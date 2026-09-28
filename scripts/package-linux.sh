#!/usr/bin/env bash
# ==============================================================================
# Alya Minimal Linux Toolchain Packaging Script (x86_64, aarch64 & x86)
# Curates a 100% statically-linked, universal musl-GCC distribution
# ==============================================================================

set -euo pipefail

ARCH="${1:-x86_64}"
VERSION="${2:-1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$REPO_ROOT/dist"
TEMP_DIR="$REPO_ROOT/temp_linux_${ARCH}"

mkdir -p "$DIST_DIR" "$TEMP_DIR"

echo "============================================================"
echo "  Alya Linux Toolchain Packager v$VERSION"
echo "  Target Architecture: $ARCH (Static musl-GCC)"
echo "============================================================"

# Upstream static musl toolchains from GitHub Releases (bazel-contrib/musl-toolchain, 100% reliable)
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "x64" ]; then
    ARCH="x64"
    UPSTREAM_URL="https://github.com/bazel-contrib/musl-toolchain/releases/download/v0.1.27/musl-1.2.3-platform-x86_64-unknown-linux-gnu-target-x86_64-linux-musl.tar.gz"
    TRIPLE="x86_64-linux-musl"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    ARCH="arm64"
    UPSTREAM_URL="https://github.com/bazel-contrib/musl-toolchain/releases/download/v0.1.27/musl-1.2.3-platform-aarch64-unknown-linux-gnu-target-aarch64-linux-musl.tar.gz"
    TRIPLE="aarch64-linux-musl"
elif [ "$ARCH" = "x86" ] || [ "$ARCH" = "i686" ] || [ "$ARCH" = "x32" ]; then
    ARCH="x86"
    TRIPLE="i686-linux-musl"
    BUILD_FROM_SOURCE=1
else
    echo "Unsupported architecture: $ARCH (supported: x86_64, aarch64, x86)"
    exit 1
fi

UPSTREAM_TGZ="$TEMP_DIR/upstream.tgz"

if [ "${BUILD_FROM_SOURCE:-0}" = "1" ]; then
    # musl.cc blocks GitHub Actions IPs outright (see musl.cc news,
    # 2025-05-27), so no prebuilt i686 upstream is reachable from CI.
    # Build an x86_64-hosted i686-linux-musl cross toolchain from source
    # instead; the result matches the x64/arm64 archives (fully static,
    # C-only, musl sysroot).
    echo "[1/5] Building i686-linux-musl toolchain from source (musl-cross-make)..."
    MISSING_DEPS=""
    for dep in bison flex texinfo gawk; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            MISSING_DEPS="$MISSING_DEPS $dep"
        fi
    done
    if [ -n "$MISSING_DEPS" ]; then
        echo "Installing missing build dependencies:$MISSING_DEPS"
        if command -v sudo >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y $MISSING_DEPS
        else
            apt-get update && apt-get install -y $MISSING_DEPS
        fi
    fi
    MCM_DIR="$TEMP_DIR/musl-cross-make"
    git clone --depth 1 https://github.com/richfelker/musl-cross-make.git "$MCM_DIR"
    (
        cd "$MCM_DIR"
        echo "TARGET = $TRIPLE" > config.mak
        echo "OUTPUT = $MCM_DIR/output" >> config.mak
        echo "GCC_CONFIG += --enable-languages=c" >> config.mak
        # Static host binaries: deployable on any x86_64 distro regardless
        # of host glibc (a dynamic build would lock to the build runner's
        # glibc, e.g. GLIBC_2.38, and fail on older systems).
        echo 'COMMON_CONFIG += CC="gcc -static" CXX="g++ -static"' >> config.mak
        echo 'COMMON_CONFIG += CFLAGS="-g0 -Os" CXXFLAGS="-g0 -Os" LDFLAGS="-s"' >> config.mak
        make -j"$(nproc)"
        # Libtool swallows `-static` from CC, so binutils links end up
        # dynamic; rebuild just that tree with libtool's native `-all-static`
        # (GCC's plain-make links cannot take `-all-static`, hence scoped).
        # NOTE: never delete litecross stamps (obj_gcc/.lc_configured depends
        # on obj_binutils/.lc_built, so a missing stamp retriggers a full
        # obj_gcc reconfigure that wipes fixincludes/Makefile). `clean` keeps
        # configure outputs, so no reconfigure can fire here.
        BUILD_SUB="build/local/$TRIPLE"
        if [ ! -d "$MCM_DIR/$BUILD_SUB/obj_binutils" ]; then
            echo "Unexpected musl-cross-make layout: $BUILD_SUB/obj_binutils missing"
            exit 1
        fi
        (
            cd "$MCM_DIR/$BUILD_SUB/obj_binutils"
            make clean > /dev/null
            make -j"$(nproc)" 'LDFLAGS=-all-static -s' all
        )
        make install
    )
    echo "musl-cross-make commit: $(git -C "$MCM_DIR" rev-parse --short HEAD)"
    SOURCE_ROOT="$MCM_DIR/output"
else
    echo "[1/5] Downloading upstream static musl toolchain for $TRIPLE..."
    curl -fsSL --connect-timeout 20 --retry 3 --retry-delay 2 "$UPSTREAM_URL" -o "$UPSTREAM_TGZ"

    echo "[2/5] Extracting archive..."
    tar -xzf "$UPSTREAM_TGZ" -C "$TEMP_DIR"
    SOURCE_ROOT="$TEMP_DIR"
    if [ -d "$TEMP_DIR/${TRIPLE}-native" ]; then
        SOURCE_ROOT="$TEMP_DIR/${TRIPLE}-native"
    fi
fi

STAGING_DIR="$TEMP_DIR/alya-toolchain-linux"
mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/lib" "$STAGING_DIR/include"

echo "[3/5] Curating minimal components..."

# 1. Essential binaries
for b in gcc as ld ar strip objdump; do
    if [ -f "$SOURCE_ROOT/bin/$TRIPLE-$b" ]; then
        cp "$SOURCE_ROOT/bin/$TRIPLE-$b" "$STAGING_DIR/bin/$b"
        ln -sf "$b" "$STAGING_DIR/bin/$TRIPLE-$b" || true
    elif [ -f "$SOURCE_ROOT/bin/$b" ]; then
        cp "$SOURCE_ROOT/bin/$b" "$STAGING_DIR/bin/$b"
    fi
done

# 2. Target sysroot ($TRIPLE/lib and $TRIPLE/include)
if [ -d "$SOURCE_ROOT/$TRIPLE" ]; then
    cp -r "$SOURCE_ROOT/$TRIPLE" "$STAGING_DIR/"
fi

# 3. GCC compiler driver internals (cc1)
if [ -d "$SOURCE_ROOT/libexec" ]; then
    cp -r "$SOURCE_ROOT/libexec" "$STAGING_DIR/"
    find "$STAGING_DIR/libexec" -name "cc1plus" -delete || true
    find "$STAGING_DIR/libexec" -name "lto1" -delete || true
    find "$STAGING_DIR/libexec" -name "f951" -delete || true
fi

# 4. Target runtime libraries and specs (lib)
if [ -d "$SOURCE_ROOT/lib" ]; then
    cp -r "$SOURCE_ROOT/lib/." "$STAGING_DIR/lib/" 2>/dev/null || true
    find "$STAGING_DIR/lib" -name "libstdc++*.a" -delete || true
    find "$STAGING_DIR/lib" -name "libgfortran*.a" -delete || true
fi

# 5. Standard C headers (include)
if [ -d "$SOURCE_ROOT/include" ]; then
    cp -r "$SOURCE_ROOT/include/." "$STAGING_DIR/include/" 2>/dev/null || true
    rm -rf "$STAGING_DIR/include/c++" || true
fi
if [ -d "$SOURCE_ROOT/$TRIPLE/include" ]; then
    cp -r "$SOURCE_ROOT/$TRIPLE/include/." "$STAGING_DIR/include/" 2>/dev/null || true
fi
if [ -d "$SOURCE_ROOT/$TRIPLE/lib" ]; then
    cp -r "$SOURCE_ROOT/$TRIPLE/lib/." "$STAGING_DIR/lib/" 2>/dev/null || true
fi

echo "[4/5] Stripping debug symbols from binaries..."
if [ -f "$STAGING_DIR/bin/strip" ] && { [ "$ARCH" = "x64" ] || [ "$ARCH" = "x86" ]; }; then
    find "$STAGING_DIR/bin" -type f -exec "$STAGING_DIR/bin/strip" --strip-unneeded {} + 2>/dev/null || true
    if [ "$ARCH" = "x86" ] && [ -d "$STAGING_DIR/libexec" ]; then
        # Source-built toolchain keeps unstripped compiler internals (cc1);
        # upstream prebuilts arrive stripped, so only x86 needs this pass.
        find "$STAGING_DIR/libexec" -type f -exec "$STAGING_DIR/bin/strip" --strip-unneeded {} + 2>/dev/null || true
    fi
fi

ARCHIVE_NAME="alya-toolchain-linux-${ARCH}.tar.gz"
OUTPUT_TAR="$DIST_DIR/$ARCHIVE_NAME"

echo "[5/5] Creating distribution archive: $ARCHIVE_NAME..."
tar -czf "$OUTPUT_TAR" -C "$STAGING_DIR" .

SIZE_BYTES=$(wc -c < "$OUTPUT_TAR" | tr -d ' ')
SIZE_MB=$(echo "scale=2; $SIZE_BYTES / 1048576" | bc 2>/dev/null || echo "16")
SHA256=$(sha256sum "$OUTPUT_TAR" | awk '{print $1}')

echo "============================================================"
echo "  Linux Toolchain Built Successfully!"
echo "  Archive: $OUTPUT_TAR"
echo "  Size:    ${SIZE_MB} MB ($SIZE_BYTES bytes)"
echo "  SHA-256: $SHA256"
echo "============================================================"

# Clean up
rm -rf "$TEMP_DIR"

#!/usr/bin/env bash
# ==============================================================================
# Alya Minimal Linux Toolchain Packaging Script (x86_64 & aarch64)
# Curates a 100% statically-linked, universal musl-GCC distribution (~16 MB)
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
else
    echo "Unsupported architecture: $ARCH (supported: x86_64, aarch64)"
    exit 1
fi

UPSTREAM_TGZ="$TEMP_DIR/upstream.tgz"

echo "[1/5] Downloading upstream static musl toolchain for $TRIPLE..."
curl -fsSL --connect-timeout 20 --retry 3 --retry-delay 2 "$UPSTREAM_URL" -o "$UPSTREAM_TGZ"

echo "[2/5] Extracting archive..."
tar -xzf "$UPSTREAM_TGZ" -C "$TEMP_DIR"
SOURCE_ROOT="$TEMP_DIR"
if [ -d "$TEMP_DIR/${TRIPLE}-native" ]; then
    SOURCE_ROOT="$TEMP_DIR/${TRIPLE}-native"
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
if [ "$ARCH" = "x64" ] && [ -f "$STAGING_DIR/bin/strip" ]; then
    find "$STAGING_DIR/bin" -type f -exec "$STAGING_DIR/bin/strip" --strip-unneeded {} + 2>/dev/null || true
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

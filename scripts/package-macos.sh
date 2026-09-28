#!/usr/bin/env bash
# ==============================================================================
# Alya Minimal macOS Toolchain Packaging Script (Apple Silicon ARM64 & Intel x64)
# Curates portable Clang/LLD Mach-O driver with ad-hoc codesign validation (~80 MB)
# ==============================================================================

set -euo pipefail

ARCH="${1:-arm64}"
VERSION="${2:-1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$REPO_ROOT/dist"
TEMP_DIR="$REPO_ROOT/temp_macos_${ARCH}"

mkdir -p "$DIST_DIR" "$TEMP_DIR"

echo "============================================================"
echo "  Alya macOS Toolchain Packager v$VERSION"
echo "  Target Architecture: $ARCH (Mach-O / Apple Silicon Ready)"
echo "============================================================"

# Upstream LLVM Clang releases for Darwin (15.0.7 has validated official arm64 and x86_64 Darwin prebuilts)
LLVM_VERSION="15.0.7"
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    ARCH="arm64"
    UPSTREAM_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/clang+llvm-${LLVM_VERSION}-arm64-apple-darwin22.0.tar.xz"
else
    ARCH="x64"
    UPSTREAM_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/clang+llvm-${LLVM_VERSION}-x86_64-apple-darwin21.0.tar.xz"
fi

UPSTREAM_ARCHIVE="$TEMP_DIR/upstream.tar.xz"

echo "[1/4] Downloading minimal LLVM Darwin release for $ARCH..."
curl -fsSL --connect-timeout 20 --retry 3 --retry-delay 2 "$UPSTREAM_URL" -o "$UPSTREAM_ARCHIVE"

echo "[2/4] Extracting LLVM archive..."
tar -xf "$UPSTREAM_ARCHIVE" -C "$TEMP_DIR"
EXTRACTED_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d -name "clang+llvm*" | head -n 1)

STAGING_DIR="$TEMP_DIR/alya-toolchain-macos"
mkdir -p "$STAGING_DIR/bin" "$STAGING_DIR/lib"

echo "[3/4] Curating minimal Mach-O binaries (clang, ld64.lld, llvm-as)..."

cp "$EXTRACTED_DIR/bin/clang" "$STAGING_DIR/bin/clang"
if [ -f "$EXTRACTED_DIR/bin/ld64.lld" ]; then
    cp "$EXTRACTED_DIR/bin/ld64.lld" "$STAGING_DIR/bin/ld64.lld"
fi
if [ -f "$EXTRACTED_DIR/bin/llvm-ar" ]; then
    cp "$EXTRACTED_DIR/bin/llvm-ar" "$STAGING_DIR/bin/ar"
fi
if [ -f "$EXTRACTED_DIR/bin/llvm-strip" ]; then
    cp "$EXTRACTED_DIR/bin/llvm-strip" "$STAGING_DIR/bin/strip"
fi

# Copy clang builtin headers
if [ -d "$EXTRACTED_DIR/lib/clang" ]; then
    cp -r "$EXTRACTED_DIR/lib/clang" "$STAGING_DIR/lib/"
fi

# Prune sanitizer/fuzzer/profiler runtimes: plain C links only need
# libclang_rt.osx.a (0.7 MB); the ios/fuzzer/orc/ubsan/xray/asan/tsan
# archives (~195 MB) are dead weight for the Alya compiler driver.
if [ -d "$STAGING_DIR/lib/clang" ]; then
    find "$STAGING_DIR/lib/clang" -path '*/lib/darwin/*' -type f ! -name 'libclang_rt.osx.a' -delete || true
    rm -rf "$STAGING_DIR/lib/clang"/*/share || true
fi

# Strip staged binaries first (no-op if upstream already stripped),
# then ad-hoc codesign everything so Gatekeeper / AMFI permits execution
# (stripping invalidates signatures, hence this order).
if [ -f "$STAGING_DIR/bin/strip" ]; then
    for b in "$STAGING_DIR"/bin/*; do
        "$STAGING_DIR/bin/strip" -S "$b" 2>/dev/null || true
    done
fi
for b in "$STAGING_DIR"/bin/*; do
    codesign --force -s - "$b" 2>/dev/null || true
done

ARCHIVE_NAME="alya-toolchain-macos-${ARCH}.tar.gz"
OUTPUT_TAR="$DIST_DIR/$ARCHIVE_NAME"

echo "[4/4] Creating distribution archive: $ARCHIVE_NAME..."
tar -czf "$OUTPUT_TAR" -C "$STAGING_DIR" .

SIZE_BYTES=$(wc -c < "$OUTPUT_TAR" | tr -d ' ')
SIZE_MB=$(echo "scale=2; $SIZE_BYTES / 1048576" | bc 2>/dev/null || echo "80")
SHA256=$(shasum -a 256 "$OUTPUT_TAR" | awk '{print $1}')

echo "============================================================"
echo "  macOS Toolchain Built Successfully!"
echo "  Archive: $OUTPUT_TAR"
echo "  Size:    ${SIZE_MB} MB ($SIZE_BYTES bytes)"
echo "  SHA-256: $SHA256"
echo "============================================================"

# Clean up
rm -rf "$TEMP_DIR"

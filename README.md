# Alya Multi-Platform Minimal Toolchain (`alya-toolchain`)

Official ultra-lightweight, zero-friction C, Clang, and GNU Assembler toolchain suite for the [Alya Programming Language](https://github.com/alya-lang).

---

## Overview

Alya compiles directly to native GNU/Mach-O assembly and links with native OS runtime libraries (`ws2_32`, `kernel32`, `libc`, `libm`, `libpthread`, Darwin `libSystem.B.dylib`, C FFI, and embedded SQLite3).

Standard compiler installations (MinGW-w64, full LLVM, or Xcode) often require hundreds of megabytes or manual system configuration. This repository provides an automated packaging pipeline that builds and verifies **ultra-compact, portable toolchain archives (~16–24 MB)** tailored specifically for the `alyac` compiler across all major platforms.

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ALYA MULTI-PLATFORM TOOLCHAIN MATRIX                     │
├───────────────────┬────────────────────┬────────────────────────────────────┤
│ Windows (x64)     │ MinGW-w64 Minimal  │ gcc.exe, as.exe, ld.exe, ws2_32    │
│ Linux (x64)       │ Universal musl-GCC │ Static gcc, as, ld (no glibc lock) │
│ Linux (ARM64)     │ Universal musl-GCC │ Static aarch64 gcc, as, ld         │
│ macOS (Apple Sil) │ Darwin Clang + LLD │ Mach-O clang, ld64.lld, codesign   │
│ macOS (Intel x64) │ Darwin Clang + LLD │ Mach-O x64 clang, ld64.lld         │
└───────────────────┴────────────────────┴────────────────────────────────────┘
```

---

## Supported Platform Matrix

| Platform Target | Architecture | Archive Format | Size (Compressed) | Build Driver |
| :--- | :--- | :--- | :--- | :--- |
| **`x86_64-pc-windows-gnu`** | Windows x64 | `.zip` | ~18 MB | `scripts/package.ps1` |
| **`x86_64-unknown-linux-musl`** | Linux x64 | `.tar.gz` | ~16 MB | `scripts/package-linux.sh x86_64` |
| **`aarch64-unknown-linux-musl`**| Linux ARM64 | `.tar.gz` | ~16 MB | `scripts/package-linux.sh aarch64` |
| **`aarch64-apple-darwin`** | macOS Apple Silicon | `.tar.gz` | ~24 MB | `scripts/package-macos.sh arm64` |
| **`x86_64-apple-darwin`** | macOS Intel x64 | `.tar.gz` | ~24 MB | `scripts/package-macos.sh x64` |

---

## Features

- 🪶 **Ultra-Compact**: Archives are strictly stripped down to essential compiler, assembler, linker, and CRT objects (averaging 16–24 MB).
- ⚡ **Zero Configuration**: Portable and self-contained; operates seamlessly from `~/.alya/toolchain` without touching system `PATH`.
- 🐧 **Universal Linux Binary**: Linux archives are 100% statically linked against musl libc, running out of the box on Ubuntu, Debian, Alpine, Arch, Fedora, and minimal container images.
- 🍏 **Apple Silicon & Mach-O Ready**: macOS archives bundle Darwin Mach-O linkers with ad-hoc code-signing validation for Apple Silicon security requirements.
- 🔒 **Cryptographically Verified**: All platform archives are recorded with exact SHA-256 checksums in [`toolchain.json`](toolchain.json).

---

## Building & Packaging

### Windows x64
```powershell
./scripts/package.ps1 -Version 1.0.0
./scripts/verify.ps1 -ToolchainPath dist/alya-toolchain-windows-x64.zip
```

### Linux (x64 / ARM64)
```bash
./scripts/package-linux.sh x86_64 1.0.0
./scripts/package-linux.sh aarch64 1.0.0
```

### macOS (Apple Silicon / Intel)
```bash
./scripts/package-macos.sh arm64 1.0.0
./scripts/package-macos.sh x64 1.0.0
```

---

## License

This packaging framework and automation scripts are licensed under the [MIT License](LICENSE).  
Underlying compiler binaries are subject to their respective open-source licenses (GPLv3 with GCC Runtime Exception, MinGW-w64 runtime license, LLVM/Apache 2.0 with LLVM Exception).

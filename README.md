# Alya Minimal Toolchain (`alya-toolchain`)

Official ultra-lightweight, zero-friction C and GNU Assembler toolchain for the [Alya Programming Language](https://github.com/alya-lang).

---

## Overview

Alya compiles directly to native GNU/Mach-O assembly and links with native OS libraries (e.g. `ws2_32`, `kernel32`, C FFI, and embedded SQLite3). 

On Windows, standard MinGW-w64 installations often exceed 100–300 MB and require manual environment variable configuration. This repository provides an automated, reproducible packaging pipeline that strips down an upstream MinGW-w64 distribution to an **ultra-compact ~18 MB archive** containing only the exact components required by the `alyac` compiler.

```text
┌─────────────────────────────────────────────────────────────┐
│                 ALYA MINIMAL TOOLCHAIN (~18 MB)             │
├───────────────────────────────┬─────────────────────────────┤
│ 1. Core Binaries              │ 2. Target CRT & Import Libs │
│    • gcc.exe                  │    • crt2.o, crtbegin.o     │
│    • as.exe (GNU Assembler)   │    • libkernel32.a          │
│    • ld.exe (GNU Linker)      │    • libws2_32.a (std/net)  │
│    • ar.exe, strip.exe        │    • libmsvcrt.a, libm.a    │
├───────────────────────────────┼─────────────────────────────┤
│ 3. Compiler Backend           │ 4. Essential C Headers      │
│    • cc1.exe (C driver)       │    • stdio, stdlib, string  │
│    • libgcc.a, specs          │    • windows.h, winsock2.h  │
└───────────────────────────────┴─────────────────────────────┘
```

---

## Features

- 🪶 **Ultra-Compact**: Compressed archive is ≤ 18 MB (uncompressed ~60 MB), compared to standard 150+ MB distributions.
- ⚡ **Zero Configuration**: Self-contained and portable; operates without requiring system `PATH` registration or registry keys.
- 🌐 **Full Network & Win32 Support**: Includes complete WinSock2 (`libws2_32.a`) and Windows API imports for `std/net` and `std/os`.
- 🔌 **C FFI & Amalgamation Ready**: Ships standard Win32 C headers (`windows.h`, `winsock2.h`, `stdio.h`) required for compiling embedded C sources (such as SQLite3).
- 🔒 **Cryptographically Verified**: Every release is paired with a SHA-256 checksum recorded in [`toolchain.json`](toolchain.json).

---

## Directory Structure

When unpacked (e.g. inside `~/.alya/toolchain`), the tree is organized as follows:

```text
~/.alya/toolchain/
├── bin/
│   ├── gcc.exe
│   ├── as.exe
│   ├── ld.exe
│   ├── ld.bfd.exe
│   ├── ar.exe
│   └── strip.exe
├── lib/
│   └── gcc/x86_64-w64-mingw32/<ver>/
│       ├── crtbegin.o
│       ├── crtend.o
│       └── libgcc.a
├── libexec/
│   └── gcc/x86_64-w64-mingw32/<ver>/
│       └── cc1.exe
└── x86_64-w64-mingw32/
    ├── include/ (C & Win32 headers)
    └── lib/ (CRT & Win32 import .a libraries)
```

---

## Building & Packaging

### Prerequisites
- Windows 10/11 x64
- PowerShell 7+

### Run Packager
To download upstream artifacts, curate minimal binaries, strip debug symbols, and produce the distribution ZIP:

```powershell
./scripts/package.ps1 -Version 1.0.0
```

The resulting package is written to `dist/alya-toolchain-windows-x64.zip` and [`toolchain.json`](toolchain.json) is updated automatically.

---

## Verification & Testing

To test the generated archive against real-world assembly and C Winsock linking:

```powershell
./scripts/verify.ps1 -ToolchainPath dist/alya-toolchain-windows-x64.zip
```

The verification suite:
1. Unpacks the archive into a scratch directory.
2. Emits an Intel-syntax GNU assembly test file simulating `alyac` codegen and compiles it to an executable.
3. Emits a C file with Winsock2 initialization (`WSAStartup`) and links it with `-lws2_32`.
4. Executes both test binaries and asserts exit code `0` and proper output.

---

## License

This packaging framework and scripts are licensed under the [MIT License](LICENSE).  
Underlying MinGW-w64 and GCC binaries are subject to their respective open-source licenses (GPLv3 with Runtime Exception, MinGW-w64 runtime license).

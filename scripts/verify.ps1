# ==============================================================================
# Alya Toolchain Verification Script
# Validates assembler, linker, CRT, and Winsock linking without system PATH
# ==============================================================================

[CmdletBinding()]
param(
    [string]$ToolchainPath = "dist/alya-toolchain-windows-x64.zip",
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64",
    [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Alya Toolchain Verifier" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$TempDir = Join-Path $RepoRoot "temp_verification"
if (Test-Path $TempDir) {
    Remove-Item -Recurse -Force $TempDir
}
New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

$ResolvedPath = if ([System.IO.Path]::IsPathRooted($ToolchainPath)) {
    $ToolchainPath
} else {
    Join-Path $RepoRoot $ToolchainPath
}

if (-not (Test-Path $ResolvedPath)) {
    throw "Toolchain path not found: $ResolvedPath"
}

$ToolchainDir = $null
if ((Get-Item $ResolvedPath) -is [System.IO.DirectoryInfo]) {
    $ToolchainDir = $ResolvedPath
} else {
    Write-Host "[1/4] Unpacking toolchain archive for testing..." -ForegroundColor Yellow
    $UnpackDir = Join-Path $TempDir "unpacked"
    Expand-Archive -Path $ResolvedPath -DestinationPath $UnpackDir -Force
    $ToolchainDir = $UnpackDir
}

$GccExe = Join-Path $ToolchainDir "bin\gcc.exe"
if (-not (Test-Path $GccExe)) {
    throw "Fatal: gcc.exe not found at $GccExe"
}

Write-Host "  Compiler detected: $GccExe" -ForegroundColor Gray
$GccVersionOut = & $GccExe --version | Select-Object -First 1
Write-Host "  Version string:    $GccVersionOut" -ForegroundColor Gray

# ------------------------------------------------------------------------------
# Test 1: Native Assembly linking (Alya Codegen simulation)
# ------------------------------------------------------------------------------
Write-Host "[2/4] Testing Assembly compilation (Alya assembly simulator)..." -ForegroundColor Yellow

if ($Arch -eq "x64") {
$AsmSource = @"
    .text
    .globl main
    .def main; .scl 2; .type 32; .endef
main:
    subq `$40, %rsp
    leaq msg(%rip), %rcx
    call puts
    xorl %eax, %eax
    addq `$40, %rsp
    ret

    .data
msg:
    .string "SUCCESS: Alya Assembly Native Execution"
"@
} else {
$AsmSource = @"
    .text
    .globl main
    .def main; .scl 2; .type 32; .endef
main:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    adrp x0, msg
    add x0, x0, :lo12:msg
    bl puts
    mov w0, #0
    ldp x29, x30, [sp], #16
    ret

    .data
msg:
    .string "SUCCESS: Alya Assembly Native Execution (ARM64)"
"@
}

$AsmFile = Join-Path $TempDir "test_asm.s"
$AsmExe = Join-Path $TempDir "test_asm.exe"
Set-Content -Path $AsmFile -Value $AsmSource -Encoding UTF8

$AsmCompOut = & $GccExe $AsmFile -o $AsmExe 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Assembly compilation failed: $AsmCompOut"
}

$RunAsmOut = & $AsmExe
if ($LASTEXITCODE -ne 0 -or $RunAsmOut -notmatch "SUCCESS") {
    throw "Assembly execution failed! Output: $RunAsmOut"
}
Write-Host "  ✓ Assembly compiled and executed successfully!" -ForegroundColor Green

# ------------------------------------------------------------------------------
# Test 2: C + Winsock2 Linking (std/net & FFI simulation)
# ------------------------------------------------------------------------------
Write-Host "[3/4] Testing C FFI & Winsock2 linking (-lws2_32)..." -ForegroundColor Yellow

$CSource = @"
#include <stdio.h>
#include <winsock2.h>

int main() {
    WSADATA wsa;
    int res = WSAStartup(MAKEWORD(2, 2), &wsa);
    if (res == 0) {
        printf("SUCCESS: Winsock2 Initialized (v%d.%d)\n", 
               LOBYTE(wsa.wVersion), HIBYTE(wsa.wVersion));
        WSACleanup();
        return 0;
    }
    return 1;
}
"@

$CFile = Join-Path $TempDir "test_sock.c"
$CExe = Join-Path $TempDir "test_sock.exe"
Set-Content -Path $CFile -Value $CSource -Encoding UTF8

$CCompOut = & $GccExe $CFile -o $CExe -lws2_32 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "C/Winsock compilation failed: $CCompOut"
}

$RunCOut = & $CExe
if ($LASTEXITCODE -ne 0 -or $RunCOut -notmatch "SUCCESS") {
    throw "C/Winsock execution failed! Output: $RunCOut"
}
Write-Host "  ✓ C FFI & Winsock2 compiled and executed successfully!" -ForegroundColor Green

Write-Host "[4/4] Cleaning test scratch directory..." -ForegroundColor Yellow
if (-not $KeepTemp) {
    Remove-Item -Recurse -Force $TempDir
}

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  All Verification Tests Passed! Toolchain is 100% Ready." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green

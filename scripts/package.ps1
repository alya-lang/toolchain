# ==============================================================================
# Alya Minimal Toolchain Packaging Script
# Curates ultra-lightweight C & Assembler distributions for Windows:
#   x64   -> MinGW-w64 minimal distribution (upstream: skeeto/w64devkit)
#   arm64 -> LLVM-MinGW distribution for Windows on ARM64
#          (upstream: mstorsjo/llvm-mingw, ucrt-aarch64 host build)
# ==============================================================================

[CmdletBinding()]
param(
    [string]$Version = "1.0.0",
    [ValidateSet("x64", "arm64", "x86")]
    [string]$Arch = "x64",
    [string]$W64DevkitVersion = "2.10.0",
    [string]$LlvmMingwVersion = "20260922",
    [string]$OutputDir = "dist",
    [switch]$SkipDownload,
    [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$DistPath = Join-Path $RepoRoot $OutputDir
$CacheDir = Join-Path $RepoRoot "cache"
$TempPath = Join-Path $RepoRoot "temp_packaging"

if ($Arch -eq "x64") {
    $ArchiveName = "alya-toolchain-windows-x64.zip"
    $TargetLabel = "Windows x64 (MinGW-w64 Minimal Distribution)"
    $ManifestKey = "x86_64-pc-windows-gnu"
} elseif ($Arch -eq "x86") {
    $ArchiveName = "alya-toolchain-windows-x86.zip"
    $TargetLabel = "Windows x86 (MinGW-w64 Minimal Distribution)"
    $ManifestKey = "i686-pc-windows-gnu"
} else {
    $ArchiveName = "alya-toolchain-windows-arm64.zip"
    $TargetLabel = "Windows ARM64 (LLVM-MinGW Distribution)"
    $ManifestKey = "aarch64-pc-windows-gnu"
}
$OutputZip = Join-Path $DistPath $ArchiveName

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Alya Toolchain Packager v$Version" -ForegroundColor Cyan
Write-Host "  Target: $TargetLabel" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path $TempPath) {
    Remove-Item -Recurse -Force $TempPath
}
New-Item -ItemType Directory -Force -Path $DistPath | Out-Null
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
New-Item -ItemType Directory -Force -Path $TempPath | Out-Null

if ($Arch -eq "x64" -or $Arch -eq "x86") {
    $W64Arch = if ($Arch -eq "x86") { "x86" } else { "x64" }
    $UpstreamExeUrl = "https://github.com/skeeto/w64devkit/releases/download/v$W64DevkitVersion/w64devkit-$W64Arch-$W64DevkitVersion.7z.exe"
    $DownloadedExe = Join-Path $CacheDir "w64devkit-$W64Arch.7z.exe"
} else {
    $UpstreamExeUrl = "https://github.com/mstorsjo/llvm-mingw/releases/download/$LlvmMingwVersion/llvm-mingw-$LlvmMingwVersion-ucrt-aarch64.zip"
    $DownloadedExe = Join-Path $CacheDir "llvm-mingw-ucrt-aarch64.zip"
}

if (-not $SkipDownload -and -not (Test-Path $DownloadedExe)) {
    Write-Host "[1/6] Downloading upstream archive..." -ForegroundColor Yellow
    Write-Host "  $UpstreamExeUrl" -ForegroundColor Gray
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $UpstreamExeUrl -OutFile $DownloadedExe -UseBasicParsing
    Write-Host "  Downloaded successfully." -ForegroundColor Green
} else {
    Write-Host "[1/6] Using cached upstream archive ($DownloadedExe)..." -ForegroundColor Yellow
}

Write-Host "[2/6] Extracting upstream archive..." -ForegroundColor Yellow
$ExtractStage = Join-Path $TempPath "extracted"
New-Item -ItemType Directory -Force -Path $ExtractStage | Out-Null

if ($Arch -ne "arm64") {
    tar.exe -xf $DownloadedExe -C $ExtractStage

    $SourceRoot = Join-Path $ExtractStage "w64devkit"
    if (-not (Test-Path $SourceRoot)) {
        $SourceRoot = $ExtractStage
    }
} else {
    Expand-Archive -Path $DownloadedExe -DestinationPath $ExtractStage -Force

    $SourceRoot = Join-Path $ExtractStage "llvm-mingw-$LlvmMingwVersion-ucrt-aarch64"
    if (-not (Test-Path $SourceRoot)) {
        throw "Unexpected llvm-mingw layout: $SourceRoot not found"
    }
}

Write-Host "[3/6] Curating minimal toolchain components..." -ForegroundColor Yellow
$StagingDir = Join-Path $TempPath "alya-toolchain"
New-Item -ItemType Directory -Force -Path $StagingDir | Out-Null

if ($Arch -ne "arm64") {
    # 1. Essential binaries
    Write-Host "  Copying core binaries (bin)..." -ForegroundColor Gray
    $BinTarget = Join-Path $StagingDir "bin"
    New-Item -ItemType Directory -Force -Path $BinTarget | Out-Null

    $EssentialBins = @(
        "gcc.exe",
        "as.exe",
        "ld.exe",
        "ld.bfd.exe",
        "ar.exe",
        "strip.exe",
        "objdump.exe"
    )

    foreach ($bin in $EssentialBins) {
        $srcBin = Join-Path $SourceRoot "bin\$bin"
        if (Test-Path $srcBin) {
            Copy-Item $srcBin $BinTarget
        }
    }

    # 2. GCC Compiler internals (cc1.exe)
    Write-Host "  Copying GCC compiler internals (libexec)..." -ForegroundColor Gray
    $LibExecSrc = Join-Path $SourceRoot "libexec"
    if (Test-Path $LibExecSrc) {
        Copy-Item -Recurse $LibExecSrc $StagingDir

        # Remove C++ compiler internals and LTO to save ~50 MB
        Get-ChildItem -Path (Join-Path $StagingDir "libexec") -Recurse -Filter "cc1plus.exe" | Remove-Item -Force
        Get-ChildItem -Path (Join-Path $StagingDir "libexec") -Recurse -Filter "lto1.exe" | Remove-Item -Force
        Get-ChildItem -Path (Join-Path $StagingDir "libexec") -Recurse -Filter "lto-dump.exe" | Remove-Item -Force
        Get-ChildItem -Path (Join-Path $StagingDir "libexec") -Recurse -Filter "f951.exe" | Remove-Item -Force
    }

    # 3. Target CRT, static libraries, and GCC specs (lib)
    Write-Host "  Copying Win32 CRT and core libraries (lib)..." -ForegroundColor Gray
    $LibSrc = Join-Path $SourceRoot "lib"
    if (Test-Path $LibSrc) {
        Copy-Item -Recurse $LibSrc $StagingDir

        $StagingLib = Join-Path $StagingDir "lib"
        # Remove C++ and Fortran static libraries to save space
        Get-ChildItem -Path $StagingLib -Recurse -Include "libstdc++*.a", "libsupc++*.a", "libgfortran*.a" | Remove-Item -Force
    }

    # 4. Standard C & Win32 headers (include)
    Write-Host "  Copying standard C and Win32 headers (include)..." -ForegroundColor Gray
    $IncSrc = Join-Path $SourceRoot "include"
    if (Test-Path $IncSrc) {
        Copy-Item -Recurse $IncSrc $StagingDir

        # Remove C++ headers to save ~30 MB
        $CppInc = Join-Path $StagingDir "include\c++"
        if (Test-Path $CppInc) {
            Remove-Item -Recurse -Force $CppInc
        }
    }
} else {
    # ARM64 curation from llvm-mingw (multi-target distribution: keep the
    # aarch64 slice plus the shared headers and Clang resource dir only).
    $TargetPrefix = "aarch64-w64-mingw32"
    $UpstreamBin = Join-Path $SourceRoot "bin"

    # 1. Canonical driver binaries (alya probes bin\gcc.exe, then clang.exe)
    Write-Host "  Copying canonical driver binaries (bin)..." -ForegroundColor Gray
    $BinTarget = Join-Path $StagingDir "bin"
    New-Item -ItemType Directory -Force -Path $BinTarget | Out-Null

    $DriverMap = @{
        "$TargetPrefix-gcc.exe"   = "gcc.exe"
        "$TargetPrefix-clang.exe" = "clang.exe"
        "$TargetPrefix-as.exe"    = "as.exe"
        "$TargetPrefix-ar.exe"    = "ar.exe"
        "$TargetPrefix-strip.exe" = "strip.exe"
        "$TargetPrefix-dlltool.exe" = "dlltool.exe"
        "$TargetPrefix-windres.exe" = "windres.exe"
        "llvm-objdump.exe"        = "objdump.exe"
    }

    foreach ($srcName in $DriverMap.Keys) {
        $srcBin = Join-Path $UpstreamBin $srcName
        if (-not (Test-Path $srcBin)) {
            throw "Required upstream binary missing: $srcName"
        }
        Copy-Item $srcBin (Join-Path $BinTarget $DriverMap[$srcName])
    }

    # LLD (invoked internally by the clang driver) plus target-selection
    # configs and runtime DLLs required by the staged executables.
    $LdLld = Join-Path $UpstreamBin "ld.lld.exe"
    if (-not (Test-Path $LdLld)) {
        throw "Required upstream binary missing: ld.lld.exe"
    }
    Copy-Item $LdLld $BinTarget
    Copy-Item (Join-Path $UpstreamBin "*.cfg") $BinTarget
    Get-ChildItem -Path $UpstreamBin -Filter "*.dll" | Copy-Item -Destination $BinTarget

    # 2. Target sysroot (CRT objects, import libraries, target DLLs)
    Write-Host "  Copying aarch64 sysroot ($TargetPrefix)..." -ForegroundColor Gray
    $SysrootSrc = Join-Path $SourceRoot $TargetPrefix
    if (-not (Test-Path $SysrootSrc)) {
        throw "Upstream sysroot missing: $TargetPrefix"
    }
    Copy-Item -Recurse $SysrootSrc $StagingDir

    # 3. Shared MinGW headers (single copy serves all targets)
    Write-Host "  Copying shared MinGW headers (include)..." -ForegroundColor Gray
    $IncSrc = Join-Path $SourceRoot "include"
    if (-not (Test-Path $IncSrc)) {
        throw "Upstream include directory missing"
    }
    Copy-Item -Recurse $IncSrc $StagingDir

    # 4. Clang resource dir: builtin headers + aarch64 runtime libraries.
    # The major version is discovered dynamically to survive upstream bumps.
    Write-Host "  Copying Clang resource dir (builtins)..." -ForegroundColor Gray
    $ClangBase = Join-Path $SourceRoot "lib\clang"
    $ClangVerDir = Get-ChildItem -Path $ClangBase -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $ClangVerDir) {
        throw "Upstream Clang resource directory missing under lib\clang"
    }
    $ClangStaging = Join-Path $StagingDir "lib\clang\$($ClangVerDir.Name)"
    New-Item -ItemType Directory -Force -Path (Join-Path $ClangStaging "include") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $ClangStaging "lib\windows") | Out-Null
    Copy-Item -Recurse (Join-Path $ClangVerDir.FullName "include\*") (Join-Path $ClangStaging "include")
    Get-ChildItem -Path (Join-Path $ClangVerDir.FullName "lib\windows") -Filter "*aarch64*" | Copy-Item -Destination (Join-Path $ClangStaging "lib\windows")
    if (-not (Get-ChildItem -Path (Join-Path $ClangStaging "lib\windows"))) {
        throw "No aarch64 runtime libraries found in Clang resource dir"
    }
}

Write-Host "[4/6] Stripping debug symbols from executables..." -ForegroundColor Yellow
$StripExe = Join-Path $BinTarget "strip.exe"
if (Test-Path $StripExe) {
    Get-ChildItem -Path $StagingDir -Recurse -Include "*.exe", "*.dll" | ForEach-Object {
        try {
            & $StripExe --strip-unneeded $_.FullName 2>$null
        } catch { }
    }
}

Write-Host "[5/6] Creating final zip package: $ArchiveName..." -ForegroundColor Yellow
if (Test-Path $OutputZip) {
    Remove-Item -Force $OutputZip
}
Compress-Archive -Path "$StagingDir\*" -DestinationPath $OutputZip -CompressionLevel Optimal

$ZipBytes = (Get-Item $OutputZip).Length
$ZipMb = [math]::Round($ZipBytes / 1MB, 2)
$Sha256 = (Get-FileHash -Path $OutputZip -Algorithm SHA256).Hash.ToLower()

Write-Host "[6/6] Updating toolchain.json manifest..." -ForegroundColor Yellow
$ManifestFile = Join-Path $RepoRoot "toolchain.json"
if (Test-Path $ManifestFile) {
    $json = Get-Content $ManifestFile -Raw | ConvertFrom-Json
    if ($json.platforms -and $json.platforms.$ManifestKey) {
        $json.platforms.$ManifestKey.archive.sha256 = $Sha256
        $json.platforms.$ManifestKey.archive.compressed_size_mb = [int][math]::Ceiling($ZipMb)
    } elseif ($json.archive) {
        $json.archive.sha256 = $Sha256
        $json.archive.compressed_size_mb = [int][math]::Ceiling($ZipMb)
    }
    $json.version = $Version
    $json | ConvertTo-Json -Depth 10 | Set-Content -Path $ManifestFile -Encoding UTF8
}

if (-not $KeepTemp) {
    Remove-Item -Recurse -Force $TempPath
}

Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Build Completed Successfully!" -ForegroundColor Green
Write-Host "  Archive:  $OutputZip" -ForegroundColor Cyan
Write-Host "  Size:     $ZipMb MB ($ZipBytes bytes)" -ForegroundColor Cyan
Write-Host "  SHA-256:  $Sha256" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Green

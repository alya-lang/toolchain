# ==============================================================================
# Alya Minimal Toolchain Packaging Script
# Curates an ultra-lightweight MinGW-w64 C & GNU Assembler distribution
# ==============================================================================

[CmdletBinding()]
param(
    [string]$Version = "1.0.0",
    [string]$W64DevkitVersion = "2.10.0",
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
$ArchiveName = "alya-toolchain-windows-x64.zip"
$OutputZip = Join-Path $DistPath $ArchiveName

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Alya Toolchain Packager v$Version" -ForegroundColor Cyan
Write-Host "  Target: Windows x64 (MinGW-w64 Minimal Distribution)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (Test-Path $TempPath) {
    Remove-Item -Recurse -Force $TempPath
}
New-Item -ItemType Directory -Force -Path $DistPath | Out-Null
New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
New-Item -ItemType Directory -Force -Path $TempPath | Out-Null

$UpstreamExeUrl = "https://github.com/skeeto/w64devkit/releases/download/v$W64DevkitVersion/w64devkit-x64-$W64DevkitVersion.7z.exe"
$DownloadedExe = Join-Path $CacheDir "w64devkit.7z.exe"

if (-not $SkipDownload -and -not (Test-Path $DownloadedExe)) {
    Write-Host "[1/6] Downloading upstream w64devkit v$W64DevkitVersion..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $UpstreamExeUrl -OutFile $DownloadedExe -UseBasicParsing
    Write-Host "  Downloaded successfully." -ForegroundColor Green
} else {
    Write-Host "[1/6] Using cached upstream archive ($DownloadedExe)..." -ForegroundColor Yellow
}

Write-Host "[2/6] Extracting upstream archive using tar.exe..." -ForegroundColor Yellow
$ExtractStage = Join-Path $TempPath "extracted"
New-Item -ItemType Directory -Force -Path $ExtractStage | Out-Null

tar.exe -xf $DownloadedExe -C $ExtractStage

$SourceRoot = Join-Path $ExtractStage "w64devkit"
if (-not (Test-Path $SourceRoot)) {
    $SourceRoot = $ExtractStage
}

Write-Host "[3/6] Curating minimal toolchain components..." -ForegroundColor Yellow
$StagingDir = Join-Path $TempPath "alya-toolchain"
New-Item -ItemType Directory -Force -Path $StagingDir | Out-Null

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

Write-Host "[4/6] Stripping debug symbols from executables..." -ForegroundColor Yellow
$StripExe = Join-Path $BinTarget "strip.exe"
if (Test-Path $StripExe) {
    Get-ChildItem -Path $StagingDir -Recurse -Filter "*.exe" | ForEach-Object {
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
    $json.archive.sha256 = $Sha256
    $json.archive.compressed_size_mb = [math]::Ceiling($ZipMb)
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

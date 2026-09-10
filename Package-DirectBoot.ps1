# Package-DirectBoot.ps1
# Builds a clean distributable zip for testers:
#   dist\NVPermissive-DirectBoot-<timestamp>.zip
#
# Does NOT need administrator rights. Before packing it:
#   1. verifies every tool-file SHA256 hash (never ships a corrupted file)
#   2. ships ONLY the files testers need (no .git, no dev leftovers)
#   3. generates SHA256SUMS.txt inside the package for on-site verification
#
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File Package-DirectBoot.ps1
#         (or just double-click Package-DirectBoot.bat)
param([string]$OutDir)
$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty when invoked through a scriptblock; fall back to cwd.
$base = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
. (Join-Path $base 'Bcd.Common.ps1')

if (-not $OutDir) { $OutDir = Join-Path $base 'dist' }

# Everything testers receive. Package-DirectBoot.* and snapshots/dev files
# stay OUT of the package on purpose.
$ship = @(
    'NVPermissiveDirect.efi',
    'NVPermissiveEFI.efi',
    'BOOTX64.EFI',
    'startup.nsh',
    'Bcd.Common.ps1',
    'Install-DirectBoot.ps1',
    'Rollback-DirectBoot.ps1',
    'install.bat',
    'install_test.bat',
    'Rollback-DirectBoot.bat',
    'README.txt',
    'README.md',
    '使用教程.txt'
)

# ---- 1. Pre-flight: every file present, tool hashes correct ----
foreach ($f in $ship) {
    if (-not (Test-Path (Join-Path $base $f))) { Fail "Missing file '$f' - cannot pack." }
}
foreach ($name in $ToolHashes.Keys) {
    $h = (Get-FileHash (Join-Path $base $name) -Algorithm SHA256).Hash
    if ($h -ne $ToolHashes[$name]) {
        Fail "Hash mismatch for '$name' - fix or re-pin it BEFORE packing (never ship a corrupted tool)."
    }
}
Ok ('All ' + $ToolHashes.Count + ' tool file hashes verified.')

# ---- 2. Stage a clean package folder ----
$pkgName = 'NVPermissive-DirectBoot-' + (Get-Date -Format 'yyyyMMdd-HHmm')
$stage = Join-Path ([IO.Path]::GetTempPath()) $pkgName
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$null = New-Item -ItemType Directory -Force $stage
foreach ($f in $ship) { Copy-Item (Join-Path $base $f) $stage -Force }

# ---- 3. SHA256 manifest inside the package ----
$lines = foreach ($f in ($ship | Sort-Object)) {
    $h = (Get-FileHash (Join-Path $stage $f) -Algorithm SHA256).Hash
    '{0}  {1}' -f $h.ToLower(), $f
}
$lines | Set-Content (Join-Path $stage 'SHA256SUMS.txt') -Encoding UTF8
Ok 'SHA256SUMS.txt generated.'

# ---- 4. Zip it (top-level folder survives extraction) ----
if (-not (Test-Path $OutDir)) { $null = New-Item -ItemType Directory -Force $OutDir }
$zip = Join-Path $OutDir "$pkgName.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal
Remove-Item $stage -Recurse -Force

$zipHash = (Get-FileHash $zip -Algorithm SHA256).Hash
$size = '{0:N0} KB' -f ((Get-Item $zip).Length / 1KB)
Info ''
Info '=================== PACKAGE READY ==================='
Ok "Package: $zip ($size)"
Info ("Zip SHA256 (send this too, testers can verify the archive):")
Info ("  " + $zipHash)
Info ''
Info 'Contents: ' + ($ship.Count + 1) + ' files (incl. SHA256SUMS.txt)'

# Rollback-DirectBoot.ps1
# Default : removes the direct-boot entry + patched file only (shell fallback chain stays).
# -Full   : also removes the shell unlock entry and all tool files (full uninstall).
$ErrorActionPreference = 'Stop'
param([switch]$Full)
function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Info($msg) { Write-Host $msg }

$descDirect = 'NVPermissive Direct Boot'
$descShell  = 'NVPermissive 90HX Unlock'

$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$adm = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $adm.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'This script must run as Administrator.'
}

function Find-Entry([string]$desc) {
    $curId = $null
    foreach ($ln in (bcdedit /enum firmware | Out-String -Stream)) {
        if ($ln -match '^\s*identifier\s+(\{[0-9a-fA-F-]+\})') { $curId = $Matches[1] }
        elseif ($ln -match ('description\s+' + [regex]::Escape($desc))) { return $curId }
    }
    return $null
}

$esp = $null
foreach ($letter in 'S','T','U','V','W') {
    $drv = "$letter`:"
    if (Test-Path "$drv\") { continue }
    $null = mountvol $drv /S
    if (Test-Path "$drv\") { $esp = $drv; break }
}
if (-not $esp) { Fail 'Could not mount the EFI System Partition (ESP). Nothing was changed.' }
if (-not (Test-Path "$esp\EFI\Microsoft\Boot\bootmgfw.efi")) {
    $null = mountvol "$esp\" /D
    Fail 'ESP mounted but Windows boot files are missing. Unexpected partition layout - aborted, nothing was changed.'
}
Info "ESP mounted at $esp"

$removed = @()

# ---- direct entry + patched file ----
$gDirect = Find-Entry $descDirect
if ($gDirect) {
    $null = bcdedit /delete $gDirect /f
    Ok "Deleted boot entry: $gDirect ($descDirect)"
    $removed += $gDirect
} else {
    Info 'No direct boot entry found (already removed).'
}
if (Test-Path "$esp\EFI\NVPermissive\NVPermissiveDirect.efi") {
    Remove-Item "$esp\EFI\NVPermissive\NVPermissiveDirect.efi" -Force
    Ok 'Deleted \EFI\NVPermissive\NVPermissiveDirect.efi from ESP.'
}

# ---- full uninstall: shell entry + tool files ----
if ($Full) {
    $gShell = Find-Entry $descShell
    if ($gShell) {
        $null = bcdedit /delete $gShell /f
        Ok "Deleted boot entry: $gShell ($descShell)"
        $removed += $gShell
    }
    if (Test-Path "$esp\EFI\NVPermissive") {
        Remove-Item "$esp\EFI\NVPermissive" -Recurse -Force
        Ok 'Deleted \EFI\NVPermissive from ESP.'
    }
    if (Test-Path "$esp\startup.nsh")  { Remove-Item "$esp\startup.nsh" -Force }
    if (Test-Path "$esp\NVPermissiveEFI.efi") { Remove-Item "$esp\NVPermissiveEFI.efi" -Force }
    Ok 'Deleted root-level tool files from ESP.'
}

# ---- clean displayorder of deleted entries ----
# NOTE: displayorder in bcdedit output can span MULTIPLE lines - parse the whole block.
$fwTxt = bcdedit /enum '{fwbootmgr}' | Out-String
$orderStr = ''
if ($fwTxt -match '(?s)displayorder\s+(.*?)\s*\r?\n\s*timeout') { $orderStr = $Matches[1] }
elseif ($fwTxt -match '(?s)displayorder\s+(.*)$') { $orderStr = $Matches[1] }
$curOrder = @($orderStr -split '\s+' | Where-Object { $_ -match '^\{[0-9a-fA-F-]+\}$' })
$newOrder = @($curOrder | Where-Object { $removed -notcontains $_ })
if ($newOrder.Count -ne $curOrder.Count) {
    $null = bcdedit /set '{fwbootmgr}' displayorder $newOrder
    Ok 'Boot order cleaned up.'
} else {
    Info 'Boot order unchanged (nothing to clean).'
}

$null = mountvol "$esp\" /D
Info ''
Info '=================== ROLLBACK DONE ==================='
if ($Full) {
    Info 'Everything removed. Boot is back to stock Windows only.'
} else {
    Info 'Direct entry removed. The shell-based unlock chain is still active:'
    Info 'the card will keep unlocking at boot via the UEFI Shell entry (slower).'
    Info 'To remove that too, run: Rollback-DirectBoot.bat -Full'
}

# Install-DirectBoot.ps1
# Installs the patched direct-boot unlock entry (NVPermissiveDirect.efi) plus the
# full fallback chain into the UEFI boot order:
#   [1] direct unlock (patched tool, no UEFI Shell needed - faster boot)
#   [2] shell unlock  (original tool via UEFI Shell - fallback if [1] fails)
#   [3] Windows Boot Manager
#   [4+] existing entries unchanged
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File Install-DirectBoot.ps1
#       final boot order (direct entry FIRST)
#   powershell -NoProfile -ExecutionPolicy Bypass -File Install-DirectBoot.ps1 -TestMode
#       adds direct entry at the END of the current boot order (select it manually
#       from the firmware boot menu once to verify before making it default)
#
# Safe to run repeatedly (idempotent). Never touches EFI\Boot\ or EFI\Microsoft\.
param([switch]$TestMode)
$ErrorActionPreference = 'Stop'
function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Info($msg) { Write-Host $msg }

$descDirect = 'NVPermissive Direct Boot'
$descShell  = 'NVPermissive 90HX Unlock'

# ---- 1. Administrator check ----
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$adm = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $adm.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'This script must run as Administrator (right-click install.bat, Run as administrator).'
}

# ---- 2. Verify tool files (SHA256) ----
$srcDir = $PSScriptRoot
$known = @{
    'startup.nsh'            = '08AA7D011B8EC0971294D234364AD969764F59B5F36D74061C1BA1B12772008D'
    'NVPermissiveEFI.efi'    = '1D076198F8D81A173514EA31785E81949E6ED44B3B810F25B8311557DC11F75B'
    'BOOTX64.EFI'            = 'DA5F4AA2008E6E26C3553B3DEE4CF835CEAC88820658693704CEA35F62733CE3'
    'NVPermissiveDirect.efi' = '93F29A5764B4A50AFB69B5DB7D1E574E7009554C48E6619BB83C5CA33191F59C'
}
foreach ($name in $known.Keys) {
    $p = Join-Path $srcDir $name
    if (-not (Test-Path $p)) { Fail "Missing file '$name' - keep all files in one folder." }
    $h = (Get-FileHash $p -Algorithm SHA256).Hash
    if ($h -ne $known[$name]) { Fail "Hash mismatch for '$name' - file corrupted or modified." }
}
Ok 'All 4 tool files verified (SHA256).'

# ---- 3. UEFI mode check ----
$cur = bcdedit /enum '{current}' | Out-String
if ($cur -notmatch 'winload\.efi') {
    Fail 'Not booted in UEFI mode (winload.efi not found). This tool requires UEFI boot.'
}
Ok 'UEFI boot mode detected.'

# ---- 4. Secure Boot check ----
try {
    if (Confirm-SecureBootUEFI) {
        Warn 'Secure Boot is ENABLED. The unlock tools are unsigned and will be refused at boot.'
        Warn 'Disable Secure Boot in firmware setup BEFORE rebooting.'
    }
} catch {
    Info 'Secure Boot status unknown. Make sure it is disabled before rebooting.'
}

# ---- 5. Mount the ESP ----
$esp = $null
foreach ($letter in 'S','T','U','V','W') {
    $drv = "$letter`:"
    if (Test-Path "$drv\") { continue }
    $null = mountvol $drv /S
    if (Test-Path "$drv\") { $esp = $drv; break }
}
if (-not $esp) { Fail 'Could not mount the EFI System Partition (ESP).' }
if (-not (Test-Path "$esp\EFI\Microsoft\Boot\bootmgfw.efi")) {
    $null = mountvol "$esp\" /D
    Fail 'ESP mounted but Windows boot files are missing. Unexpected partition layout - aborted, nothing was changed.'
}
Ok "ESP mounted at $esp"

# ---- 6. Copy tool files (never touches EFI\Boot\ or EFI\Microsoft\) ----
$null = New-Item -ItemType Directory -Force "$esp\EFI\NVPermissive"
Copy-Item (Join-Path $srcDir 'startup.nsh')            "$esp\startup.nsh" -Force
Copy-Item (Join-Path $srcDir 'startup.nsh')            "$esp\EFI\NVPermissive\startup.nsh" -Force
Copy-Item (Join-Path $srcDir 'NVPermissiveEFI.efi')    "$esp\NVPermissiveEFI.efi" -Force
Copy-Item (Join-Path $srcDir 'BOOTX64.EFI')            "$esp\EFI\NVPermissive\BOOTX64.EFI" -Force
Copy-Item (Join-Path $srcDir 'NVPermissiveDirect.efi') "$esp\EFI\NVPermissive\NVPermissiveDirect.efi" -Force
Ok 'Tool files copied to ESP.'

# ---- 7. Register / update firmware boot entries (idempotent) ----
function Find-Entry([string]$desc) {
    $curId = $null
    foreach ($ln in (bcdedit /enum firmware | Out-String -Stream)) {
        if ($ln -match '^\s*identifier\s+(\{[0-9a-fA-F-]+\})') { $curId = $Matches[1] }
        elseif ($ln -match ('description\s+' + [regex]::Escape($desc))) { return $curId }
    }
    return $null
}
function Create-Entry([string]$desc) {
    $out = bcdedit /copy '{bootmgr}' /d $desc | Out-String
    if ($out -match '\{[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}') { return $Matches[0] }
    Fail "bcdedit could not create the boot entry: $out"
}
$gDirect = Find-Entry $descDirect
if (-not $gDirect) {
    $gDirect = Create-Entry $descDirect
    Info "Created firmware boot entry: $gDirect"
} else {
    Info "Existing direct entry found, reusing: $gDirect"
}
$null = bcdedit /set $gDirect path '\EFI\NVPermissive\NVPermissiveDirect.efi'
Ok "Direct entry path set: \EFI\NVPermissive\NVPermissiveDirect.efi"

$gShell = Find-Entry $descShell
if (-not $gShell) {
    $gShell = Create-Entry $descShell
    Info "Created fallback shell entry: $gShell"
} else {
    Info "Existing shell entry found, reusing: $gShell"
}
$null = bcdedit /set $gShell path '\EFI\NVPermissive\BOOTX64.EFI'
Ok "Shell entry path set: \EFI\NVPermissive\BOOTX64.EFI"

# ---- 8. Boot order ----
# NOTE: displayorder in bcdedit output can span MULTIPLE lines, so parse the whole
# block between 'displayorder' and 'timeout' instead of a single line.
$fwTxt = bcdedit /enum '{fwbootmgr}' | Out-String
$orderStr = ''
if ($fwTxt -match '(?s)displayorder\s+(.*?)\s*\r?\n\s*timeout') { $orderStr = $Matches[1] }
elseif ($fwTxt -match '(?s)displayorder\s+(.*)$') { $orderStr = $Matches[1] }
$curOrder = @($orderStr -split '\s+' | Where-Object { $_ -match '^\{[0-9a-fA-F-]+\}$' })
if ($curOrder.Count -eq 0) { Fail 'Could not parse the firmware boot order. Aborted, nothing was changed.' }
if ($TestMode) {
    $newOrder = @($curOrder | Where-Object { $_ -ne $gDirect }) + @($gDirect)
    $null = bcdedit /set '{fwbootmgr}' displayorder $newOrder
    Ok 'TEST MODE: direct entry appended at END of boot order - NOT set as default yet.'
    Info 'Reboot and select "NVPermissive Direct Boot" from the firmware boot menu (F8/F11/F12) once to verify.'
} else {
    $rest = @($curOrder | Where-Object { $_ -ne $gDirect -and $_ -ne $gShell -and $_ -ne '{bootmgr}' })
    $newOrder = @($gDirect, $gShell, '{bootmgr}') + $rest
    $null = bcdedit /set '{fwbootmgr}' displayorder $newOrder
    Ok 'Boot order set: [1] direct unlock  [2] shell unlock fallback  [3] Windows Boot Manager  [4+] others'
}

# ---- 9. Verify ----
# NOTE: displayorder can span MULTIPLE lines - parse the whole block again.
$verify = bcdedit /enum '{fwbootmgr}' | Out-String
$verStr = ''
if ($verify -match '(?s)displayorder\s+(.*?)\s*\r?\n\s*timeout') { $verStr = $Matches[1] }
elseif ($verify -match '(?s)displayorder\s+(.*)$') { $verStr = $Matches[1] }
$verOrder = @($verStr -split '\s+' | Where-Object { $_ -match '^\{[0-9a-fA-F-]+\}$' })
Info ''
Info '--- current {fwbootmgr} displayorder ---'
foreach ($g in $verOrder) { Info ('  ' + $g) }
if ($TestMode) {
    if ($verOrder.Count -gt 0 -and $verOrder[-1] -eq $gDirect) {
        Ok 'Verified: direct entry is LAST in the boot order (test mode).'
    } else {
        Warn 'Could not verify the boot order; run "bcdedit /enum {fwbootmgr}" to check.'
    }
} else {
    if ($verOrder.Count -gt 0 -and $verOrder[0] -eq $gDirect) {
        Ok 'Verified: direct entry is FIRST in the boot order.'
    } else {
        Warn 'Could not verify the boot order; run "bcdedit /enum {fwbootmgr}" to check.'
    }
}

$null = mountvol "$esp\" /D
Info ''
Info '=================== DONE ==================='
if ($TestMode) {
    Info 'TEST MODE - direct entry NOT default yet. Next steps:'
    Info ' 1. Reboot and open the firmware boot menu (F8/F11/F12, key depends on board).'
    Info ' 2. Select "NVPermissive Direct Boot" once.'
    Info ' 3. Windows boots -> open GPU-Z -> confirm PCIe x16 2.0 link speed.'
    Info ' 4. If OK: run install.bat again WITHOUT -TestMode (or run Install-DirectBoot.ps1 directly) to make it default.'
} else {
    Info 'Next steps:'
    Info ' 1. Confirm Secure Boot is DISABLED in firmware setup.'
    Info ' 2. Reboot (no USB stick). The 90HX is unlocked automatically via the direct entry, then Windows boots.'
    Info ' 3. Keep the rescue USB: if boot ever fails, boot from the USB and run Rollback-DirectBoot.bat.'
}
Info ''
Info 'Rollback (run as Administrator):'
Info '  Rollback-DirectBoot.bat  - removes the direct entry only (keeps shell fallback chain)'
Info '  Rollback-DirectBoot.bat -Full  - removes EVERYTHING this package installed'
Info ''

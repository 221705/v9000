# Install-Compat.ps1
# Compatibility one-click install: repoint the standard Windows Boot Manager entry
# {bootmgr} to NVPermissiveCompat.efi. This works on EVERY board, including boards
# that HIDE custom firmware boot entries (the reason plain installs fail).
#
# NVPermissiveCompat.efi = NVPermissiveDirect.efi (2-byte default-mode patch)
#                          + 2-byte chainload patch: the tool now chains Windows
#                          itself whenever AT LEAST ONE Windows boot partition is
#                          found (original refused unless EXACTLY one existed,
#                          which broke dual-ESP / dual-boot / install-USB setups).
#
# A backup entry (copy of {bootmgr}, path untouched) is placed 2nd in the boot
# order, so ANY failure of the tool falls through to plain Windows automatically
# (per UEFI spec, the firmware tries the next entry whenever an entry returns
# non-EFI_SUCCESS - verified by reverse engineering).
#
# Boot chain after install:
#   [1] {bootmgr} -> NVPermissiveCompat.efi  (unlock, then chains Windows itself)
#   [2] Windows Boot Manager (Backup) -> bootmgfw.efi  (plain Windows, no unlock)
#   [3+] existing generic entries (Hard Drive etc.),
#        all NVPermissive custom entries REMOVED (fixes duplicated unlocks)
#
# Operation order is risk-ascending: snapshot -> backup entry -> cleanup -> boot
# order -> ONLY THEN repoint {bootmgr}. Safe to run repeatedly (idempotent).
# Never touches EFI\Boot\ or EFI\Microsoft\ (only the {bootmgr} path string in BCD
# and tool files under EFI\NVPermissive\).
param()
$ErrorActionPreference = 'Stop'
function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Info($msg) { Write-Host $msg }

$toolFile  = 'NVPermissiveCompat.efi'
$toolHash  = '42F8AB966A43C8E4060AA9406F40D0FC9B48C8AE00920B2CF3B5C22CC76B0267'
$winPath   = '\EFI\Microsoft\Boot\bootmgfw.efi'
$toolPath  = '\EFI\NVPermissive\NVPermissiveCompat.efi'
$backupDesc = 'Windows Boot Manager (Backup)'
$stateFile = Join-Path $PSScriptRoot 'compat-state.txt'
$snapDir   = Join-Path $PSScriptRoot 'snapshots'

# ---- Locale-proof bcdedit field keywords ----
# bcdedit prints field names in the PROCESS UI language: a batch double-clicked
# on zh-CN Windows runs in a Chinese console where 'identifier' becomes its
# localized form (0x6807 0x8BC6 0x7B26; section headers change too, but
# path/description/displayorder stay English). Match both languages so the
# script works identically from either console. Built from char codes to keep
# this file pure ASCII (PS 5.1 reads .ps1 as ANSI, raw Chinese text could garble).
$kwId   = '(?:identifier|' + (-join [char[]](0x6807,0x8BC6,0x7B26)) + ')'  # identifier | localized form
$kwDesc = '(?:description|' + (-join [char[]](0x63CF,0x8FF0)) + ')'       # description | localized form
$kwPath = '(?:path|'     + (-join [char[]](0x8DEF,0x5F84)) + ')'          # path | localized form

# ---- 1. Administrator check ----
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$adm = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $adm.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'This script must run as Administrator (right-click Install-Compat.bat, Run as administrator).'
}

# ---- 2. Verify tool file (SHA256) ----
$srcTool = Join-Path $PSScriptRoot $toolFile
if (-not (Test-Path $srcTool)) { Fail "Missing '$toolFile' - keep it next to this script." }
$h = (Get-FileHash $srcTool -Algorithm SHA256).Hash
if ($h -ne $toolHash) { Fail "Hash mismatch for '$toolFile' - file corrupted or modified." }
Ok 'Tool file verified (SHA256).'

# ---- 3. UEFI mode check ----
$cur = bcdedit /enum '{current}' | Out-String
if ($cur -notmatch 'winload\.efi') {
    Fail 'Not booted in UEFI mode (winload.efi not found). This tool requires UEFI boot.'
}
Ok 'UEFI boot mode detected.'

# ---- 4. Secure Boot check ----
try {
    if (Confirm-SecureBootUEFI) {
        Warn 'Secure Boot is ENABLED. The unlock tool is unsigned and will be refused at boot.'
        Warn 'Disable Secure Boot in firmware setup BEFORE rebooting.'
    }
} catch {
    Info 'Secure Boot status unknown. Make sure it is disabled before rebooting.'
}

# ---- 5. Mount the ESP (or reuse an already-mounted one) ----
$esp = $null
foreach ($letter in 'S','T','U','V','W') {
    $drv = "$letter`:"
    if (Test-Path "$drv\EFI\Microsoft\Boot\bootmgfw.efi") { $esp = $drv; break }
    if (Test-Path "$drv\") { continue }
    $null = mountvol $drv /S
    if (Test-Path "$drv\EFI\Microsoft\Boot\bootmgfw.efi") { $esp = $drv; break }
}
if (-not $esp) { Fail 'Could not mount the EFI System Partition (ESP).' }
if (-not (Test-Path "$esp\EFI\Microsoft\Boot\bootmgfw.efi")) {
    $null = mountvol "$esp\" /D
    Fail 'ESP mounted but Windows boot files are missing. Unexpected partition layout - aborted, nothing was changed.'
}
Ok "ESP mounted at $esp"

# ---- 6. Copy tool file (never touches EFI\Boot\ or EFI\Microsoft\) ----
$null = New-Item -ItemType Directory -Force "$esp\EFI\NVPermissive"
Copy-Item $srcTool "$esp\EFI\NVPermissive\$toolFile" -Force
$espHash = (Get-FileHash "$esp\EFI\NVPermissive\$toolFile" -Algorithm SHA256).Hash
if ($espHash -ne $toolHash) { Fail 'Copied tool file hash mismatch on ESP - aborted, nothing else was changed.' }
Ok 'Tool file installed on ESP.'

# ---- 7. Snapshot current firmware state ----
$null = New-Item -ItemType Directory -Force $snapDir
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
$snapFile = Join-Path $snapDir "firmware-$ts.txt"
bcdedit /enum firmware /v | Out-File $snapFile -Encoding ascii
bcdedit /enum '{fwbootmgr}' | Out-File (Join-Path $snapDir "fwbootmgr-$ts.txt") -Encoding ascii
Ok "Snapshot saved: $snapFile"

# ---- 8. Locate {bootmgr} and read current path ----
function Find-Entry([string]$desc) {
    $curId = $null
    foreach ($ln in (bcdedit /enum firmware | Out-String -Stream)) {
        if ($ln -match ('^\s*' + $kwId + '\s+(\{[0-9a-fA-F-]+\})')) { $curId = $Matches[1] }
        elseif ($ln -match ($kwDesc + '\s+' + [regex]::Escape($desc))) { return $curId }
    }
    return $null
}
# Read the {bootmgr} entry directly (the alias works on every locale) and parse
# only its path line - no section tracking, immune to keyword localization.
$oldPath = $null
foreach ($ln in (bcdedit /enum '{bootmgr}' | Out-String -Stream)) {
    if ($ln -match ('^\s*' + $kwPath + '\s+(\S+)')) { $oldPath = $Matches[1]; break }
}
if (-not $oldPath) { Fail 'Could not read the current {bootmgr} path. Aborted - {bootmgr} and boot order were NOT changed.' }
Info "Current {bootmgr} path: $oldPath"

# ---- 9. Ensure backup entry exists (BEFORE touching {bootmgr}) ----
$gBackup = Find-Entry $backupDesc
if (-not $gBackup) {
    $out = bcdedit /copy '{bootmgr}' /d $backupDesc | Out-String
    if ($out -match '\{[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\}') { $gBackup = $Matches[0] }
    else { Fail "Could not create backup entry: $out" }
    Info "Created backup entry: $gBackup"
} else {
    Info "Backup entry already exists, reusing: $gBackup"
}
$null = bcdedit /set $gBackup path $winPath
# verify backup entry path
$bkPath = $null; $inBk = $false
foreach ($ln in (bcdedit /enum firmware | Out-String -Stream)) {
    if ($ln -match ('^\s*' + $kwId + '\s+(\{[0-9a-fA-F-]+\})')) { $inBk = ($Matches[1] -eq $gBackup) }
    elseif ($inBk -and $ln -match ('^\s*' + $kwPath + '\s+(\S+)')) { $bkPath = $Matches[1]; break }
}
if ($bkPath -ne $winPath) { Fail "Backup entry path is '$bkPath' (expected '$winPath'). Aborted, {bootmgr} NOT touched." }
Ok "Backup entry verified: $gBackup -> $winPath"

# ---- 10. Remove ALL NVPermissive custom entries (fixes duplicated unlocks) ----
$nvEntries = @()
$curId = $null
foreach ($ln in (bcdedit /enum firmware | Out-String -Stream)) {
    if ($ln -match ('^\s*' + $kwId + '\s+(\{[0-9a-fA-F-]+\})')) { $curId = $Matches[1] }
    elseif ($ln -match ('^\s*' + $kwDesc + '\s+(.*)$')) {
        if ($Matches[1] -match 'NVPermissive') { $nvEntries += $curId }
    }
}
if ($nvEntries.Count -gt 0) {
    Info ('Removing ' + $nvEntries.Count + ' NVPermissive custom entry(s):')
    foreach ($g in $nvEntries) {
        Info ('  delete ' + $g)
        $null = bcdedit /delete "$g" /f
    }
    Ok 'NVPermissive custom entries removed.'
} else {
    Ok 'No NVPermissive custom entries to remove.'
}

# ---- 11. Rebuild boot order: {bootmgr} first, backup second, others unchanged ----
$fwTxt = bcdedit /enum '{fwbootmgr}' | Out-String
$orderStr = ''
if ($fwTxt -match '(?s)displayorder\s+(.*?)\s*\r?\n\s*timeout') { $orderStr = $Matches[1] }
elseif ($fwTxt -match '(?s)displayorder\s+(.*)$') { $orderStr = $Matches[1] }
$curOrder = @($orderStr -split '\s+' | Where-Object { $_ -match '^\{[^}]+\}$' })
if ($curOrder.Count -eq 0) { Fail 'Could not parse the firmware boot order. Aborted (no {bootmgr} change).' }
$nvSet = @{}; foreach ($g in $nvEntries) { $nvSet[$g] = $true }
$rest = @($curOrder | Where-Object { $_ -ne '{bootmgr}' -and $_ -ne $gBackup -and -not $nvSet.ContainsKey($_) })
$newOrder = @('{bootmgr}', $gBackup) + $rest
$null = bcdedit /set '{fwbootmgr}' displayorder $newOrder
Ok 'Boot order set: [1] {bootmgr}->tool  [2] backup Windows  [3+] others (no duplicates)'

# ---- 12. THE HIJACK: repoint {bootmgr} path to the tool (last step) ----
if ($oldPath -eq $toolPath) {
    Info '{bootmgr} already points to the tool (idempotent).'
} else {
    $null = bcdedit /set '{bootmgr}' path $toolPath
    Ok "{bootmgr} path repointed: $oldPath -> $toolPath"
}

# ---- 13. Verify ----
$vPath = $null
foreach ($ln in (bcdedit /enum '{bootmgr}' | Out-String -Stream)) {
    if ($ln -match ('^\s*' + $kwPath + '\s+(\S+)')) { $vPath = $Matches[1]; break }
}
if ($vPath -ne $toolPath) { Fail "VERIFY FAILED: {bootmgr} path is '$vPath'. Run Rollback-Compat.bat to restore, then report this." }

$fwTxt2 = bcdedit /enum '{fwbootmgr}' | Out-String
$orderStr2 = ''
if ($fwTxt2 -match '(?s)displayorder\s+(.*?)\s*\r?\n\s*timeout') { $orderStr2 = $Matches[1] }
elseif ($fwTxt2 -match '(?s)displayorder\s+(.*)$') { $orderStr2 = $Matches[1] }
$verOrder = @($orderStr2 -split '\s+' | Where-Object { $_ -match '^\{[^}]+\}$' })
$leftover = @($verOrder | Where-Object { $nvSet.ContainsKey($_) })
if ($leftover.Count -gt 0) { Warn ('Deleted entries still in displayorder: ' + ($leftover -join ' ')) }
if ($verOrder.Count -gt 0 -and $verOrder[0] -eq '{bootmgr}' -and $verOrder[1] -eq $gBackup) {
    Ok 'Verified: boot order is [{bootmgr}, backup, ...]'
} else {
    Warn 'Could not fully verify boot order; run "bcdedit /enum {fwbootmgr}" to check.'
}

# ---- 14. Neutralize legacy shell scripts (rename, physically reversible) ----
foreach ($p in @("$esp\startup.nsh", "$esp\EFI\NVPermissive\startup.nsh")) {
    if (Test-Path $p) {
        Move-Item $p "$p.bak" -Force
        Info "Renamed $p -> $p.bak (no entry boots it anymore)"
    }
}

# ---- 15. Write state file for Rollback-Compat ----
# If this run found {bootmgr} ALREADY hijacked (idempotent re-run), do NOT
# overwrite the real original path with the tool path - keep the previous
# OLD_PATH from the existing state file, else fall back to the standard path.
$stateOld = $oldPath
if ($oldPath -eq $toolPath) {
    $stateOld = $winPath
    if (Test-Path $stateFile) {
        Get-Content $stateFile | ForEach-Object {
            if ($_ -match '^OLD_PATH=(.+)$') {
                # save $Matches first: a nested -match overwrites the $Matches automatic variable
                $cand = $Matches[1]
                if ($cand -match '^\\' -and $cand -ne $toolPath) { $stateOld = $cand }
            }
        }
    }
}
@(
    "OLD_PATH=$stateOld"
    "BACKUP_GUID=$gBackup"
    "TIMESTAMP=$ts"
) | Out-File $stateFile -Encoding ascii
Ok "State file written: $stateFile"

$null = mountvol "$esp\" /D
Info ''
Info '=================== DONE ==================='
Info 'Boot chain now:'
Info '  [1] {bootmgr} -> NVPermissiveCompat.efi (unlocks, then chains Windows automatically)'
Info '  [2] Windows Boot Manager (Backup) -> plain Windows (auto fallback if the tool fails)'
Info '  [3+] other entries (Hard Drive etc.)'
Info ''
Info 'Next steps:'
Info ' 1. Reboot. The tool output should appear exactly ONCE, then Windows boots.'
Info ' 2. Open GPU-Z -> confirm PCIe x16 2.0 link speed.'
Info ' 3. If the unlock fails, see the failure table in README.txt.'
Info '    Failure drill (optional but recommended): rename'
Info '    \EFI\NVPermissive\NVPermissiveCompat.efi on the ESP to .off, reboot ->'
Info '    the machine must boot Windows anyway (no unlock, PCIe 1.1) via the'
Info '    backup entry. Then rename it back.'
Info ''
Info 'Rollback (run as Administrator):'
Info '  Rollback-Compat.bat       - restore {bootmgr} path, remove backup entry'
Info '  Rollback-Compat.bat -Full - also remove all tool files from the ESP'

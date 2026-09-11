# Rollback-Compat.ps1
# Restores the {bootmgr} path to plain Windows and removes the backup entry.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File Rollback-Compat.ps1
#       restore {bootmgr} path + remove backup entry (tool files stay on ESP)
#   powershell -NoProfile -ExecutionPolicy Bypass -File Rollback-Compat.ps1 -Full
#       additionally remove ALL tool files from the ESP
#
# After rollback the machine boots plain Windows (PCIe 1.1, no unlock) via the
# standard {bootmgr} entry - the exact pre-install state.
param([switch]$Full)
$ErrorActionPreference = 'Stop'
function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Info($msg) { Write-Host $msg }

$winPath   = '\EFI\Microsoft\Boot\bootmgfw.efi'
$toolPath  = '\EFI\NVPermissive\NVPermissiveCompat.efi'
$backupDesc = 'Windows Boot Manager (Backup)'
$stateFile = Join-Path $PSScriptRoot 'compat-state.txt'

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
    Fail 'This script must run as Administrator (right-click Rollback-Compat.bat, Run as administrator).'
}

# ---- 2. Read state file (fallback to defaults if missing) ----
$oldPath = $winPath
$gBackup = $null
if (Test-Path $stateFile) {
    $st = @{}
    Get-Content $stateFile | ForEach-Object {
        if ($_ -match '^([A-Z_]+)=(.*)$') { $st[$Matches[1]] = $Matches[2] }
    }
    if ($st.ContainsKey('OLD_PATH') -and $st['OLD_PATH'] -match '^\\' -and $st['OLD_PATH'] -ne $toolPath) {
        $oldPath = $st['OLD_PATH']
    } else {
        Warn 'State file OLD_PATH invalid or missing - using standard Windows path instead.'
    }
    if ($st.ContainsKey('BACKUP_GUID') -and $st['BACKUP_GUID'] -match '^\{[0-9a-fA-F-]+\}$') { $gBackup = $st['BACKUP_GUID'] }
    Info "State file loaded. Original {bootmgr} path was: $oldPath"
} else {
    Warn 'State file not found - using standard Windows path as restore target.'
}

# ---- 3. Find backup entry by description if GUID unknown ----
function Find-Entry([string]$desc) {
    $curId = $null
    foreach ($ln in (bcdedit /enum firmware | Out-String -Stream)) {
        if ($ln -match ('^\s*' + $kwId + '\s+(\{[0-9a-fA-F-]+\})')) { $curId = $Matches[1] }
        elseif ($ln -match ($kwDesc + '\s+' + [regex]::Escape($desc))) { return $curId }
    }
    return $null
}
if (-not $gBackup) { $gBackup = Find-Entry $backupDesc }

# ---- 4. Restore {bootmgr} path ----
$null = bcdedit /set '{bootmgr}' path $oldPath
Ok "{bootmgr} path restored to: $oldPath"

# ---- 5. Remove backup entry ----
if ($gBackup) {
    $null = bcdedit /delete "$gBackup" /f
    Ok "Backup entry removed: $gBackup"
} else {
    Info 'No backup entry found - nothing to remove.'
}

# ---- 6. Verify ----
# Read the {bootmgr} entry directly (the alias works on every locale) and parse
# only its path line - immune to keyword localization.
$vPath = $null
foreach ($ln in (bcdedit /enum '{bootmgr}' | Out-String -Stream)) {
    if ($ln -match ('^\s*' + $kwPath + '\s+(\S+)')) { $vPath = $Matches[1]; break }
}
if ($vPath -eq $oldPath) {
    Ok 'Verified: {bootmgr} points to plain Windows again.'
} else {
    Fail "VERIFY FAILED: {bootmgr} path is '$vPath' (expected '$oldPath'). Do NOT reboot - run this script again."
}

# ---- 7. Full cleanup of tool files (only with -Full) ----
if ($Full) {
    $esp = $null
    foreach ($letter in 'S','T','U','V','W') {
        $drv = "$letter`:"
        if (Test-Path "$drv\EFI\Microsoft\Boot\bootmgfw.efi") { $esp = $drv; break }
        if (Test-Path "$drv\") { continue }
        $null = mountvol $drv /S
        if (Test-Path "$drv\EFI\Microsoft\Boot\bootmgfw.efi") { $esp = $drv; break }
    }
    if ($esp) {
        Remove-Item "$esp\EFI\NVPermissive" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$esp\startup.nsh" -Force -ErrorAction SilentlyContinue
        Remove-Item "$esp\startup.nsh.bak" -Force -ErrorAction SilentlyContinue
        Remove-Item "$esp\NVPermissiveEFI.efi" -Force -ErrorAction SilentlyContinue
        $null = mountvol "$esp\" /D
        Ok "Tool files removed from ESP ($esp)."
    } else {
        Warn 'Could not mount ESP - tool files were not removed (re-run with -Full later).'
    }
    Info 'Note: NVPermissive custom firmware entries (if any) were NOT removed by this script.'
    Info 'Run "bcdedit /enum firmware" and delete them manually if desired.'
} else {
    Info 'Tool files kept on ESP (run with -Full to remove them too).'
}

Info ''
Info '=================== ROLLBACK DONE ==================='
Info 'The machine now boots plain Windows exactly as before the hijack install.'

# Bcd.Common.ps1
# Shared constants, helpers and BCD parsing for Install-DirectBoot.ps1 and
# Rollback-DirectBoot.ps1. Both scripts dot-source this file - do NOT duplicate
# any regex or bcdedit text parsing in the individual scripts.
#
# LOCALIZATION NOTE (the bug this fixes): on zh-CN Windows, bcdedit localizes
# the label "identifier" (e.g. to the localized word) while element names such
# as path/description/displayorder usually stay English (matched bilingually
# anyway). Label-based regexes therefore never match -> "Could not read ..."
# or, worse, Find-Entry returns null and entries get DUPLICATED on every run.
# Parsing here is STRUCTURAL, not label-based:
#   every `bcdedit /enum ...` entry block looks like
#       <title line>
#       --------------------
#       <identifier line>   {guid}        <- first line after the dashes
#       path                \EFI\...
#       description         ...
# We locate entries via the dashed separator + first {...} token after it,
# which works regardless of the OS display language.

$descDirect = 'NVPermissive Direct Boot'
$descShell  = 'NVPermissive 90HX Unlock'

# A full GUID in braces, e.g. the response of `bcdedit /copy ...`
$GuidPattern = '\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}'

# Tool files that must ship and be hash-verified. Single source of truth for
# Install-DirectBoot.ps1 AND Package-DirectBoot.ps1 - never duplicate these.
# NOTE: startup.nsh is the customized version (windows arg + chained Windows
# Boot Manager); hash re-pinned 2026-09-10.
$ToolHashes = @{
    'startup.nsh'            = '77478AB16F4B16B424A0AB06B4930129D09E4564159E37F68F1CFE44B177C798'
    'NVPermissiveEFI.efi'    = '1D076198F8D81A173514EA31785E81949E6ED44B3B810F25B8311557DC11F75B'
    'BOOTX64.EFI'            = 'DA5F4AA2008E6E26C3553B3DEE4CF835CEAC88820658693704CEA35F62733CE3'
    'NVPermissiveDirect.efi' = '93F29A5764B4A50AFB69B5DB7D1E574E7009554C48E6619BB83C5CA33191F59C'
}

function Fail($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Ok($msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Info($msg) { Write-Host $msg }

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Parse `bcdedit /enum firmware` into objects { Id, Description, Path }.
# Language-independent: entry start = first {...} token after a dashed line.
function Get-BcdFirmwareEntries {
    $entries   = @()
    $cur       = $null
    $identNext = $false
    foreach ($ln in (bcdedit /enum firmware)) {
        if ($ln -match '^\s*[-=]{4,}\s*$') { $identNext = $true; continue }
        if ([string]::IsNullOrWhiteSpace($ln)) { continue }
        if ($identNext) {
            if ($cur) { $entries += $cur }
            $id = $null
            if ($ln -match '\{[0-9a-zA-Z-]+\}') { $id = $Matches[0] }
            $cur = [pscustomobject]@{ Id = $id; Description = $null; Path = $null }
            $identNext = $false
            continue
        }
        if ($null -eq $cur) { continue }
        if     ($ln -match '^\s*(?:path|路径|路徑)\s+(\S+)')              { $cur.Path = $Matches[1] }
        elseif ($ln -match '^\s*(?:description|说明|描述|說明)\s+(.*)$')  { $cur.Description = $Matches[1].Trim() }
    }
    if ($cur) { $entries += $cur }
    return @($entries | Where-Object { $_.Id })
}

# Find one firmware entry by its exact description text. Returns the id or $null.
function Get-BcdEntryByDescription([string]$desc) {
    Get-BcdFirmwareEntries | Where-Object { $_.Description -eq $desc } | Select-Object -First 1
}

# Create a new firmware app entry by copying {bootmgr}; returns the new GUID.
function New-BcdFirmwareEntry([string]$desc) {
    $out = bcdedit /copy '{bootmgr}' /d $desc | Out-String
    $g = ConvertTo-BcdGuid $out
    if (-not $g) { Fail "bcdedit could not create the boot entry: $out" }
    return $g
}

# Parse the firmware boot manager displayorder into an array of entry ids.
# displayorder can span MULTIPLE lines, so parse the block up to 'timeout'.
function Get-BcdFwbootmgrDisplayOrder {
    $txt = bcdedit /enum '{fwbootmgr}' | Out-String
    $orderStr = ''
    if     ($txt -match '(?s)(?:displayorder|显示顺序|顯示順序)\s+(.*?)\s*\r?\n\s*timeout') { $orderStr = $Matches[1] }
    elseif ($txt -match '(?s)(?:displayorder|显示顺序|顯示順序)\s+(.*)$')                   { $orderStr = $Matches[1] }
    # accept ANY {...} token - '{bootmgr}' is not a GUID shape ([a-f] only)
    # and dropping it would silently remove Windows from the boot order.
    return @($orderStr -split '\s+' | Where-Object { $_ -match '^\{[^}]+\}$' })
}

# Extract the first GUID in braces from free text (e.g. bcdedit /copy output).
function ConvertTo-BcdGuid([string]$text) {
    if ($text -match $GuidPattern) { return $Matches[0] }
    return $null
}

# Find or mount the ESP (identified by Windows bootmgfw.efi on it);
# returns a drive letter like "S:" or $null. Never unmounts.
function Get-EspMount {
    foreach ($letter in 'S','T','U','V','W') {
        $drv = "$letter`:"
        if (Test-Path "$drv\EFI\Microsoft\Boot\bootmgfw.efi") { return $drv }
        if (Test-Path "$drv\") { continue }
        $null = mountvol $drv /S
        if (Test-Path "$drv\EFI\Microsoft\Boot\bootmgfw.efi") { return $drv }
    }
    return $null
}

function Remove-EspMount($esp) { $null = mountvol "$esp\" /D }

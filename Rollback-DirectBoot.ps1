# Rollback-DirectBoot.ps1
# Default : removes the direct-boot entry + patched file only (shell fallback chain stays).
# -Full   : also removes the shell unlock entry and all tool files (full uninstall).
#
# All bcdedit text parsing lives in Bcd.Common.ps1 (language-independent) -
# keep that file next to this script.
param([switch]$Full)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Bcd.Common.ps1')

if (-not (Test-IsAdministrator)) {
    Fail 'This script must run as Administrator.'
}

$esp = Get-EspMount
if (-not $esp) { Fail 'Could not mount the EFI System Partition (ESP). Nothing was changed.' }
if (-not (Test-Path "$esp\EFI\Microsoft\Boot\bootmgfw.efi")) {
    Remove-EspMount $esp
    Fail 'ESP mounted but Windows boot files are missing. Unexpected partition layout - aborted, nothing was changed.'
}
Info "ESP mounted at $esp"

$removed = @()

# ---- direct entry + patched file ----
$gDirect = (Get-BcdEntryByDescription $descDirect).Id
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
    $gShell = (Get-BcdEntryByDescription $descShell).Id
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
$curOrder = Get-BcdFwbootmgrDisplayOrder
$newOrder = @($curOrder | Where-Object { $removed -notcontains $_ })
if ($newOrder.Count -ne $curOrder.Count) {
    $null = bcdedit /set '{fwbootmgr}' displayorder $newOrder
    Ok 'Boot order cleaned up.'
} else {
    Info 'Boot order unchanged (nothing to clean).'
}

Remove-EspMount $esp
Info ''
Info '=================== ROLLBACK DONE ==================='
if ($Full) {
    Info 'Everything removed. Boot is back to stock Windows only.'
} else {
    Info 'Direct entry removed. The shell-based unlock chain is still active:'
    Info 'the card will keep unlocking at boot via the UEFI Shell entry (slower).'
    Info 'To remove that too, run: Rollback-DirectBoot.bat -Full'
}

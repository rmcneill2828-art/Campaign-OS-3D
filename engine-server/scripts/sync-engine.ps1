# Re-pulls a fresh copy of the DOM-free rules engine (engine/*.js) from the 2D
# Campaign-OS checkout this project was forked alongside. There is exactly ONE
# real source of truth for 5e rules logic -- the 2D repo's engine/ folder -- and
# this 3D project never edits its own copy in place; it only ever overwrites it
# wholesale from there, the same "manual sync, audited by hand" convention
# Campaign-OS's own CLAUDE.md already documents for its duplicated lookup lists
# (MONSTER_LIST/CONDITION_LIST/etc. between the browser engine and dm-bridge/watch.js).
#
# PowerShell counterpart to sync-engine.sh -- same behavior, for a machine without
# Git Bash. Keep the two in sync if this logic ever changes.
#
# Usage: pwsh scripts/sync-engine.ps1 [-Source <path-to-Campaign-OS-checkout>]
# Defaults to ../../Campaign-OS (i.e. a sibling checkout next to this project).

param(
    [string]$Source = "../../Campaign-OS"
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$Dest = "engine"
$SourceEngine = Join-Path $Source "engine"

if (-not (Test-Path $SourceEngine)) {
    Write-Error "Could not find $SourceEngine -- pass the Campaign-OS checkout path explicitly."
    exit 1
}

foreach ($f in "encounter.js", "dmBridge.js", "campaign.js", "characterCreator.js") {
    $srcFile = Join-Path $SourceEngine $f
    $destFile = Join-Path $Dest $f
    if ((Test-Path $destFile) -and (Get-FileHash $srcFile).Hash -ne (Get-FileHash $destFile).Hash) {
        Write-Host "CHANGED: $f (review before committing -- the 3D client may rely on behavior that just shifted)"
    }
    Copy-Item $srcFile $destFile -Force
}

Write-Host "Synced engine/*.js from $SourceEngine."

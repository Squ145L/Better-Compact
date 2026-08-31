[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$WorkspaceRoot,
    [ValidateSet('Prompt', 'Merge', 'Cancel')]
    [string]$ExistingHooksAction = 'Prompt'
)

$ErrorActionPreference = 'Stop'
$SourceRoot = Split-Path -Parent $PSScriptRoot
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd([char]92)
if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) { throw "WorkspaceRoot does not exist or is not a directory: $WorkspaceRoot" }
if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'Windows PowerShell 5.1 or newer is required.' }

$ToolRoot = Join-Path $WorkspaceRoot '.agents\skills\better-compact'
$RuntimeRoot = Join-Path $ToolRoot 'runtime'
$InstallRoot = Join-Path $ToolRoot 'install'
$ConfigPath = Join-Path $ToolRoot 'config\workspace.json'
$MetadataPath = Join-Path $InstallRoot 'install.json'
$CodexHome = Join-Path $env:USERPROFILE '.codex'
$HooksPath = Join-Path $CodexHome 'hooks.json'
$HookScriptPath = Join-Path $RuntimeRoot 'continuity.ps1'

function Get-Value($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}
function Assert-ExistingToolIsBetterCompact {
    if (-not (Test-Path -LiteralPath $ToolRoot -PathType Container)) { return $false }
    if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) { throw "Refusing to overwrite unknown directory: $ToolRoot" }
    try { $metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json } catch { throw "Refusing to overwrite directory with invalid Better Compact metadata: $ToolRoot" }
    if (([string](Get-Value $metadata 'product')) -ne 'better-compact' -or ([string](Get-Value $metadata 'workspaceRoot')).TrimEnd([char]92) -ne $WorkspaceRoot) {
        throw "Refusing to overwrite directory not identified as this workspace's Better Compact installation: $ToolRoot"
    }
    return $true
}
function Read-HookConfig {
    if (-not (Test-Path -LiteralPath $HooksPath -PathType Leaf)) { return [pscustomobject]@{ hooks = [pscustomobject]@{} } }
    try { return Get-Content -LiteralPath $HooksPath -Raw | ConvertFrom-Json } catch { throw "Existing hooks.json is not valid JSON: $HooksPath" }
}
function Ensure-HookEvent($Config, [string]$EventName) {
    if ($null -eq $Config.hooks) { $Config | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force }
    if ($null -eq $Config.hooks.PSObject.Properties[$EventName]) { $Config.hooks | Add-Member -NotePropertyName $EventName -NotePropertyValue @() }
}
function Remove-ToolHandlers($Config, [string[]]$EventNames) {
    $changed = $false
    foreach ($eventName in $EventNames) {
        $property = $Config.hooks.PSObject.Properties[$eventName]
        if ($null -eq $property) { continue }
        $groups = @($property.Value); $remainingGroups = New-Object System.Collections.Generic.List[object]
        foreach ($group in $groups) {
            $handlers = @($group.hooks)
            $remainingHandlers = @($handlers | Where-Object { [string]$_.command -notmatch [regex]::Escape($HookScriptPath) })
            if ($remainingHandlers.Count -ne $handlers.Count) { $changed = $true }
            if ($remainingHandlers.Count -gt 0) { $group.hooks = $remainingHandlers; [void]$remainingGroups.Add($group) }
        }
        if ($remainingGroups.Count -ne $groups.Count) { $changed = $true }
        $Config.hooks.$eventName = $remainingGroups.ToArray()
    }
    return $changed
}
function Add-ToolHandler($Config, $Definition) {
    Ensure-HookEvent $Config $Definition.event
    $quotedScript = '"' + $HookScriptPath + '"'; $quotedWorkspace = '"' + $WorkspaceRoot + '"'; $quotedToolRoot = '"' + $ToolRoot + '"'
    $command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $quotedScript -WorkspaceRoot $quotedWorkspace -ToolRoot $quotedToolRoot"
    $handler = [ordered]@{ type = 'command'; command = $command; commandWindows = $command; timeout = 10; statusMessage = $Definition.status }
    if ($null -ne $Definition.contextLimit) { $handler.additionalContextLimit = $Definition.contextLimit }
    $Config.hooks.($Definition.event) = @($Config.hooks.($Definition.event) + [pscustomobject]@{ matcher = $Definition.matcher; hooks = @([pscustomobject]$handler) })
}

$isUpgrade = Assert-ExistingToolIsBetterCompact
$hooksExist = Test-Path -LiteralPath $HooksPath -PathType Leaf
if ($hooksExist -and $ExistingHooksAction -eq 'Prompt') { $ExistingHooksAction = if ((Read-Host "Existing $HooksPath detected. Enter M to safely merge, or C to cancel") -match '^[Mm]$') { 'Merge' } else { 'Cancel' } }
if ($hooksExist -and $ExistingHooksAction -eq 'Cancel') { Write-Host 'Installation cancelled. Existing hooks.json was not changed.' -ForegroundColor Yellow; exit 0 }
$hookConfig = Read-HookConfig

foreach ($sourceFile in @('continuity.ps1', 'Control.ps1', 'Watch-ContinuityDiagnostics.ps1', 'Uninstall.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $sourceFile) -PathType Leaf)) { throw "Distribution file is missing: $sourceFile" }
}
foreach ($sourceFile in @('skill\SKILL.md', 'prompts\task-state.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceRoot $sourceFile) -PathType Leaf)) { throw "Distribution file is missing: $sourceFile" }
}

New-Item -ItemType Directory -Force -Path $RuntimeRoot, (Join-Path $ToolRoot 'config'), (Join-Path $ToolRoot 'prompts'), (Join-Path $ToolRoot 'recovery'), (Join-Path $ToolRoot 'logs'), $InstallRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $SourceRoot 'skill\SKILL.md') -Destination (Join-Path $ToolRoot 'SKILL.md') -Force
Copy-Item -LiteralPath (Join-Path $SourceRoot 'prompts\task-state.md') -Destination (Join-Path $ToolRoot 'prompts\task-state.md') -Force
foreach ($sourceFile in @('continuity.ps1', 'Control.ps1', 'Watch-ContinuityDiagnostics.ps1', 'Uninstall.ps1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $sourceFile) -Destination (Join-Path $RuntimeRoot $sourceFile) -Force }
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { [ordered]@{ schemaVersion = 1; coreEnabled = $true; taskStateEnabled = $true } | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding utf8 }

$previousMetadata = if ($isUpgrade) { Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json } else { $null }
[ordered]@{
    schemaVersion = 1; product = 'better-compact'; workspaceRoot = $WorkspaceRoot
    installedAtUtc = if ($previousMetadata) { [string](Get-Value $previousMetadata 'installedAtUtc') } else { [DateTime]::UtcNow.ToString('o') }
    updatedAtUtc = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json | Set-Content -LiteralPath $MetadataPath -Encoding utf8

$changed = Remove-ToolHandlers $hookConfig @('SessionStart', 'PreToolUse', 'PostToolUse', 'PreCompact')
$definitions = @(
    @{ event = 'SessionStart'; matcher = '^(compact|resume)$'; contextLimit = 18000; status = 'Restoring Better Compact context' },
    @{ event = 'PostToolUse'; matcher = '^apply_patch$'; contextLimit = $null; status = 'Recording successful Better Compact edits' },
    @{ event = 'PreCompact'; matcher = '^(manual|auto)$'; contextLimit = $null; status = 'Marking Better Compact recovery card' }
)
foreach ($definition in $definitions) { Add-ToolHandler $hookConfig $definition; $changed = $true }
if ($changed) {
    New-Item -ItemType Directory -Force -Path $CodexHome | Out-Null
    if ($hooksExist) { Copy-Item -LiteralPath $HooksPath -Destination "$HooksPath.better-compact-backup-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss')).json" -Force }
    $hookConfig | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $HooksPath -Encoding utf8
}

Write-Host "Installed Better Compact for $WorkspaceRoot" -ForegroundColor Green
Write-Host "Next: trust the three hook definitions in Codex, then run: & `"$RuntimeRoot\Watch-ContinuityDiagnostics.ps1`" -Tail 10" -ForegroundColor Cyan

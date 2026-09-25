[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'
$SourceRoot = Split-Path -Parent $PSScriptRoot
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')

if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
    throw "WorkspaceRoot does not exist or is not a directory: $WorkspaceRoot"
}
if ($PSVersionTable.PSVersion.Major -lt 5) {
    throw 'Windows PowerShell 5.1 or newer is required.'
}

$bytes = [System.Text.Encoding]::UTF8.GetBytes($WorkspaceRoot.ToLowerInvariant())
$hasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $workspaceHash = ([System.BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-', '').Substring(0, 16).ToLowerInvariant()
} finally {
    $hasher.Dispose()
}

$CodexHome = Join-Path $env:USERPROFILE '.codex'
$InstallRoot = Join-Path (Join-Path $CodexHome 'continuity-hooks') $workspaceHash
$StateRoot = Join-Path $InstallRoot 'state'
$HooksPath = Join-Path $CodexHome 'hooks.json'
$HookScriptPath = Join-Path $InstallRoot 'continuity.ps1'

if (Test-Path -LiteralPath $HooksPath -PathType Leaf) {
    $choice = Read-Host "Existing $HooksPath detected. Enter M to safely merge, or C to cancel"
    if ($choice -notmatch '^[Mm]$') {
        Write-Host 'Installation cancelled. Existing hooks.json was not changed.' -ForegroundColor Yellow
        exit 0
    }
    $backupPath = "$HooksPath.continuity-hooks-backup-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss')).json"
    Copy-Item -LiteralPath $HooksPath -Destination $backupPath -Force
    $hookConfig = Get-Content -LiteralPath $HooksPath -Raw | ConvertFrom-Json
} else {
    $hookConfig = [pscustomobject]@{ hooks = [pscustomobject]@{} }
}

New-Item -ItemType Directory -Force -Path $InstallRoot, $StateRoot | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'continuity.ps1') -Destination $HookScriptPath -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Watch-ContinuityDiagnostics.ps1') -Destination (Join-Path $InstallRoot 'Watch-ContinuityDiagnostics.ps1') -Force
$installConfig = [ordered]@{
    schemaVersion = 1
    workspaceRoot = $WorkspaceRoot
    stateRoot = $StateRoot
    installedAtUtc = [DateTime]::UtcNow.ToString('o')
}
$installConfig | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallRoot 'install.json') -Encoding utf8

if ($null -eq $hookConfig.hooks) {
    $hookConfig | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
}

$quotedScript = '"' + $HookScriptPath + '"'
$quotedWorkspace = '"' + $WorkspaceRoot + '"'
$quotedState = '"' + $StateRoot + '"'
$command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File $quotedScript -WorkspaceRoot $quotedWorkspace -StateRoot $quotedState"
$definitions = @(
    @{ event = 'SessionStart'; matcher = '^(startup|resume|compact)$'; contextLimit = 3000; status = 'Reloading workspace rules and recovery card' },
    @{ event = 'PreToolUse'; matcher = '^apply_patch$'; contextLimit = 3000; status = 'Reloading file-specific rules' },
    @{ event = 'PostToolUse'; matcher = '^apply_patch$'; contextLimit = 1000; status = 'Recording successful workspace edits' },
    @{ event = 'PreCompact'; matcher = '^(manual|auto)$'; contextLimit = $null; status = 'Saving recovery card' }
)

foreach ($definition in $definitions) {
    $property = $hookConfig.hooks.PSObject.Properties[$definition.event]
    if ($null -eq $property) {
        $hookConfig.hooks | Add-Member -NotePropertyName $definition.event -NotePropertyValue @()
    }
    $existing = @($hookConfig.hooks.($definition.event))
    $alreadyInstalled = $existing | Where-Object {
        $_.hooks | Where-Object { [string]$_.command -match [regex]::Escape($HookScriptPath) }
    }
    if ($alreadyInstalled) { continue }
    $handler = [ordered]@{
        type = 'command'
        command = $command
        commandWindows = $command
        timeout = 10
        statusMessage = $definition.status
    }
    if ($null -ne $definition.contextLimit) { $handler.additionalContextLimit = $definition.contextLimit }
    $group = [pscustomobject]@{ matcher = $definition.matcher; hooks = @([pscustomobject]$handler) }
    $hookConfig.hooks.($definition.event) = @($existing + $group)
}

$hookConfig | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $HooksPath -Encoding utf8
Write-Host "Installed continuity hooks for $WorkspaceRoot" -ForegroundColor Green
Write-Host "Next: trust the new hook definitions in Codex, then run: & `"$InstallRoot\Watch-ContinuityDiagnostics.ps1`" -Tail 10" -ForegroundColor Cyan

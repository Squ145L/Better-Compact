[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
$bytes = [System.Text.Encoding]::UTF8.GetBytes($WorkspaceRoot.ToLowerInvariant())
$hasher = [System.Security.Cryptography.SHA256]::Create()
try {
    $workspaceHash = ([System.BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-', '').Substring(0, 16).ToLowerInvariant()
} finally {
    $hasher.Dispose()
}
$CodexHome = Join-Path $env:USERPROFILE '.codex'
$InstallRoot = Join-Path (Join-Path $CodexHome 'continuity-hooks') $workspaceHash
$HooksPath = Join-Path $CodexHome 'hooks.json'
$HookScriptPath = Join-Path $InstallRoot 'continuity.ps1'

if (Test-Path -LiteralPath $HooksPath -PathType Leaf) {
    $hookConfig = Get-Content -LiteralPath $HooksPath -Raw | ConvertFrom-Json
    $changed = $false
    foreach ($eventName in @('SessionStart', 'PreToolUse', 'PostToolUse', 'PreCompact')) {
        $property = $hookConfig.hooks.PSObject.Properties[$eventName]
        if ($null -eq $property) { continue }
        $remaining = @($property.Value | Where-Object { -not ($_.hooks | Where-Object { [string]$_.command -match [regex]::Escape($HookScriptPath) }) })
        if ($remaining.Count -ne @($property.Value).Count) {
            $hookConfig.hooks.($eventName) = $remaining
            $changed = $true
        }
    }
    if ($changed) {
        $backupPath = "$HooksPath.continuity-hooks-backup-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss')).json"
        Copy-Item -LiteralPath $HooksPath -Destination $backupPath -Force
        $hookConfig | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $HooksPath -Encoding utf8
    }
}

if (Test-Path -LiteralPath $InstallRoot -PathType Container) {
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force
}
Write-Host "Removed continuity hooks for $WorkspaceRoot" -ForegroundColor Green

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$CodexHome = Join-Path $env:USERPROFILE '.codex'
$HooksPath = Join-Path $CodexHome 'hooks.json'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-Value($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}
function Read-Utf8Text([string]$Path) { return [System.IO.File]::ReadAllText($Path, $Utf8NoBom) }
function Write-JsonFile([string]$Path, $Value) { [System.IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 12) + [Environment]::NewLine), $Utf8NoBom) }
function Get-ToolRootFromCommand([string]$Command) {
    $match = [regex]::Match($Command, '(?i)-ToolRoot\s+"([^"]+)"')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}
function Test-VerifiedToolRoot([string]$ToolRoot) {
    try { $fullRoot = [System.IO.Path]::GetFullPath($ToolRoot).TrimEnd([char]92) } catch { return $false }
    $metadataPath = Join-Path $fullRoot 'install\install.json'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { return $false }
    try { $metadata = Read-Utf8Text $metadataPath | ConvertFrom-Json } catch { return $false }
    if ([string](Get-Value $metadata 'product') -ne 'better-compact') { return $false }
    $expectedWorkspace = [System.IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $fullRoot)))).TrimEnd([char]92)
    return ([string](Get-Value $metadata 'workspaceRoot')).TrimEnd([char]92) -eq $expectedWorkspace
}

if (-not (Test-Path -LiteralPath $HooksPath -PathType Leaf)) {
    Write-Host 'No hooks.json found; no Better Compact Hook needs cleanup.' -ForegroundColor Yellow
    exit 0
}

try { $hookConfig = Read-Utf8Text $HooksPath | ConvertFrom-Json } catch { throw "Existing hooks.json is not valid JSON: $HooksPath" }
$toolRoots = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
$removedHandlers = 0
$changed = $false
foreach ($eventName in @($hookConfig.hooks.PSObject.Properties.Name)) {
    $groups = @($hookConfig.hooks.$eventName)
    $remainingGroups = New-Object System.Collections.Generic.List[object]
    foreach ($group in $groups) {
        $remainingHandlers = New-Object System.Collections.Generic.List[object]
        foreach ($handler in @($group.hooks)) {
            $command = [string](Get-Value $handler 'command')
            $windowsCommand = [string](Get-Value $handler 'commandWindows')
            $isBetterCompact = $command -match '(?i)\\.agents\\skills\\better-compact\\runtime\\continuity\.ps1' -or $windowsCommand -match '(?i)\\.agents\\skills\\better-compact\\runtime\\continuity\.ps1'
            if (-not $isBetterCompact) { [void]$remainingHandlers.Add($handler); continue }
            foreach ($candidate in @((Get-ToolRootFromCommand $command), (Get-ToolRootFromCommand $windowsCommand))) {
                if ($candidate) { [void]$toolRoots.Add($candidate) }
            }
            $removedHandlers++
            $changed = $true
        }
        if ($remainingHandlers.Count -gt 0) { $group.hooks = $remainingHandlers.ToArray(); [void]$remainingGroups.Add($group) }
    }
    if ($remainingGroups.Count -gt 0) { $hookConfig.hooks.$eventName = $remainingGroups.ToArray() }
    else { $hookConfig.hooks.PSObject.Properties.Remove($eventName) }
}

if ($changed) {
    Copy-Item -LiteralPath $HooksPath -Destination "$HooksPath.better-compact-backup-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss')).json" -Force
    Write-JsonFile $HooksPath $hookConfig
}

$removedRoots = 0
foreach ($toolRoot in $toolRoots) {
    if (Test-VerifiedToolRoot $toolRoot) {
        Remove-Item -LiteralPath $toolRoot -Recurse -Force
        $removedRoots++
    } elseif (Test-Path -LiteralPath $toolRoot) {
        Write-Warning "Retained unverified Better Compact directory: $toolRoot"
    }
}

Write-Host "Removed $removedHandlers Better Compact Hook handler(s) and $removedRoots verified workspace installation(s)." -ForegroundColor Green

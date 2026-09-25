[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$WorkspaceRoot,
    [Parameter(Mandatory)]
    [string]$StateRoot
)

$ErrorActionPreference = 'Stop'
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
$StateRoot = [System.IO.Path]::GetFullPath($StateRoot).TrimEnd('\')
$ActivePath = Join-Path $StateRoot 'active-projects.json'
$DiagnosticPath = Join-Path $StateRoot 'continuity-diagnostic.jsonl'
$AuditPath = Join-Path $StateRoot 'recovery-audit.jsonl'

New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

function Get-Value($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Write-JsonLine([string]$Path, $Value) {
    ($Value | ConvertTo-Json -Depth 12 -Compress) | Add-Content -LiteralPath $Path -Encoding utf8
}

function Write-Diagnostic([string]$Stage, [string]$Outcome, [string]$Project, [string]$Detail, $Event) {
    $entry = [ordered]@{
        timestampUtc = [DateTime]::UtcNow.ToString('o')
        stage = $Stage
        outcome = $Outcome
        project = $Project
        source = [string](Get-Value $Event 'source')
        trigger = [string](Get-Value $Event 'trigger')
        detail = $Detail
    }
    Write-JsonLine $DiagnosticPath $entry
    [Console]::Error.WriteLine("[continuity] $Stage/$Outcome project=$Project detail=$Detail")
}

function Write-Audit([string]$Stage, [string]$Project, [string]$Detail, $Event) {
    Write-JsonLine $AuditPath ([ordered]@{
        timestampUtc = [DateTime]::UtcNow.ToString('o')
        stage = $Stage
        project = $Project
        sessionId = [string](Get-Value $Event 'session_id')
        detail = $Detail
    })
}

function Get-PathKey([string]$Path) {
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\').ToLowerInvariant()
}

function Read-ActiveProjects {
    if (-not (Test-Path -LiteralPath $ActivePath -PathType Leaf)) { return [pscustomobject]@{} }
    try { return Get-Content -LiteralPath $ActivePath -Raw | ConvertFrom-Json } catch { return [pscustomobject]@{} }
}

function Set-ActiveProject([string]$Cwd, [string]$Project) {
    $active = Read-ActiveProjects
    $key = Get-PathKey $Cwd
    $property = $active.PSObject.Properties[$key]
    if ($null -eq $property) { $active | Add-Member -NotePropertyName $key -NotePropertyValue $Project }
    else { $property.Value = $Project }
    $active | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ActivePath -Encoding utf8
}

function Get-ActiveProject([string]$Cwd) {
    $active = Read-ActiveProjects
    foreach ($candidate in @($Cwd, $WorkspaceRoot)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $property = $active.PSObject.Properties[(Get-PathKey $candidate)]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) { return [string]$property.Value }
    }
    return $null
}

function Get-ProjectNameForPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try { $fullPath = [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRoot $Path)) } catch { return $null }
    $prefix = $WorkspaceRoot + '\'
    if (-not $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    $relative = $fullPath.Substring($prefix.Length)
    if ([string]::IsNullOrWhiteSpace($relative) -or $relative -notmatch '^[^\\/]+') { return $null }
    $project = ($relative -split '[\\/]')[0]
    if ($project -in @('.codex', 'docs')) { return $null }
    if (-not (Test-Path -LiteralPath (Join-Path $WorkspaceRoot $project) -PathType Container)) { return $null }
    return $project
}

function Get-PatchTargetPaths($Event) {
    $input = Get-Value $Event 'tool_input'
    $command = [string](Get-Value $input 'command')
    if ([string]::IsNullOrWhiteSpace($command)) { return @() }
    $matches = [regex]::Matches($command, '(?m)^\*\*\* (?:Add|Update|Delete) File: ([^\r\n]+)$')
    return @($matches | ForEach-Object { $_.Groups[1].Value.Trim() })
}

function Get-RuleContext([string]$Project, [string[]]$Targets) {
    $ruleFiles = New-Object System.Collections.Generic.List[string]
    foreach ($relative in @('AGENTS.md', 'README.md')) {
        $candidate = Join-Path $WorkspaceRoot $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { [void]$ruleFiles.Add($candidate) }
    }
    if (-not [string]::IsNullOrWhiteSpace($Project)) {
        $projectRoot = Join-Path $WorkspaceRoot $Project
        foreach ($relative in @('AGENTS.md', 'README.md')) {
            $candidate = Join-Path $projectRoot $relative
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { [void]$ruleFiles.Add($candidate) }
        }
    }
    $items = foreach ($file in $ruleFiles | Select-Object -Unique) {
        $text = Get-Content -LiteralPath $file -Raw
        if ($text.Length -gt 5000) { $text = $text.Substring(0, 5000) + "`n[truncated]" }
        "### Rules: $file`n$text"
    }
    return ($items -join "`n`n")
}

function Get-RecoveryCardPath([string]$Project) { return Join-Path (Join-Path $StateRoot 'recovery') "$Project.json" }

function Read-RecoveryCard([string]$Project) {
    $path = Get-RecoveryCardPath $Project
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
}

function Write-RecoveryCard([string]$Project, [string[]]$Targets, $Event) {
    $directory = Join-Path $StateRoot 'recovery'
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $previous = Read-RecoveryCard $Project
    $files = New-Object System.Collections.Generic.List[string]
    foreach ($oldFile in @(Get-Value $previous 'files')) { if (-not [string]::IsNullOrWhiteSpace([string]$oldFile)) { [void]$files.Add([string]$oldFile) } }
    foreach ($target in $Targets) { if (-not [string]::IsNullOrWhiteSpace($target) -and -not $files.Contains($target)) { [void]$files.Add($target) } }
    while ($files.Count -gt 50) { $files.RemoveAt(0) }
    $now = [DateTime]::UtcNow.ToString('o')
    $card = [ordered]@{
        schemaVersion = 1
        project = $Project
        lastSuccessfulEditAt = $now
        lastSuccessfulEditSessionId = [string](Get-Value $Event 'session_id')
        lastCompactedAt = Get-Value $previous 'lastCompactedAt'
        lastCompactedSessionId = Get-Value $previous 'lastCompactedSessionId'
        files = @($files)
    }
    $card | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Get-RecoveryCardPath $Project) -Encoding utf8
    return $card
}

function Mark-RecoveryCardCompacted([string]$Project, $Event) {
    $card = Read-RecoveryCard $Project
    if ($null -eq $card) { return $false }
    $card.lastCompactedAt = [DateTime]::UtcNow.ToString('o')
    $card.lastCompactedSessionId = [string](Get-Value $Event 'session_id')
    $card | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Get-RecoveryCardPath $Project) -Encoding utf8
    return $true
}

function Send-Context([string]$HookEventName, [string]$Context) {
    if ([string]::IsNullOrWhiteSpace($Context)) { return }
    [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = $HookEventName; additionalContext = $Context } } | ConvertTo-Json -Depth 8 -Compress
}

try {
    $rawEvent = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($rawEvent)) { exit 0 }
    $event = $rawEvent | ConvertFrom-Json
    $stage = [string](Get-Value $event 'hook_event_name')
    $cwd = [string](Get-Value $event 'cwd')
    if ([string]::IsNullOrWhiteSpace($cwd)) { $cwd = $WorkspaceRoot }

    switch ($stage) {
        'PreToolUse' {
            $targets = @(Get-PatchTargetPaths $event)
            $projects = @($targets | ForEach-Object { Get-ProjectNameForPath $_ } | Where-Object { $_ } | Select-Object -Unique)
            if ($projects.Count -eq 0) { Write-Diagnostic $stage 'skipped' '-' 'reason=no-workspace-project-targets' $event; break }
            $project = $projects[0]
            Set-ActiveProject $cwd $project
            $context = Get-RuleContext $project $targets
            Send-Context $stage $context
            Write-Diagnostic $stage 'reloaded' $project "targetCount=$($targets.Count); ruleCount=$(if ($context) { 1 } else { 0 })" $event
            Write-Audit $stage $project "targetCount=$($targets.Count)" $event
        }
        'PostToolUse' {
            $response = Get-Value $event 'tool_response'
            if ((Get-Value $response 'success') -eq $false) { Write-Diagnostic $stage 'skipped' '-' 'reason=tool-unsuccessful' $event; break }
            $targets = @(Get-PatchTargetPaths $event)
            $projects = @($targets | ForEach-Object { Get-ProjectNameForPath $_ } | Where-Object { $_ } | Select-Object -Unique)
            if ($projects.Count -eq 0) { Write-Diagnostic $stage 'skipped' '-' 'reason=no-workspace-project-targets' $event; break }
            foreach ($project in $projects) {
                $projectTargets = @($targets | Where-Object { (Get-ProjectNameForPath $_) -eq $project })
                [void](Write-RecoveryCard $project $projectTargets $event)
                Set-ActiveProject $cwd $project
                Write-Audit $stage $project "targetCount=$($projectTargets.Count)" $event
            }
            Write-Diagnostic $stage 'recorded' ($projects -join ',') "recordedProjects=$($projects -join ',')" $event
        }
        'PreCompact' {
            $project = Get-ActiveProject $cwd
            if ([string]::IsNullOrWhiteSpace($project)) { Write-Diagnostic $stage 'skipped' '-' 'reason=no-active-project' $event; break }
            if (Mark-RecoveryCardCompacted $project $event) {
                Write-Audit $stage $project 'recovery-card-marked-compacted' $event
                Write-Diagnostic $stage 'recorded' $project 'recovery-card-marked-compacted' $event
            } else { Write-Diagnostic $stage 'skipped' $project 'reason=no-recovery-card' $event }
        }
        'SessionStart' {
            $project = Get-ActiveProject $cwd
            $context = Get-RuleContext $project @()
            $card = if ($project) { Read-RecoveryCard $project } else { $null }
            if ($card) { $context = ($context, "### Recovery card: $project`n$($card | ConvertTo-Json -Depth 8)") -join "`n`n" }
            Send-Context $stage $context
            $source = [string](Get-Value $event 'source')
            Write-Diagnostic $stage 'reloaded' $(if ($project) { $project } else { '-' }) "projectSource=$(if ($project) { 'active' } else { 'none' }); cardFound=$([bool]$card)" $event
            Write-Audit $stage $(if ($project) { $project } else { '-' }) "source=$source; cardFound=$([bool]$card)" $event
        }
        default { Write-Diagnostic $stage 'ignored' '-' 'reason=unsupported-event' $event }
    }
} catch {
    try { Write-Diagnostic 'Dispatch' 'failed' '-' $_.Exception.Message $null } catch { [Console]::Error.WriteLine("[continuity] Dispatch/failed: $($_.Exception.Message)") }
    exit 1
}

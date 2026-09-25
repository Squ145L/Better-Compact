[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Hook = Join-Path $PSScriptRoot 'continuity.ps1'
$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-continuity-hooks-test-" + [guid]::NewGuid().ToString('N'))
$Workspace = Join-Path $TestRoot 'workspace'
$State = Join-Path $TestRoot 'state'

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "ASSERTION FAILED: $Message" } }
function Invoke-Hook($Event) {
    $payload = $Event | ConvertTo-Json -Depth 10 -Compress
    $lines = $payload | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Hook -WorkspaceRoot $Workspace -StateRoot $State 2>&1
    return @($lines | Where-Object { $_ -match '^\{' })
}

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $Workspace 'project-a'), (Join-Path $Workspace 'docs') | Out-Null
    Set-Content -LiteralPath (Join-Path $Workspace 'AGENTS.md') -Value '# Root rule' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $Workspace 'project-a\AGENTS.md') -Value '# Project rule' -Encoding utf8
    $base = @{ session_id = 'test-session'; cwd = $Workspace; tool_name = 'apply_patch' }
    $post = $base.Clone(); $post.hook_event_name = 'PostToolUse'; $post.tool_input = @{ command = "*** Add File: project-a\probe.txt`n+ok" }; $post.tool_response = @{ success = $true }
    Invoke-Hook $post | Out-Null
    $cardPath = Join-Path $State 'recovery\project-a.json'
    Assert-True (Test-Path -LiteralPath $cardPath) 'successful create should write a recovery card'
    $card = Get-Content -LiteralPath $cardPath -Raw | ConvertFrom-Json
    Assert-True ($card.files -contains 'project-a\probe.txt') 'created file should be listed'
    $update = $base.Clone(); $update.hook_event_name = 'PostToolUse'; $update.tool_input = @{ command = "*** Update File: project-a\probe.txt`n@@" }; $update.tool_response = @{ success = $true }
    Invoke-Hook $update | Out-Null
    $delete = $base.Clone(); $delete.hook_event_name = 'PostToolUse'; $delete.tool_input = @{ command = "*** Delete File: project-a\old.txt" }; $delete.tool_response = @{ success = $true }
    Invoke-Hook $delete | Out-Null
    $card = Get-Content -LiteralPath $cardPath -Raw | ConvertFrom-Json
    Assert-True ($card.files -contains 'project-a\old.txt') 'deleted file should be listed'
    $failed = $base.Clone(); $failed.hook_event_name = 'PostToolUse'; $failed.tool_input = @{ command = "*** Add File: project-a\ignored.txt" }; $failed.tool_response = @{ success = $false }
    Invoke-Hook $failed | Out-Null
    $card = Get-Content -LiteralPath $cardPath -Raw | ConvertFrom-Json
    Assert-True (-not ($card.files -contains 'project-a\ignored.txt')) 'failed tool result must not be recorded'
    $compact = @{ hook_event_name = 'PreCompact'; session_id = 'test-session'; cwd = $Workspace; trigger = 'manual' }
    Invoke-Hook $compact | Out-Null
    $card = Get-Content -LiteralPath $cardPath -Raw | ConvertFrom-Json
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$card.lastCompactedAt)) 'compact should mark the current card'
    $resume = @{ hook_event_name = 'SessionStart'; session_id = 'test-session'; cwd = $Workspace; source = 'compact' }
    $output = (Invoke-Hook $resume | Select-Object -Last 1) | ConvertFrom-Json
    Assert-True ($output.hookSpecificOutput.hookEventName -eq 'SessionStart') 'resume output must identify the SessionStart event'
    Assert-True ($output.hookSpecificOutput.additionalContext -match 'Recovery card: project-a') 'compact resume should inject the recovery card'
    $pre = $base.Clone(); $pre.hook_event_name = 'PreToolUse'; $pre.tool_input = @{ command = "*** Update File: project-a\probe.txt`n@@" }
    $output = (Invoke-Hook $pre | Select-Object -Last 1) | ConvertFrom-Json
    Assert-True ($output.hookSpecificOutput.hookEventName -eq 'PreToolUse') 'pre-tool output must identify the PreToolUse event'
    $docs = $base.Clone(); $docs.hook_event_name = 'PostToolUse'; $docs.tool_input = @{ command = "*** Add File: docs\ignored.md`n+x" }; $docs.tool_response = @{ success = $true }
    Invoke-Hook $docs | Out-Null
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $State 'recovery\docs.json'))) 'shared docs must not become a project'
    Write-Host 'PASS: create, update, delete, failed edit, compact resume, and shared-doc exclusion.' -ForegroundColor Green
} finally {
    if ((Test-Path -LiteralPath $TestRoot) -and $TestRoot.StartsWith([System.IO.Path]::GetTempPath(), [System.StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
}

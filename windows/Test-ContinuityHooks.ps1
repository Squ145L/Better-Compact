[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$DistributionRoot = Split-Path -Parent $PSScriptRoot
$Installer = Join-Path $PSScriptRoot 'Install.ps1'
$Launcher = Join-Path $DistributionRoot 'Install.cmd'
$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('better-compact-test-' + [guid]::NewGuid().ToString('N'))
$Workspace = Join-Path $TestRoot 'workspace'
$TestHome = Join-Path $TestRoot 'home'
$OriginalUserProfile = $env:USERPROFILE

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "ASSERTION FAILED: $Message" } }
function Assert-Utf8WithoutBom([string]$Path, [string]$Message) {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Assert-True (-not $hasBom) $Message
}
function Invoke-InstalledHook($Event) {
    $payload = $Event | ConvertTo-Json -Depth 10 -Compress
    $runtime = Join-Path $Workspace '.agents\skills\better-compact\runtime'
    $hook = Join-Path $runtime 'continuity.ps1'
    $toolRoot = Split-Path -Parent $runtime
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = $payload | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hook -WorkspaceRoot $Workspace -ToolRoot $toolRoot 2>&1
    } finally { $ErrorActionPreference = $previousErrorActionPreference }
    return @($lines | Where-Object { $_ -match '^\{' })
}
function Invoke-InstalledHookRaw([string]$Payload) {
    $runtime = Join-Path $Workspace '.agents\skills\better-compact\runtime'
    $hook = Join-Path $runtime 'continuity.ps1'
    $toolRoot = Split-Path -Parent $runtime
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        return @($Payload | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hook -WorkspaceRoot $Workspace -ToolRoot $toolRoot 2>&1)
    } finally { $ErrorActionPreference = $previousErrorActionPreference }
}
function Invoke-Controller([string]$Action, [bool]$Enabled = $true) {
    $controller = Join-Path $Workspace '.agents\skills\better-compact\runtime\Control.ps1'
    return @(& $controller -Action $Action -Enabled $Enabled 2>&1)
}
function Invoke-InteractiveInstaller([string]$TargetWorkspace = $Workspace, [switch]$UseLauncher) {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    if ($UseLauncher) {
        $processInfo.FileName = 'cmd.exe'
        $processInfo.Arguments = "/d /c `"`"$Launcher`"`""
    } else {
        $processInfo.FileName = 'powershell.exe'
        $processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Installer`""
    }
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.EnvironmentVariables['USERPROFILE'] = $TestHome
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    [void]$process.Start()
    $process.StandardInput.WriteLine($TargetWorkspace)
    $process.StandardInput.WriteLine('M')
    $process.StandardInput.WriteLine('')
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ exitCode = $process.ExitCode; output = $stdout + $stderr }
}

try {
    New-Item -ItemType Directory -Force -Path (Join-Path $Workspace 'project-a'), (Join-Path $Workspace 'project-b'), (Join-Path $Workspace 'docs'), $TestHome | Out-Null
    Set-Content -LiteralPath (Join-Path $Workspace 'AGENTS.md') -Value '# Root rule' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $Workspace 'README.md') -Value 'README-MUST-NOT-INJECT' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $Workspace 'project-a\AGENTS.md') -Value '# Project rule' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $Workspace 'project-a\TASK_STATE.md') -Value '# Project task state' -Encoding utf8
    $env:USERPROFILE = $TestHome
    $codexHome = Join-Path $TestHome '.codex'
    New-Item -ItemType Directory -Force -Path $codexHome | Out-Null
    [pscustomobject]@{ hooks = [pscustomobject]@{ SessionStart = @([pscustomobject]@{ matcher = '^startup$'; hooks = @([pscustomobject]@{ command = 'echo user-hook' }) }) } } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $codexHome 'hooks.json') -Encoding utf8

    & $Installer -WorkspaceRoot $Workspace -ExistingHooksAction Merge
    $toolRoot = Join-Path $Workspace '.agents\skills\better-compact'
    $runtime = Join-Path $toolRoot 'runtime'
    Assert-True (Test-Path -LiteralPath (Join-Path $toolRoot 'SKILL.md')) 'installer should copy the workspace-local Skill'
    Assert-True (Test-Path -LiteralPath (Join-Path $runtime 'Uninstall.ps1')) 'installer should copy the workspace-local uninstaller'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $DistributionRoot 'prompts\task-state.md')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $toolRoot 'prompts\task-state.md')).Hash) 'installer should copy the exact TASK_STATE management prompt'
    $config = Get-Content -LiteralPath (Join-Path $toolRoot 'config\workspace.json') -Raw | ConvertFrom-Json
    Assert-True ($config.coreEnabled -and $config.taskStateEnabled) 'fresh installation should default both switches to ON'
    Assert-Utf8WithoutBom (Join-Path $toolRoot 'config\workspace.json') 'installer must write workspace config without a UTF-8 BOM'
    Assert-Utf8WithoutBom (Join-Path $toolRoot 'install\install.json') 'installer must write installation metadata without a UTF-8 BOM'
    $status = Invoke-Controller Status | Out-String
    foreach ($field in @('Core:', 'TASK_STATE:', 'Workspace:', 'Tool directory:', 'Active project:', 'Recovery Card directory:')) { Assert-True ($status -match [regex]::Escape($field)) "status should include $field" }
    $hooks = Get-Content -LiteralPath (Join-Path $codexHome 'hooks.json') -Raw | ConvertFrom-Json
    Assert-Utf8WithoutBom (Join-Path $codexHome 'hooks.json') 'installer must write hooks.json without a UTF-8 BOM'
    Assert-True ($null -eq $hooks.hooks.PSObject.Properties['PreToolUse']) 'installer must not register PreToolUse'
    foreach ($eventName in @('SessionStart', 'PostToolUse', 'PreCompact')) {
        Assert-True ($null -ne $hooks.hooks.PSObject.Properties[$eventName]) "installer should register $eventName"
    }
    $sessionGroup = @($hooks.hooks.SessionStart | Where-Object { $_.hooks.command -match [regex]::Escape((Join-Path $runtime 'continuity.ps1')) })[0]
    Assert-True ($sessionGroup.matcher -eq '^(compact|resume)$') 'SessionStart matcher should exclude startup'
    Assert-True ($hooks.hooks.SessionStart[0].hooks.command -eq 'echo user-hook') 'installer must preserve existing user hooks'
    Assert-True ((Get-ChildItem -LiteralPath $codexHome -Filter 'hooks.json.better-compact-backup-*.json').Count -eq 1) 'merging existing hooks must create a backup beside hooks.json'

    $base = @{ session_id = 'test-session'; cwd = $Workspace; tool_name = 'apply_patch' }
    $post = $base.Clone(); $post.hook_event_name = 'PostToolUse'; $post.tool_input = @{ command = "*** Add File: project-a\probe.txt`n+ok" }; $post.tool_response = @{ success = $true }
    Invoke-InstalledHook $post | Out-Null
    $cardPath = Join-Path $toolRoot 'recovery\project-a.json'
    Assert-True (Test-Path -LiteralPath $cardPath) 'successful edit should write a recovery card'
    $successWithoutFlag = $base.Clone(); $successWithoutFlag.hook_event_name = 'PostToolUse'; $successWithoutFlag.tool_input = @{ command = "*** Add File: project-a\response-without-success.txt`n+x" }; $successWithoutFlag.tool_response = @{}
    Invoke-InstalledHook $successWithoutFlag | Out-Null
    $card = Get-Content -LiteralPath $cardPath -Raw | ConvertFrom-Json
    Assert-True ($card.files -contains 'project-a\response-without-success.txt') 'successful tool responses without a success field should be recorded'
    $absolute = $base.Clone(); $absolute.hook_event_name = 'PostToolUse'; $absolute.tool_input = @{ command = "*** Add File: $(Join-Path $Workspace 'project-b\absolute-path.txt')`n+ok" }; $absolute.tool_response = @{ success = $true }
    Invoke-InstalledHook $absolute | Out-Null
    $absoluteCardPath = Join-Path $toolRoot 'recovery\project-b.json'
    Assert-True (Test-Path -LiteralPath $absoluteCardPath) 'absolute project paths should write a recovery card'
    $absoluteCard = Get-Content -LiteralPath $absoluteCardPath -Raw | ConvertFrom-Json
    Assert-True ($absoluteCard.files -contains (Join-Path $Workspace 'project-b\absolute-path.txt')) 'absolute project paths should retain their patch target'
    $absoluteResume = @{ hook_event_name = 'SessionStart'; session_id = 'test-session'; cwd = $Workspace; source = 'compact' }
    $absoluteOutput = (Invoke-InstalledHook $absoluteResume | Select-Object -Last 1) | ConvertFrom-Json
    Assert-True ($absoluteOutput.hookSpecificOutput.additionalContext -match 'Recovery Card: project-b') 'absolute project paths should be injected after compact'
    $restoreProjectA = $base.Clone(); $restoreProjectA.hook_event_name = 'PostToolUse'; $restoreProjectA.tool_input = @{ command = "*** Update File: project-a\probe.txt`n+still-active" }; $restoreProjectA.tool_response = @{ success = $true }
    Invoke-InstalledHook $restoreProjectA | Out-Null
    $outside = $base.Clone(); $outside.hook_event_name = 'PostToolUse'; $outside.tool_input = @{ command = "*** Add File: $(Join-Path $TestRoot 'outside.txt')`n+blocked" }; $outside.tool_response = @{ success = $true }
    Invoke-InstalledHook $outside | Out-Null
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $toolRoot 'recovery\outside.json'))) 'workspace-external absolute paths must not create recovery cards'
    $failed = $base.Clone(); $failed.hook_event_name = 'PostToolUse'; $failed.tool_input = @{ command = "*** Add File: project-a\ignored.txt`n+x" }; $failed.tool_response = @{ success = $false }
    Invoke-InstalledHook $failed | Out-Null
    $card = Get-Content -LiteralPath $cardPath -Raw | ConvertFrom-Json
    Assert-True (-not ($card.files -contains 'project-a\ignored.txt')) 'failed edit must not update a recovery card'
    $docs = $base.Clone(); $docs.hook_event_name = 'PostToolUse'; $docs.tool_input = @{ command = "*** Add File: docs\ignored.md`n+x" }; $docs.tool_response = @{ success = $true }
    Invoke-InstalledHook $docs | Out-Null
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $toolRoot 'recovery\docs.json'))) 'shared docs must not become a project'
    $toolEdit = $base.Clone(); $toolEdit.hook_event_name = 'PostToolUse'; $toolEdit.tool_input = @{ command = "*** Add File: .agents\skills\better-compact\ignored.txt`n+x" }; $toolEdit.tool_response = @{ success = $true }
    Invoke-InstalledHook $toolEdit | Out-Null
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $toolRoot 'recovery\.agents.json'))) 'tool directory must not become a project'

    $compact = @{ hook_event_name = 'PreCompact'; session_id = 'test-session'; cwd = $Workspace; trigger = 'manual' }
    Invoke-InstalledHook $compact | Out-Null
    $card = Get-Content -LiteralPath $cardPath -Raw | ConvertFrom-Json
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$card.lastCompactedAt)) 'PreCompact should mark the active recovery card'
    $resume = @{ hook_event_name = 'SessionStart'; session_id = 'test-session'; cwd = $Workspace; source = 'compact' }
    $output = (Invoke-InstalledHook $resume | Select-Object -Last 1) | ConvertFrom-Json
    $context = [string]$output.hookSpecificOutput.additionalContext
    Assert-True ($context -notmatch 'README-MUST-NOT-INJECT') 'README must not be reinjected'
    $rootIndex = $context.IndexOf('# Root rule'); $projectIndex = $context.IndexOf('# Project rule'); $promptIndex = $context.IndexOf('TASK_STATE management prompt'); $stateIndex = $context.IndexOf('# Project task state'); $cardIndex = $context.IndexOf('Recovery Card: project-a')
    Assert-True ($rootIndex -ge 0 -and $rootIndex -lt $projectIndex -and $projectIndex -lt $promptIndex -and $promptIndex -lt $stateIndex -and $stateIndex -lt $cardIndex) "resume injection order must be rules, prompt, TASK_STATE, recovery card (indices: $rootIndex, $projectIndex, $promptIndex, $stateIndex, $cardIndex)"
    $startup = @{ hook_event_name = 'SessionStart'; session_id = 'test-session'; cwd = $Workspace; source = 'startup' }
    Assert-True ((Invoke-InstalledHook $startup).Count -eq 0) 'startup must not inject context'

    Invoke-Controller SetTaskState $false | Out-Null
    $taskOff = (Invoke-InstalledHook $resume | Select-Object -Last 1) | ConvertFrom-Json
    Assert-True ($taskOff.hookSpecificOutput.additionalContext -notmatch 'TASK_STATE management prompt') ("TASK_STATE off must skip management prompt; status=" + ((Invoke-Controller Status | Out-String).Trim()))
    Assert-True ($taskOff.hookSpecificOutput.additionalContext -notmatch '# Project task state') 'TASK_STATE off must skip project state'
    Assert-True ($taskOff.hookSpecificOutput.additionalContext -match 'Recovery Card: project-a') 'TASK_STATE off must retain recovery card'
    Invoke-Controller SetCore $false | Out-Null
    $logPath = Join-Path $toolRoot 'logs\continuity-diagnostic.jsonl'; $logLength = (Get-Item -LiteralPath $logPath).Length
    $coreOff = $base.Clone(); $coreOff.hook_event_name = 'PostToolUse'; $coreOff.tool_input = @{ command = "*** Add File: project-a\core-off.txt`n+x" }; $coreOff.tool_response = @{ success = $true }
    Assert-True ((Invoke-InstalledHook $coreOff).Count -eq 0) 'Core off must have no hook output'
    $card = Get-Content -LiteralPath $cardPath -Raw | ConvertFrom-Json
    Assert-True (-not ($card.files -contains 'project-a\core-off.txt')) 'Core off must not update recovery data'
    Assert-True ((Get-Item -LiteralPath $logPath).Length -eq $logLength) 'Core off must not write diagnostics'
    Invoke-Controller SetCore $true | Out-Null
    $invalidPayloadMarker = 'MUST-NOT-APPEAR-IN-DIAGNOSTICS'
    Invoke-InstalledHookRaw ("{invalid-json:$invalidPayloadMarker}") | Out-Null
    $invalidEntry = Get-Content -LiteralPath $logPath -Tail 1 | ConvertFrom-Json
    Assert-True ($invalidEntry.stage -eq 'Dispatch' -and $invalidEntry.outcome -eq 'failed') 'invalid Hook JSON should record a dispatch failure'
    Assert-True ($invalidEntry.detail -match '^reason=invalid-hook-json; inputLength=\d+$') 'invalid Hook JSON diagnostics should be bounded to the input length'
    Assert-True ($invalidEntry.detail -notmatch $invalidPayloadMarker) 'invalid Hook JSON diagnostics must not store raw payload content'
    Remove-Item -LiteralPath (Join-Path $toolRoot 'config\workspace.json') -Force
    $missingConfig = (Invoke-InstalledHook $resume | Select-Object -Last 1) | ConvertFrom-Json
    Assert-True ($missingConfig.hookSpecificOutput.additionalContext -match 'TASK_STATE management prompt') 'missing config must default TASK_STATE to ON'
    Set-Content -LiteralPath (Join-Path $toolRoot 'config\workspace.json') -Value '{bad json' -Encoding utf8
    Assert-True ((Invoke-Controller Status | Out-String) -match 'Core: ON') 'corrupt config must default Core to ON'

    $preUpgradeCardHash = (Get-FileHash -LiteralPath $cardPath).Hash
    $preUpgradeLogLength = (Get-Item -LiteralPath $logPath).Length
    & $Installer -WorkspaceRoot $Workspace -ExistingHooksAction Merge
    Assert-True ((Get-Content -LiteralPath (Join-Path $toolRoot 'config\workspace.json') -Raw) -match '^\{bad json') 'install should retain corrupt config for runtime fallback, not overwrite it'
    Assert-True ((Get-FileHash -LiteralPath $cardPath).Hash -eq $preUpgradeCardHash) 'upgrade should preserve recovery cards'
    Assert-True ((Get-Item -LiteralPath $logPath).Length -eq $preUpgradeLogLength) 'upgrade should preserve diagnostic logs'
    $interactiveInstall = Invoke-InteractiveInstaller
    Assert-True ($interactiveInstall.exitCode -eq 0) 'interactive installer should complete successfully'
    $installerSource = Get-Content -LiteralPath $Installer -Raw
    Assert-True ($installerSource.Contains('请输入codex工作区路径，例如：D:\codex workspace')) 'interactive installer should show the workspace path example'
    Assert-True ($installerSource.Contains('安装完成，按 Enter 关闭窗口')) 'interactive installer should wait before closing'
    Assert-True ($installerSource.Contains('安装并保留其他 Hook，请输入 M 后回车；输入 C 取消')) 'interactive installer should explain the merge and cancel choices in Chinese'
    Assert-True (Test-Path -LiteralPath $Launcher -PathType Leaf) 'the distribution should include a double-click installer launcher'
    $launcherInstall = Invoke-InteractiveInstaller -UseLauncher
    Assert-True ($launcherInstall.exitCode -eq 0) 'double-click installer launcher should complete successfully'
    $unknownWorkspace = Join-Path $TestRoot 'unknown-workspace'
    New-Item -ItemType Directory -Force -Path (Join-Path $unknownWorkspace '.agents\skills\better-compact') | Out-Null
    $unknownFailed = $false
    try { & $Installer -WorkspaceRoot $unknownWorkspace -ExistingHooksAction Merge } catch { $unknownFailed = $true }
    Assert-True $unknownFailed 'installer must refuse an unknown existing Better Compact directory'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $unknownWorkspace '.agents\skills\better-compact\install\install.json'))) 'unknown directory must remain untouched'
    $interactiveError = Invoke-InteractiveInstaller $unknownWorkspace
    Assert-True ($interactiveError.exitCode -eq 1) 'interactive installer should return a failure status after an installation error'
    Assert-True ($installerSource.Contains('安装失败：')) 'interactive installer should show a readable installation error'

    & (Join-Path $runtime 'Uninstall.ps1')
    Assert-True (-not (Test-Path -LiteralPath $toolRoot)) 'uninstaller should remove only the workspace-local Better Compact directory'
    $hooks = Get-Content -LiteralPath (Join-Path $codexHome 'hooks.json') -Raw | ConvertFrom-Json
    Assert-True ($hooks.hooks.SessionStart[0].hooks.command -eq 'echo user-hook') 'uninstaller must preserve user hooks'
    Assert-True ($null -eq $hooks.hooks.PSObject.Properties['PreToolUse']) 'uninstaller must not add or retain a Better Compact PreToolUse hook'
    Write-Host 'PASS: installation, switches, three-hook lifecycle, recovery injection, upgrade safety, and workspace-local uninstall.' -ForegroundColor Green
} finally {
    $env:USERPROFILE = $OriginalUserProfile
    if ((Test-Path -LiteralPath $TestRoot) -and $TestRoot.StartsWith([System.IO.Path]::GetTempPath(), [System.StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
}

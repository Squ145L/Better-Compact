# Better Compact 高级使用

## 文件位置

全局 Skill 安装在：

```text
C:\Users\<你>\.agents\skills\better-compact\
```

每个工作区独立保存运行文件、配置、恢复数据和日志：

```text
<workspace>\.agents\skills\better-compact\
├─ config\workspace.json
├─ prompts\task-state.md
├─ recovery\
├─ logs\
├─ runtime\
└─ install\install.json
```

`TASK_STATE.md` 位于具体项目根目录。全局 Skill 只有在项目唯一时才创建或静默维护它。

## 开关

`config\workspace.json`：

```json
{
  "schemaVersion": 1,
  "coreEnabled": true,
  "taskStateEnabled": true
}
```

- `coreEnabled: false`：暂停当前工作区的 Better Compact。
- `taskStateEnabled: false`：保留恢复功能，但不使用项目 `TASK_STATE.md`。

保存后下一次事件生效，无需重装。文件缺失或格式错误时按开启处理。

## 排查

依次检查：

1. `coreEnabled` 是否为 `true`。
2. Codex **设置 → 钩子** 中三个 Better Compact 项目是否已批准。
3. 当前项目是否已有成功的 `apply_patch` 编辑。
4. 查看 `logs\continuity-diagnostic.jsonl`。

实时查看最近日志：

```powershell
& "D:\my-workspace\.agents\skills\better-compact\runtime\Watch-ContinuityDiagnostics.ps1" -Tail 10
```

## 手动安装与升级

双击发行包的 `Install.cmd`，直接输入 workspace 路径；安装器会同时安装全局 Skill、工作区运行文件、配置和三个 Hook。

也可在命令行明确指定：

```powershell
# 全局 Skill、workspace 运行文件、配置和 Hook
.\windows\Install.ps1 -WorkspaceRoot "D:\my-workspace"
```

工作区安装会保留现有其他 Hook，并在修改 `hooks.json` 前创建带时间戳的备份。它也会确保本机全局 Skill 可用；同一名称不会再写入工作区，避免出现两个 Better Compact Skill。

## 卸载当前工作区

```powershell
& "D:\my-workspace\.agents\skills\better-compact\runtime\Uninstall.ps1"
```

这只会移除当前工作区的运行文件和对应 Hook，不会删除全局 Skill、其他工作区、其他 Hook 或项目的 `TASK_STATE.md`。

## 功能边界

只支持 Windows。不保存完整聊天、原始 patch、密码、令牌或私密数据；不自动选择不唯一的项目。

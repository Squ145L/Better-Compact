# Better Compact: Context Continuity for Codex (Windows)
# 更好的 Compact： Codex连续上下文优化

减少 Codex 在 compact 后丢失任务状态和最近编辑线索的情况。

## 30 秒开始

Better Compact 在 Codex 压缩上下文或恢复会话后，补回项目任务状态和最近编辑记录。`AGENTS.md` 由 Codex 自行加载

### 方式一：手动安装

双击 `Install.cmd`，直接输入工作区路径。安装器会安装全局 Skill、该工作区的运行文件和三个 Hook。完成后到 Codex **设置 → 钩子** 审阅并批准这三个 Hook。

或者

也可以在发行包目录运行，把路径改成你要使用的工作区：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\Install.ps1 -WorkspaceRoot "D:\my-workspace"
```

使用工作区安装方式时，未批准 Hook 前，恢复功能不会运行。

### 方式二：让 Codex 安装

把这段话发给 Codex：

```text
请帮助我为当前工作区安装 Better Compact：https://github.com/Squ145L/Better-Compact/。先检查安装包、现有安装和 hooks.json；确认工作区归属后安装。若发现不明安装目录，先停下说明。完成后提醒我到“设置 → 钩子”审阅并批准 Hook。
```

## 它怎么工作

```mermaid
flowchart LR
    A[成功编辑] --> B[记一张恢复卡]
    B --> C[compact 或 resume]
    C --> D[补回 TASK_STATE 和恢复卡]
```

| 时机 | 做什么 |
| --- | --- |
| 成功 `apply_patch` 后 | 记住当前项目、最近编辑的文件和时间。 |
| compact 前 | 给该项目的恢复卡标记时间。 |
| compact 或 resume 后 | 补回 TASK_STATE 提示、项目任务状态和恢复卡。 |

恢复时会补入 TASK_STATE 维护提示；找到活动项目后，分别补入存在的项目 `TASK_STATE.md` 和 Recovery Card。Better Compact 不注入任何 `AGENTS.md`。

不会在每次工具调用前重复塞上下文；不会注入 README，也不会在普通启动时注入。

## 平时只改这一个文件

每个 workspace 有自己独立的开关：

```text
<workspace>\.agents\skills\better-compact\config\workspace.json
```

默认内容：

```json
{
  "schemaVersion": 1,
  "coreEnabled": true,
  "taskStateEnabled": true
}
```

| 你想做什么 | 改成什么 | 会发生什么 |
| --- | --- | --- |
| 正常使用 | 两个都是 `true` | 记录恢复卡；恢复时补回 TASK_STATE 提示、项目任务状态和恢复卡。 |
| 暂停 Better Compact | `"coreEnabled": false` | 三个 Hook 都直接跳过：不注入、不写卡、不写日志。TASK_STATE 的值保留。 |
| 不补 TASK_STATE | `"taskStateEnabled": false` | 恢复时只补回恢复卡，跳过 TASK_STATE 提示与项目 `TASK_STATE.md`。 |

保存后下一次 Hook 事件就会生效，不必重装。只能写小写的 `true` / `false`，不要加引号。配置文件丢失或损坏时，两个开关都会按 ON 处理，避免意外停用。

## 你真正会看的文件

工作区运行文件位于：

```text
<workspace>\.agents\skills\better-compact\
```

| 文件或目录 | 什么时候看 |
| --- | --- |
| `config\workspace.json` | 想开、关 Core 或 TASK_STATE 时。 |
| `prompts\task-state.md` | 想看注入给 Codex 的 TASK_STATE 提示原文时。 |
| `recovery\` | 想确认是否已记住活动项目和 Recovery Card 时。 |
| `logs\` | 功能看起来没生效时。 |

项目任务状态位于项目根目录的 `TASK_STATE.md`。全局 Skill 在选定唯一项目后创建或读取它，并在关键状态变化时精简重写；Hook 只读取，不改写该文件。

### 这些名词是什么意思

- **Recovery Card**：一张小卡，只记最近成功编辑的文件和关键时间。
- **上下文注入**：恢复时把必要文本补给 Codex，不是找回完整聊天。
- **Core**：总开关。
- **TASK_STATE**：是否补入 TASK_STATE 提示和项目 `TASK_STATE.md`。

## Skill 是做什么的

全局 Skill 负责定位项目、初始化工作区，并创建或读取、精简重写当前项目的 `TASK_STATE.md`。日常开关请直接改 `workspace.json`。

它不是原生命令。Codex 目前不能把自定义 Skill 变成“无需 LLM、直接执行 PowerShell 并在输入框返回结果”的原生斜杠命令；原生 `/status` 只显示 Codex 自己的状态。[Codex Slash commands 文档](https://learn.chatgpt.com/docs/reference/slash-commands?translationFallback=pt-BR)

## 出问题时怎么查

按这个顺序：

1. 打开 `config\workspace.json`，确认 `coreEnabled` 是 `true`。
2. 到 Codex **设置 → 钩子**，确认三个 Better Compact Hook 都已批准。
3. 确认发生过一次成功的 `apply_patch`；没有成功编辑就没有 Recovery Card。
4. 看 `logs\continuity-diagnostic.jsonl`：它会写明已运行、正常跳过或失败。

想实时看日志：

```powershell
& "D:\my-workspace\.agents\skills\better-compact\runtime\Watch-ContinuityDiagnostics.ps1" -Tail 10
```

- 没有任何日志：通常是 Hook 没批准，或 Core 已关闭。
- compact 后没补回项目内容：看 `recovery\` 是否有该项目的卡；没有就先进行一次成功编辑。
- 想让 Codex 排查：直接发“请只读检查当前 workspace 的 Better Compact，检查 config、recovery、logs 和 Hook 授权；先解释原因，不要修改任何文件。”

## 卸载

双击发行包根目录的 `Uninstall.cmd`，会移除当前用户已登记的所有 Better Compact Hook，并删除元数据核验通过的对应工作区运行目录。全局 Skill 和项目的 `TASK_STATE.md` 会保留。

如果只卸载一个仍可访问的工作区，可运行：

```powershell
& "D:\my-workspace\.agents\skills\better-compact\runtime\Uninstall.ps1"
```

这个脚本会备份 `hooks.json`，只移除指向该工作区的 Better Compact Hook 和运行目录。迁移后旧路径无法使用时，运行发行包根目录的 `Uninstall.cmd`。

## 完整文件参考

```text
<发行包>\
├─ Install.cmd                        # 安装入口
└─ Uninstall.cmd                      # 迁移后也可使用的卸载入口

C:\Users\<你>\.agents\skills\better-compact\
├─ SKILL.md                           # 全局 Skill
└─ package\                           # 为工作区安装提供运行包

<workspace>\
├─ <project>\TASK_STATE.md            # 当前项目状态
└─ .agents\skills\better-compact\
   ├─ config\workspace.json          # 两个开关
   ├─ prompts\task-state.md          # TASK_STATE 提示原文
   ├─ recovery\                      # 活动项目与 Recovery Card
   ├─ logs\                          # 运行与恢复日志
   ├─ runtime\                        # 三个 Hook 的脚本及诊断工具
   └─ install\install.json           # 安装归属元数据
```

Better Compact 目前只支持 Windows。它不提供 Linux、GUI、多 profile、全局开关、原生自定义斜杠命令、完整会话保存、用户 Prompt 保存或原始 patch 保存。`TASK_STATE.md` 的语义维护由 Skill 完成，Hook 不会自动改写它。

## 开发者建议

工作区根目录的 `AGENTS.md` 不要塞入大段规范正文。保留少量不能违反的规则，再链接到详细规范；项目自己的规则放到项目根目录的 `AGENTS.md`。
例如：

```markdown
禁止状态机直接操作底层代码，禁止反向 import。修改前先阅读：
- [前端规范](docs/前端规范.md)
- [后端规范](docs/后端规范.md)
```

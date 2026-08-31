# Better Compact: Context Continuity for Codex (Windows)
# 更好的 Compact： Codex连续上下文优化

减少 Codex 在 compact 后的上下文丢失，遗忘规范、任务进度。

## 30 秒开始

Better Compact 在 Codex 压缩上下文或恢复会话后，自动补回必要的规则、任务状态和最近编辑记录。它不保存完整聊天，不记录密码、令牌或原始 patch。

### 方式一：手动安装

在工作区根目录运行，把路径改成你要使用的 workspace：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows\Install.ps1 -WorkspaceRoot "D:\my-workspace"
```

安装完成后必须打开 Codex 的 **设置 → 钩子**，审阅并批准三个 Better Compact Hook。未批准时，脚本已安装但不会工作。

### 方式二：让 Codex 安装

把这段话发给 Codex：

```text
请帮助我在当前工作目录安装 Better Compact。先只读检查安装包中的 windows\Install.ps1 和现有 hooks.json，说明目标 workspace、将创建的目录、将注册的三个 Hook、备份位置及旧版残留。不要安装、修改 hooks.json 或删除文件，直到我明确确认。完成后提醒我到“设置 → 钩子”审阅并批准 Hook。
```

## 它怎么工作

```mermaid
flowchart LR
    A[成功编辑] --> B[记一张恢复卡]
    B --> C[compact 或 resume]
    C --> D[补回必要上下文]
```

| 时机 | 做什么 |
| --- | --- |
| 成功 `apply_patch` 后 | 记住当前项目、最近编辑的文件和时间。 |
| compact 前 | 给该项目的恢复卡标记时间。 |
| compact 或 resume 后 | 补回规则、任务状态和恢复卡。 |

恢复时依次补回：工作区 `AGENTS.md` → 项目 `AGENTS.md`（有才补）→ TASK_STATE 提示和项目 `TASK_STATE.md`（开关开启且存在时）→ Recovery Card。

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
| 正常使用 | 两个都是 `true` | 记录恢复卡；恢复时补回规则、任务状态和恢复卡。 |
| 暂停 Better Compact | `"coreEnabled": false` | 三个 Hook 都直接跳过：不注入、不写卡、不写日志。TASK_STATE 的值保留。 |
| 不补 TASK_STATE | `"taskStateEnabled": false` | 仍补 `AGENTS.md` 和恢复卡，只跳过 TASK_STATE 提示与项目 `TASK_STATE.md`。 |

保存后下一次 Hook 事件就会生效，不必重装。只能写小写的 `true` / `false`，不要加引号。配置文件丢失或损坏时，两个开关都会按 ON 处理，避免意外停用。

## 你真正会看的文件

所有 Better Compact 自己的文件都在当前 workspace：

```text
<workspace>\.agents\skills\better-compact\
```

| 文件或目录 | 什么时候看 |
| --- | --- |
| `config\workspace.json` | 想开、关 Core 或 TASK_STATE 时。 |
| `prompts\task-state.md` | 想看注入给 Codex 的 TASK_STATE 提示原文时。 |
| `recovery\` | 想确认是否已记住活动项目和 Recovery Card 时。 |
| `logs\` | 功能看起来没生效时。 |

项目自己的任务状态在项目根目录 `TASK_STATE.md`。Better Compact 不会自动创建、删除或改写它。

### 这些名词是什么意思

- **Recovery Card**：一张小卡，只记最近成功编辑的文件和关键时间。
- **上下文注入**：恢复时把必要文本补给 Codex，不是找回完整聊天。
- **Core**：总开关。
- **TASK_STATE**：是否补入 TASK_STATE 提示和项目 `TASK_STATE.md`。

## Skill 是做什么的

Skill 只让 Codex 按正确边界协助**安装、更新、卸载或排障**。日常开关请直接改 `workspace.json`。

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

```powershell
& "D:\my-workspace\.agents\skills\better-compact\runtime\Uninstall.ps1"
```

它会备份 `hooks.json`，只移除指向这个 workspace 的三个 Better Compact Hook，并删除这个 workspace 的 `.agents\skills\better-compact\`。它不会删其他 Hook、其他 workspace 或项目的 `TASK_STATE.md`。

如果卸载失败，先复制 `C:\Users\<你>\.codex\hooks.json`，再只删除命令路径含下面文件的三个处理器；不要碰其他 Hook：

```text
<workspace>\.agents\skills\better-compact\runtime\continuity.ps1
```

然后重开 Codex，到 **设置 → 钩子** 检查。

## 完整文件参考

```text
<workspace>\
├─ AGENTS.md                         # 工作区的总规则
├─ <project>\
│  ├─ AGENTS.md                       # 项目规则（存在时）
│  └─ TASK_STATE.md                   # 项目任务状态（存在时）
└─ .agents\skills\better-compact\
   ├─ SKILL.md                        # 安装与排障说明
   ├─ config\workspace.json          # 两个开关
   ├─ prompts\task-state.md          # TASK_STATE 提示原文
   ├─ recovery\                      # 活动项目与 Recovery Card
   ├─ logs\                          # 运行与恢复日志
   ├─ runtime\continuity.ps1         # 三个 Hook 实际执行的脚本
   ├─ runtime\Control.ps1            # 安装或排障时的内部诊断脚本
   ├─ runtime\Watch-ContinuityDiagnostics.ps1
   ├─ runtime\Uninstall.ps1
   └─ install\install.json           # 安装归属元数据
```

Better Compact 目前只支持 Windows。它不提供 Linux、GUI、多 profile、全局开关、原生自定义斜杠命令、完整会话保存、用户 Prompt 保存、原始 patch 保存、自动任务分类或自动改写 `TASK_STATE.md`。

## 开发者建议

工作区根目录的 `AGENTS.md` 不要塞入大段规范正文。保留少量不能违反的规则，再链接到详细规范；项目自己的规则放到项目根目录的 `AGENTS.md`。

```markdown
禁止状态机直接操作底层代码，禁止反向 import。修改前先阅读：

- [前端规范](docs/前端规范.md)
- [后端规范](docs/后端规范.md)
```

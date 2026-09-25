# Better Compact README 重构设计

## 目标

将 README 改为一份面向最终用户的开箱即用文档：用户能理解 Better Compact 解决什么问题、何时补回上下文、如何安装/批准/使用/排查/卸载，也能选择把安装和维护交给 Codex。

README 不作为 Codex 的运行指令来源，也不被 Better Compact 注入恢复上下文。运行行为仍分别由 `AGENTS.md`、`SKILL.md`、`prompts\task-state.md` 和 PowerShell 脚本定义。

## 读者与写法

- 主读者是首次安装或日常使用 Better Compact 的用户。
- 文本使用中文和人话；可直接使用通用的 Hook 术语，同时解释 Better Compact 自己定义的 Recovery Card、上下文注入、Core/TASK_STATE 和 Skill。
- 面向 Codex 的协助内容集中在单独章节，以用户可复制的提示词形式出现。
- 精确 matcher、PowerShell 函数、完整 Hook JSON、设计历史与测试实现不进入 README；必要时链接 `docs\实施计划.md`。

## README 信息架构

```text
# Better Compact
## 它解决什么问题
## 它会在什么时候做什么
## 极简流程图
## 两种安装方式
### 手动 PowerShell
### 交给 Codex 安装
## 安装后有哪些文件
## Skill 与日常开关
## 维护与详细排查
## 卸载与高级恢复 hooks.json
## 给 Codex 的可复制提示词
## 范围与明确不做什么
```

前半按用户任务流组织：理解、安装、批准、使用。后半提供文件可见性、排查、卸载和 Codex 协助。所有更改 `hooks.json` 的流程均先说明影响并取得用户确认；安装后始终引导用户到 Codex 的“设置 → 钩子”审阅并批准新 Hook。

## 原理说明

README 使用以下准确但简短的解释：

- 成功 `apply_patch` 后，工具记录当前一级项目、最近成功编辑的文件和时间。
- compact 前，工具为该项目 Recovery Card 记录 compact 时间。
- 在 compact 或 resume 的恢复边界，工具依次补回工作区/项目 `AGENTS.md`、TASK_STATE 管理提示、项目 `TASK_STATE.md` 和 Recovery Card。
- 它不会判断聊天“是否丢了上下文”，不会保存完整聊天、用户消息、原始 patch 或自动任务总结，也不会在每次工具调用前重复注入。

README 使用一个四步 Mermaid 流程图：`成功编辑 → 记录 → compact/resume → 补回上下文`，不画内部脚本或 JSON 细节。

## 安装与批准

### 手动 PowerShell

提供从发布仓库根目录运行 `windows\Install.ps1 -WorkspaceRoot "<workspace>"` 的最短命令，说明其会复制 workspace-local 目录、合并三个 Hook 并为已有 `hooks.json` 创建备份。随后明确要求用户在“设置 → 钩子”批准新 Hook。

### 交给 Codex 安装

提供可复制提示词，要求 Codex：

1. 检查当前目录与安装包；
2. 说明目标 workspace、将创建的本地目录、将变更的三个 Hook 与备份位置；
3. 等待用户明确确认；
4. 执行安装；
5. 引导用户到“设置 → 钩子”审阅并批准，不得声称绕过或自动完成批准。

## 文件说明

文件结构按“安装时复制”和“运行时生成”分组。每个关键文件带一到两行短示例或用途：

- `SKILL.md`：Slash 命令入口。
- `runtime\`：Hook、控制器、诊断与卸载脚本。
- `config\workspace.json`：Core/TASK_STATE 开关，展示双 ON 示例。
- `prompts\task-state.md`：用户可直接翻阅的 TASK_STATE 管理提示。
- `recovery\<project>.json`：项目名、最近文件与 compact 时间，展示最短 JSON 示例。
- `logs\`：诊断与审计日志。
- `install\install.json`：安装归属元数据。

同时指出 `.agents\skills\better-compact\` 含机器/工作区本地状态，是否加入 `.gitignore` 由用户决定；工具不会自动改写 `.gitignore`。

## 使用与排查

README 列出全部五个 `/better-compact` 命令，并说明 Core OFF 与 TASK_STATE OFF 的差异。

排查采用“现象 → 首先检查 → 进一步检查”表格，覆盖：

- 功能未生效：`status` 与“设置 → 钩子”批准状态；
- compact 后未补回：Core/TASK_STATE 开关与 Recovery Card；
- 未生成 Recovery Card：成功 `apply_patch` 与诊断日志；
- 想看 TASK_STATE 提示：打开 `prompts\task-state.md`；
- 升级或卸载异常：先保留 `hooks.json` 备份。

“高级恢复 hooks.json”明确为最后手段：先备份当前文件，只删除命令路径指向当前 workspace `better-compact\runtime\continuity.ps1` 的三个处理器，保留其他 Hook，再到“设置 → 钩子”重新审阅。

## Codex 协助提示词

README 包含三个可复制提示词：安装、只读排查、卸载。它们都要求 Codex 先解释影响、对 Hook 或删除操作等待明确确认、完成后引导用户到“设置 → 钩子”。

## 验收

- 普通用户能从顶部完成安装和 Hook 批准，无需阅读实现文档。
- 用户能定位 TASK_STATE 管理提示、配置、Recovery Card 和日志。
- 用户可选手动 PowerShell 或 Codex 协助，两条路线的安全确认一致。
- README 准确描述仅三 Hook、只在 compact/resume 注入、无 PreToolUse/README 注入。
- 用户能按症状完成排查、卸载或高级恢复，而不误删其他 Hook。

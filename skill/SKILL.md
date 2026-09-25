---
name: better-compact
description: Keep a concise TASK_STATE.md for durable project work. Use for multi-file or multi-stage tasks, ongoing debugging, compact, recovery, or handoff; skip one-off questions and simple tasks.
---

# Better Compact

1. **选项目。** 工作区就是当前工作目录，不向上寻找。优先使用用户明确指定的一级项目；否则使用当前请求唯一指向的一级项目。`.agents`、`.codex`、`docs` 不是项目。无法唯一确定时询问用户；答复前不安装，也不写 `TASK_STATE.md`。
2. **初始化。** 检查工作区的 `.agents\skills\better-compact\` 及其安装元数据。已确认安装则沿用；不存在则运行本 Skill 的 `package\windows\Install.ps1 -WorkspaceRoot <workspace> -ExistingHooksAction Merge`。目录或元数据不明时停止，避免覆盖。初次安装 Hook 需要用户到 Codex **设置 → 钩子** 批准。
3. **维护状态。** 在选定项目根目录创建或先读取 `TASK_STATE.md`，再继续任务。固定五栏：`目标`、`已确认边界`、`已排除项`、`当前状态`、`下一步`。只在目标、边界、关键结论、下一步或交接状态变化时，按已核实的当前事实重写相关内容：合并同类项，删掉过期或已不影响后续工作的记录，不在末尾追加历史。保持精简；代码和测试事实优先；不写密钥或隐私。
4. **继续工作。** 初始化后简短说明实际结果；若新 Hook 待批准，一并提醒。随后继续用户任务。不要为不适用本 Skill 的任务创建或维护状态。

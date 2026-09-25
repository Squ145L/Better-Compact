# Better Compact 恢复卡路径修复

## 目标

修复 Windows Hook 在 `apply_patch` 返回绝对路径时无法识别 workspace 项目的问题，使下一次 compact 能读取对应 Recovery Card。

## 范围与边界

- 只修改发布源 `E:\Claudeproject\codex\Better Compact`。
- 不修改已安装的 `E:\Claudeproject\codex\.agents\skills\better-compact`、用户级 `hooks.json` 或现有恢复数据。
- 保持现有三 Hook、配置开关、恢复卡字段和注入顺序不变。
- 不自动创建或更新项目的 `TASK_STATE.md`。

## 根因

`Get-ProjectNameForPath` 总是把传入路径与 workspace 拼接。对于 `E:\...\egg-party-secret-lobby\...` 这类绝对路径，Windows 会得到一个无效的重复路径，项目判断失败。因此 `PostToolUse` 跳过记录、活动项目为空，后续 `PreCompact` 和 `SessionStart` 找不到恢复卡。

## 设计

### 路径归一化

新增一个只负责解析 patch 目标路径的内部函数：

1. 空路径直接忽略。
2. 绝对路径直接规范化；相对路径才以 workspace 为基准拼接。
3. 仅当规范化后的路径处于 workspace 内时继续处理。
4. 继续沿用一级子目录即项目、忽略 `.agents`、`.codex` 与 `docs` 的既有规则。

这会同时支持 Codex 传入的相对路径与绝对路径，不改变恢复卡保存的原始相对/绝对文件名格式。

### Hook 输入兼容

保留当前标准 JSON 读取逻辑，并在解析失败时把诊断内容限制为错误类型与输入长度，不把完整 Hook payload（其中可能含 patch 内容）写入日志。不会尝试从损坏 JSON 中猜测或执行内容。

### 测试

在隔离测试中新增：

- 成功 `apply_patch` 的绝对项目路径会建立 Recovery Card、登记活动项目，并能在 compact 后注入该卡。
- 相对路径保留既有行为。
- workspace 外的绝对路径不建立卡。
- 无效 JSON 仅产生受限诊断，不写入原始 payload。

## 验收

发布源的隔离测试通过；审阅源码与测试改动后，由用户明确确认才运行安装器更新当前 workspace，并完成一次真实的“成功 apply_patch → compact → Recovery Card 注入”验证。

# Better Compact Skill 自动初始化与 TASK_STATE 维护

## 目标

让 Better Compact 从“仅在用户要求安装或排障时才有用的说明文件”，变成一个可由 Codex 在合适任务中自动选择的用户级全局工作流：它先定位唯一项目，再无确认地初始化该 workspace 的运行文件，并在项目根目录创建或静默维护 `TASK_STATE.md`。

本设计只改变 Skill、TASK_STATE 管理提示、文档与文本验证；不改变 Recovery Hook 的生命周期和语义职责。

## 已确认用户决策

- 当 agent 判断任务是长期、多阶段、跨文件、持续排障、设计到实现、可能 compact 或需要交接时，自动选择 Better Compact Skill；无需用户显式输入 `$better-compact`。
- 使用 Better Compact 后不要求用户确认安装、初始化或创建 TASK_STATE；完成后用极短一句说明实际动作。
- 只有项目根无法唯一确定时才提问。工作区根的一级子目录是项目候选；不根据最近文件、惯例或猜测选择。
- 选定项目后，若项目根没有 `TASK_STATE.md`，直接创建；已有文件则静默读取并在关键状态变化时合并维护。
- 不在每次文件修改时更新 TASK_STATE，不把它当聊天日志，也不保存密钥、令牌、密码或隐私信息。
- Better Compact Hook 继续只记录可验证工程事实；不自动生成或改写 TASK_STATE 的语义内容。

## 触发与不触发

Skill 的 metadata `description` 应明确支持自动选择，并列出两个边界。

应选择：用户显式提到 Better Compact、连续上下文、compact、恢复、交接、TASK_STATE；或当前任务明显属于已确认的长期类别。

不应选择：纯问答、翻译、一次性命令、只读定位单个事实、简单单文件且可在本轮结束的动作，或用户明确要求不创建/不维护状态。

Skill 被选择后，先完成项目定位与状态检查，再开始用户请求的实质工作。它不应在每次普通对话中宣告自己存在。

## 项目定位

Skill 把 workspace 视为 Codex 当前工作目录，不向上寻找其他 workspace。项目根按以下顺序唯一确定：

1. 用户明确给出的项目目录，或用户明确文件路径所属的一级项目目录。
2. 当前 cwd 本身是 workspace 的一级项目目录。
3. 当前对话、当前请求或已验证的恢复上下文唯一指向一个一级项目目录。
4. 若以上都不能唯一确定，列出 workspace 下一级子目录并询问用户选择；在得到答案前不安装、不创建、不修改 TASK_STATE。

`.agents`、`.codex`、`docs` 和 workspace 根不是项目候选。已经由文件路径确定项目时，绝不再提问。

## 初始化流程

项目唯一后，Skill 按以下顺序执行：

1. 只读检查 `<workspace>\.agents\skills\better-compact\`、`config\workspace.json`、安装元数据、Recovery 数据和项目 `TASK_STATE.md`。
2. 若 Better Compact 未安装或是本工作区可确认的旧安装，直接从用户级全局 Skill 自带的包以当前 workspace 执行安装/升级；有现有 `hooks.json` 时使用安装器的 Merge 路径，不再额外询问。未知或损坏的安装目录仍停止并报告，避免覆盖未知数据。
3. 若 Hook 尚未获信任，不能伪称已启用；极短说明中提醒用户到 Codex“设置 → 钩子”审阅并批准。
4. 在项目根创建缺失的 `TASK_STATE.md`，或读取既有文件进入静默维护。
5. 用一条简短消息报告实际结果，例如：`Better Compact：已为 骰子爬塔设计 初始化；TASK_STATE 已创建并开始静默维护。` 安装了 Hook 时再追加批准提醒。

已经安装且配置可用时，不重装、不重写 Hook 注册、不创建重复状态文件。

## TASK_STATE 提示与维护

`prompts\task-state.md` 必须先声明：它只在 Better Compact 已为当前任务选定唯一项目后生效，不能仅凭该提示被注入就创建状态文件。

文件固定位置为 `<project-root>\TASK_STATE.md`，结构为：

```md
# TASK_STATE

## 目标
## 已确认边界
## 已排除项
## 当前状态
## 下一步
```

agent 在关键状态变化时静默合并维护：目标或范围改变、用户确认/排除重要决策、阶段完成、验证结果改变结论、下一步改变、暂停或准备交接。恢复后先读它；若与代码、测试或文件事实冲突，以可验证事实为准并修正状态。

## Recovery Card 的边界

Recovery Card 继续按照成功 `apply_patch` 的目标文件路径归属一级项目：`<workspace>\骰子爬塔设计\...` 写入 `recovery\骰子爬塔设计.json`。它保存最近文件和时间等事实，不能决定任务语义或选择 TASK_STATE。

恢复时 active project 由 cwd 映射取回；一次 patch 涉及多个项目时不作为 TASK_STATE 的项目选择依据。Skill 仍使用“项目定位”规则，不能把 Recovery Card 的最近活动项目当成唯一事实。

## 文件改动范围

| 文件 | 职责 |
| --- | --- |
| `skill\SKILL.md` | 用户级全局 Skill 的源，定义自动选择、项目定位、无确认初始化、静默维护与短报告。 |
| `C:\Users\<你>\.agents\skills\better-compact\SKILL.md` | 安装后的唯一全局 Skill；自带运行包，可为其他 workspace 安装运行文件。 |
| `prompts\task-state.md` | 限定提示生效前提、项目根位置和静默维护规则。 |
| `.agents\skills\better-compact\prompts\task-state.md` | 与发布源同步。 |
| `README.md` | 提供开箱即用的安装、日常使用与开关入口。 |
| `docs\advanced.md` | 保留安装、升级、排查、卸载和目录细节。 |
| `TASK_STATE.md` | 更新该发行包当前状态与下一步。 |
| `windows\Test-ContinuityHooks.ps1` | 增加发布源/安装副本同步与新版文本边界的检查；不把 agent 的语义判断伪装成 Hook 单元测试。 |

不改 `hooks.json`、Hook event、`continuity.ps1`、Recovery Card 格式或已有项目 TASK_STATE 文件。

## 验收

- 新版 Skill 明确允许 agent 在符合条件的任务中自动选择，且明确列出不触发情形。
- 项目无法唯一确定时只询问一级项目目录，未发生安装或 TASK_STATE 写入。
- 项目唯一时，缺失 TASK_STATE 自动在项目根创建；已有文件不会被覆盖而是静默合并维护。
- 安装/升级过程无额外确认轮次，未知/损坏安装目录仍不覆盖；Hook 信任仍明确由用户完成。
- TASK_STATE prompt 不再因单纯恢复注入而命令 agent 无条件创建文件。
- Recovery Card 仍只按 `apply_patch` 文件路径记录工程事实。
- 发布源与用户级全局 Skill/运行包哈希一致；现有隔离 Hook 测试继续通过。

## 非目标

- 自动总结完整聊天、自动保存原始 patch、自动创建记忆、自动选择不唯一项目、每次编辑重写 TASK_STATE、Hook 写入任务语义、绕过 Hook 信任、修改其他 workspace 或删除既有 TASK_STATE。

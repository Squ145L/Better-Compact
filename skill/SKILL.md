---
name: better-compact
description: Guide Better Compact installation, updates, uninstallation, or troubleshooting in the current workspace; do not use for daily switch commands.
---

# Better Compact

Use this skill only when the user asks to install, update, uninstall, diagnose, or repair Better Compact.

Better Compact does not provide a native Codex slash command that can run PowerShell without an LLM. Do not present this Skill as an `on/off/status/task-state` command interface.

The workspace is the current working directory exactly. Do not search upward for another workspace.

For everyday Core or TASK_STATE changes, direct the user to edit `<current working directory>\.agents\skills\better-compact\config\workspace.json` manually. Explain the requested value without changing it unless the user separately asks Codex to edit that file.

For installation, update, or uninstallation, first do read-only checks and explain the target workspace, relevant local files, Hook changes, and any `hooks.json` backup. Wait for explicit confirmation before running an installer, uninstaller, changing Hook registrations, or deleting files. Always direct the user to Codex **设置 → 钩子** to review and approve new Hooks; never claim to bypass or automatically complete that approval.

For troubleshooting, inspect the workspace-local installation metadata, `workspace.json`, recovery data and logs first. Use `runtime\Control.ps1` only as an internal diagnostic helper when it is useful. Explain the evidence and proposed repair before making any change.

GITHUB:  https://github.com/Squ145L/Better-Compact/
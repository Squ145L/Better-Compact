# Continuity Hooks Distribution State

## Goal

Package the verified Windows continuity hooks for sharing through a Git Release, with an explicit merge-or-cancel install flow.

## Confirmed boundary

- Windows is phase one; Linux is a later, separate implementation.
- The installer must prompt before modifying an existing user hooks.json and only merge after consent.
- Release artifacts must exclude existing user state, logs, recovery cards, absolute user paths, and credentials.
- The package must support any first-level child directory in a chosen workspace as a project.

## Current status

- Windows scripts, README, watcher and uninstall flow are complete.
- README now separates the human-facing purpose/impact explanation from instructions written for Codex.
- The shared hook uses `SHA256.Create().ComputeHash`, compatible with built-in Windows PowerShell 5.1.
- Isolated tests passed: edit tracking, failed-edit exclusion, compact injection, shared-doc exclusion, clean install, merge deduplication, cancellation preservation and uninstall.

## Next step

Initialize/publish this folder as the Git repository and create a Windows Git Release when requested. Linux remains intentionally excluded.

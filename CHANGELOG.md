# Changelog

## 0.1.0 (2026-11-06)

- `UserPromptSubmit` hook injects TLDR rules every prompt via `additionalContext`.
- Config in `~/.claude/tldr.json` with per-key project override: `when`, `long_lines`, `position`, `body`, `short_lines`, `include`, `max_bullets`, `strict`.
- Optional strict `Stop` hook with `stop_hook_active` guard.
- `/tldr:tldr` skill: `on`, `off`, `top`, `bottom`, `short`, `full`, `strict on`, `strict off`, `status`, `reset`.
- `tests/run.sh` covering hooks, config merge, malformed and hostile config, missing jq, and the toggle command.

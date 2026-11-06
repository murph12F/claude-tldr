---
name: tldr
description: Toggle or inspect the tldr plugin's reply summary settings (on, off, top, bottom, short, full, strict on, strict off, status, reset).
argument-hint: "on|off|top|bottom|short|full|strict on|strict off|status|reset"
disable-model-invocation: true
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/tldr-config.sh *)
---

Arguments: `$ARGUMENTS`

Allowed arguments are exactly one of: `on`, `off`, `top`, `bottom`, `short`, `full`, `strict on`, `strict off`, `status`, `reset`, or nothing.

1. If the arguments are not one of those (case-insensitive), use `status` instead. Never pass anything else.
2. Run this single Bash command, with the argument words appended as plain separate words and nothing else on the line:

   `${CLAUDE_PLUGIN_ROOT}/scripts/tldr-config.sh <argument words>`

3. Reply with only the command's output line. No TLDR, no commentary.

#!/usr/bin/env bash
# UserPromptSubmit hook: inject the current TLDR rules as additionalContext.
# Runs every turn, so /tldr toggles apply on the next prompt and the rules
# come back after compaction. Must never break the session: always exit 0.

src=${BASH_SOURCE[0]}
case "$src" in */*) here=${src%/*} ;; *) here=. ;; esac
# shellcheck source=lib.sh
. "$here/lib.sh" || exit 0

if ! tldr_have_jq; then
  echo "tldr plugin: jq not found on PATH; TLDR rules not injected. Install jq (brew install jq / apt install jq)." >&2
  exit 0
fi

input=$(cat 2>/dev/null) || input=''
proj=$(tldr_project_dir "$input")
cfg=$(tldr_config "$proj" 2>/dev/null) || exit 0

jq -nc --argjson c "$cfg" '
  $c as $c
  | if $c.when == "off" then empty else
    {
      outcome:   "outcome first (concrete numbers/decisions, not process)",
      needs_you: "`Needs you:` (always; `nothing` if nothing)",
      running:   "`Running:` what is still in progress (omit if none)",
      risks:     "`Risks:` real risks only (omit if none)"
    } as $item
    | ([$c.include[] | $item[.]] | join("; ")) as $items
    | (if $c.position == "top" then "start it with" else "end it with" end) as $where
    | (if $c.when == "always"
         then "Always \($where)"
         else "If the reply exceeds \($c.long_lines) lines, \($where)" end) as $trigger
    | [
        "[tldr rules, newest wins]",
        (if $c.body == "short"
           then "Keep the whole reply to at most \($c.short_lines) lines (code, commands, security/data-loss warnings exempt)."
           else empty end),
        "\($trigger) a `TLDR:` line and at most \($c.max_bullets) bullets: \($items).",
        (if $c.position == "top" then "Then a blank line, then the answer." else empty end),
        (if $c.when == "long" then "Shorter replies: no TLDR." else empty end),
        "Never restate the question or recap \"I did X\". Never truncate code, commands, or security/data-loss warnings. No em dash character."
      ]
    | join(" ")
    | {hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: .}}
    end
' 2>/dev/null

exit 0

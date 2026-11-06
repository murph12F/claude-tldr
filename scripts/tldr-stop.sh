#!/usr/bin/env bash
# Stop hook (strict mode only): if the final reply is long and has no TLDR
# block, block the stop once and ask Claude to append it.
# Loop guard: stop_hook_active is true when Claude is already continuing
# because of a stop hook, so we never block twice in a row.

src=${BASH_SOURCE[0]}
case "$src" in */*) here=${src%/*} ;; *) here=. ;; esac
# shellcheck source=lib.sh
. "$here/lib.sh" || exit 0

if ! tldr_have_jq; then
  echo "tldr plugin: jq not found on PATH; strict check skipped. Install jq (brew install jq / apt install jq)." >&2
  exit 0
fi

input=$(cat 2>/dev/null) || input=''
proj=$(tldr_project_dir "$input")
cfg=$(tldr_config "$proj" 2>/dev/null) || exit 0

printf '%s' "$input" | jq -c --argjson c "$cfg" '
  if ($c.strict != true) or ($c.when == "off") then empty
  elif .stop_hook_active == true then empty
  else
    (.last_assistant_message // "") as $m
    | if ($m | type) != "string" then empty else
      ([$m | split("\n")[] | select(test("\\S"))] | length) as $n
      | ($m | test("(^|\\n)[ \\t>*_#-]*TLDR\\b")) as $tagged
      | if ($n > 0) and ($tagged | not)
           and (($c.when == "always") or ($n > $c.long_lines))
        then {
          decision: "block",
          reason: "tldr strict: your reply has \($n) lines and no TLDR block. Append only the TLDR block now (a `TLDR:` line plus bullets, per the tldr rules). Do not repeat the answer."
        }
        else empty end
      end
  end
' 2>/dev/null

exit 0

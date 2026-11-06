#!/usr/bin/env bash
# /tldr command backend. Edits ~/.claude/tldr.json atomically and prints the
# resulting effective config on one line.
#
# Usage: tldr-config.sh on|off|top|bottom|short|full|strict on|strict off|status|reset

usage='usage: /tldr on|off|top|bottom|short|full|strict on|strict off|status|reset'

src=${BASH_SOURCE[0]}
case "$src" in */*) here=${src%/*} ;; *) here=. ;; esac
# shellcheck source=lib.sh
. "$here/lib.sh" || exit 1

if ! tldr_have_jq; then
  echo "tldr: jq not found on PATH. Install jq (brew install jq / apt install jq)."
  exit 1
fi

# Normalize arguments: join, lowercase, squeeze whitespace. The result is only
# ever compared against literal patterns below, never executed or eval'd.
cmd=$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')
cmd=${cmd# }
cmd=${cmd% }

# jq filter to apply (fixed strings only).
case "$cmd" in
  ''|status)    edit='' ;;
  on)           edit='if .when == "off" or (has("when") | not) then .when = "long" else . end' ;;
  off)          edit='.when = "off"' ;;
  top)          edit='.position = "top"' ;;
  bottom)       edit='.position = "bottom"' ;;
  short)        edit='.body = "short"' ;;
  full)         edit='.body = "full"' ;;
  'strict on')  edit='.strict = true' ;;
  'strict off') edit='.strict = false' ;;
  reset)        edit='reset' ;;
  *)
    echo "$usage"
    exit 2
    ;;
esac

ucfg=$(tldr_user_config_path)

if [ -n "$edit" ]; then
  udir=$(dirname "$ucfg")
  mkdir -p "$udir" || { echo "tldr: cannot create $udir"; exit 1; }

  if [ "$edit" = reset ]; then
    current='{}'
    edit='.'
  elif [ -f "$ucfg" ]; then
    if ! current=$(jq -ce 'if type == "object" then . else error("not an object") end' "$ucfg" 2>/dev/null); then
      echo "tldr: $ucfg is not a valid JSON object; fix it or run /tldr reset"
      exit 1
    fi
  else
    current='{}'
  fi

  tmp=$(mktemp "$udir/.tldr.json.XXXXXX") || { echo "tldr: cannot create temp file in $udir"; exit 1; }
  if printf '%s' "$current" | jq "$edit" >"$tmp" 2>/dev/null && mv -f "$tmp" "$ucfg"; then
    :
  else
    rm -f "$tmp"
    echo "tldr: failed to write $ucfg"
    exit 1
  fi
fi

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
eff=$(tldr_config "$proj") || { echo "tldr: failed to read config"; exit 1; }
note=''
if [ -f "$proj/.claude/tldr.json" ] && [ "$proj/.claude/tldr.json" != "$ucfg" ]; then
  note=" (project overrides from $proj/.claude/tldr.json)"
fi
printf 'tldr: %s%s\n' "$eff" "$note"

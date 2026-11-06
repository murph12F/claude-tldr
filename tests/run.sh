#!/usr/bin/env bash
# Feeds sample hook JSON to the scripts and asserts on their output.
# Uses a throwaway HOME and project dir; never touches the real ~/.claude.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
S="$root/scripts"
work=$(mktemp -d "${TMPDIR:-/tmp}/tldr-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

export HOME="$work/home"
proj="$work/proj"
mkdir -p "$HOME/.claude" "$proj/.claude"
export CLAUDE_PROJECT_DIR="$proj"

pass=0
fail=0
ok()   { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '     got: %s\n' "$2"; }
reset_cfg() { rm -f "$HOME/.claude/tldr.json" "$proj/.claude/tldr.json"; }

prompt_in() { printf '{"session_id":"t","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"hi"}' "$proj"; }
inject()    { prompt_in | "$S/tldr-inject.sh"; }
ctx()       { inject | jq -r '.hookSpecificOutput.additionalContext'; }

# stop_in <stop_hook_active> <message text>
stop_in() {
  jq -nc --argjson a "$1" --arg m "$2" \
    '{session_id:"t",hook_event_name:"Stop",stop_hook_active:$a,last_assistant_message:$m}'
}
long_msg=$(for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "line $i of a long answer"; done)
long_tagged="$long_msg
TLDR:
- outcome
- Needs you: nothing"
short_msg=$'one\ntwo\nthree'

# 1. defaults
reset_cfg
out=$(inject)
c=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')
ev=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')
if [ "$ev" = UserPromptSubmit ] && [[ "$c" == *"exceeds 8 lines, end it with"* ]] \
   && [[ "$c" == *"at most 3 bullets"* ]] && [[ "$c" == *"Needs you:"* ]] \
   && [[ "$c" == *"Shorter replies: no TLDR."* ]] && [[ "$c" != *"Running:"* ]] \
   && [[ "$c" != *"at most 5 lines"* ]]; then
  ok "defaults inject bottom/long/8/3 bullets/outcome+needs_you"
else bad "defaults" "$out"; fi

words=$(printf '%s' "$c" | wc -w | tr -d ' ')
if [ "$words" -le 80 ]; then ok "default injection is short ($words words)"; else bad "injection length $words words"; fi

if printf '%s' "$c" | grep -q $'\xe2\x80\x94'; then bad "injection contains em dash"; else ok "no em dash in injection"; fi

# 2. project override wins per key
reset_cfg
echo '{"position":"top","max_bullets":2,"long_lines":20}' >"$HOME/.claude/tldr.json"
echo '{"position":"bottom","include":["outcome","needs_you","risks"]}' >"$proj/.claude/tldr.json"
c=$(ctx)
if [[ "$c" == *"exceeds 20 lines, end it with"* ]] && [[ "$c" == *"at most 2 bullets"* ]] \
   && [[ "$c" == *"Risks:"* ]] && [[ "$c" != *"blank line"* ]]; then
  ok "project overrides user per key, user keys kept"
else bad "project override" "$c"; fi

# 2b. cwd fallback when CLAUDE_PROJECT_DIR is unset
c=$(prompt_in | env -u CLAUDE_PROJECT_DIR "$S/tldr-inject.sh" | jq -r '.hookSpecificOutput.additionalContext')
if [[ "$c" == *"Risks:"* ]]; then ok "project dir falls back to input cwd"; else bad "cwd fallback" "$c"; fi

# 3. when=off: no injection
reset_cfg
echo '{"when":"off"}' >"$HOME/.claude/tldr.json"
out=$(inject); rc=$?
if [ $rc -eq 0 ] && [ -z "$out" ]; then ok "when=off injects nothing"; else bad "when=off" "$out"; fi

# 4. short mode
reset_cfg
echo '{"body":"short","short_lines":4}' >"$HOME/.claude/tldr.json"
c=$(ctx)
if [[ "$c" == *"at most 4 lines (code, commands, security/data-loss warnings exempt)"* ]] \
   && [[ "$c" == *"Never truncate code"* ]]; then
  ok "short mode caps reply and exempts code/commands/warnings"
else bad "short mode" "$c"; fi

# 4b. top + always
reset_cfg
echo '{"position":"top","when":"always"}' >"$HOME/.claude/tldr.json"
c=$(ctx)
if [[ "$c" == *"Always start it with"* ]] && [[ "$c" == *"blank line"* ]] && [[ "$c" != *"Shorter replies"* ]]; then
  ok "top + always"
else bad "top + always" "$c"; fi

# 5. strict: block on long untagged message
reset_cfg
echo '{"strict":true}' >"$HOME/.claude/tldr.json"
out=$(stop_in false "$long_msg" | "$S/tldr-stop.sh")
if [ "$(printf '%s' "$out" | jq -r '.decision')" = block ] \
   && [ -n "$(printf '%s' "$out" | jq -r '.reason // empty')" ]; then
  ok "strict blocks long untagged reply"
else bad "strict block" "$out"; fi

# 6. no block when stop_hook_active is true
out=$(stop_in true "$long_msg" | "$S/tldr-stop.sh")
if [ -z "$out" ]; then ok "no block when stop_hook_active=true"; else bad "stop_hook_active guard" "$out"; fi

# 7. no block on short message
out=$(stop_in false "$short_msg" | "$S/tldr-stop.sh")
if [ -z "$out" ]; then ok "no block on short reply"; else bad "short reply blocked" "$out"; fi

# 7b. no block when TLDR present
out=$(stop_in false "$long_tagged" | "$S/tldr-stop.sh")
if [ -z "$out" ]; then ok "no block when TLDR marker present"; else bad "tagged reply blocked" "$out"; fi

# 7c. strict off (default): never blocks
reset_cfg
out=$(stop_in false "$long_msg" | "$S/tldr-stop.sh")
if [ -z "$out" ]; then ok "strict=false never blocks"; else bad "non-strict blocked" "$out"; fi

# 8. malformed config falls back to defaults
reset_cfg
printf '{"when": "always", oops' >"$HOME/.claude/tldr.json"
printf '[1,2,3]' >"$proj/.claude/tldr.json"
c=$(ctx)
if [[ "$c" == *"exceeds 8 lines, end it with"* ]]; then ok "malformed JSON falls back to defaults"; else bad "malformed json" "$c"; fi

reset_cfg
echo '{"when":"$(touch PWNED)","long_lines":"8; rm -rf /","max_bullets":99,"include":["outcome","evil"],"position":"`id`","strict":"yes","body":42}' >"$HOME/.claude/tldr.json"
c=$(cd "$work" && ctx)
if [[ "$c" == *"exceeds 8 lines, end it with"* ]] && [[ "$c" == *"at most 3 bullets"* ]] \
   && [[ "$c" != *PWNED* ]] && [[ "$c" != *rm\ -rf* ]] && [[ "$c" != *'`id`'* ]] && [ ! -e "$work/PWNED" ]; then
  ok "invalid values ignored per key, nothing executed or echoed"
else bad "invalid values" "$c"; fi

# 9. missing jq: clear stderr, exit 0, no stdout (both hooks).
# PATH holds the usual tools but no jq.
mkdir -p "$work/nojq"
for t in cat wc tr dirname mktemp mv rm mkdir env grep; do
  p=$(command -v "$t") && ln -s "$p" "$work/nojq/$t"
done
for h in tldr-inject.sh tldr-stop.sh; do
  err="$work/err"
  out=$(prompt_in | PATH="$work/nojq" /bin/bash "$S/$h" 2>"$err"); rc=$?
  if [ $rc -eq 0 ] && [ -z "$out" ] && grep -q 'jq not found' "$err"; then
    ok "missing jq: $h exits 0, no output, clear error"
  else bad "missing jq ($h) rc=$rc" "$out / $(cat "$err")"; fi
done

# 10. /tldr command: atomic writes and one-line status
reset_cfg
cfgsh() { (cd "$proj" && "$S/tldr-config.sh" "$@"); }
o=$(cfgsh off)
if [ "$(jq -r .when "$HOME/.claude/tldr.json")" = off ] && [ "$(printf '%s\n' "$o" | wc -l | tr -d ' ')" = 1 ] \
   && [[ "$o" == 'tldr: {"when":"off"'* ]]; then ok "/tldr off writes config, prints one line"; else bad "/tldr off" "$o"; fi
cfgsh on >/dev/null
cfgsh top >/dev/null
cfgsh short >/dev/null
cfgsh strict on >/dev/null
o=$(cfgsh STRICT   On)   # case and spacing normalized
u=$(jq -c . "$HOME/.claude/tldr.json")
if [ "$u" = '{"when":"long","position":"top","body":"short","strict":true}' ]; then
  ok "/tldr on|top|short|strict on accumulate"
else bad "/tldr accumulate" "$u"; fi
cfgsh strict off >/dev/null; cfgsh bottom >/dev/null; cfgsh full >/dev/null
u=$(jq -c . "$HOME/.claude/tldr.json")
if [ "$u" = '{"when":"long","position":"bottom","body":"full","strict":false}' ]; then
  ok "/tldr strict off|bottom|full"
else bad "/tldr reverse" "$u"; fi
echo '{"when":"always"}' >"$HOME/.claude/tldr.json"; cfgsh on >/dev/null
if [ "$(jq -r .when "$HOME/.claude/tldr.json")" = always ]; then ok "/tldr on keeps when=always"; else bad "/tldr on clobbered always"; fi
o=$(cfgsh reset)
if [ "$(jq -c . "$HOME/.claude/tldr.json")" = '{}' ] && [[ "$o" == *'"when":"long"'* ]]; then ok "/tldr reset"; else bad "/tldr reset" "$o"; fi
o=$(cfgsh 'status; touch PWNED'); rc=$?
if [ $rc -eq 2 ] && [[ "$o" == usage:* ]] && [ ! -e "$proj/PWNED" ]; then ok "/tldr rejects unknown args"; else bad "/tldr unknown" "$o"; fi
printf 'not json' >"$HOME/.claude/tldr.json"
o=$(cfgsh top); rc=$?
if [ $rc -eq 1 ] && [ "$(cat "$HOME/.claude/tldr.json")" = 'not json' ]; then ok "/tldr refuses to clobber malformed user config"; else bad "/tldr malformed" "$o"; fi
leftover=$(find "$HOME/.claude" -name '.tldr.json.*' | wc -l | tr -d ' ')
if [ "$leftover" = 0 ]; then ok "no temp files left behind"; else bad "temp files left: $leftover"; fi
reset_cfg
echo '{"position":"top"}' >"$proj/.claude/tldr.json"
o=$(cfgsh status)
if [[ "$o" == *'"position":"top"'* ]] && [[ "$o" == *"project overrides"* ]]; then ok "/tldr status shows project override"; else bad "/tldr status project" "$o"; fi

# 11. no em dash anywhere in shipped files
if grep -rl $'\xe2\x80\x94' "$root" --exclude-dir=.git >/dev/null 2>&1; then
  bad "em dash found in: $(grep -rl $'\xe2\x80\x94' "$root" --exclude-dir=.git | tr '\n' ' ')"
else ok "no em dash in repo files"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

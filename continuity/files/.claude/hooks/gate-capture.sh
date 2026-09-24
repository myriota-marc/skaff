#!/bin/sh
# PostToolUse AskUserQuestion and UserPromptSubmit: record a human Accept as gate evidence.
# Every payload is logged raw to .claude/.cache/gate-capture-last.json so field names stay verifiable.
. "$CLAUDE_PROJECT_DIR/scripts/lib.sh"
need jq "winget install jqlang.jq, brew install jq or asdf"
in="$(cat)"
mkdir -p "$ROOT/.claude/.cache" "$ROOT/.gates"
printf '%s' "$in" > "$ROOT/.claude/.cache/gate-capture-last.json"

write() { # id answer
  case "$HUMAN" in *@@*) echo "gate-capture: no human id. Set CONTINUITY_HUMAN or HUMAN in scripts/lib.sh; $1 not recorded" >&2; return 0 ;; esac
  jq -n --arg id "$1" --arg by "$HUMAN" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg head "$(git -C "$ROOT" rev-parse HEAD)" --arg answer "$2" \
    '{id:$id, by:$by, at:$at, head:$head, answer:$answer}' > "$ROOT/.gates/$1.json"
  echo "gate-capture: recorded .gates/$1.json" >&2
}

ev="$(printf '%s' "$in" | jq -r '.hook_event_name // empty')"
if [ "$ev" = "UserPromptSubmit" ]; then
  id="$(printf '%s' "$in" | jq -r '.prompt // empty' | sed -nE '1s/^ACCEPT ([A-Za-z0-9_-]+).*/\1/p')"
  [ -n "$id" ] && write "$id" "ACCEPT"
  exit 0
fi

# AskUserQuestion: answers map question text to the chosen label (tool_input.answers).
printf '%s' "$in" | jq -r '
  (.tool_input.answers // .tool_response.answers // {}) as $a
  | .tool_input.questions[]? | select(.header | test("^Gate [A-Za-z0-9_-]+$"))
  | [(.header | sub("^Gate "; "")), ($a[.question] // "")] | @tsv' | tr -d '\r' |
while IFS="$(printf '\t')" read -r id ans; do
  case "$ans" in Accept*) write "$id" "$ans" ;; esac
done
exit 0

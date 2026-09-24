#!/bin/sh
# PreToolUse Write|Edit|MultiEdit: protect ADRs, gate evidence and OKF docs.
. "$CLAUDE_PROJECT_DIR/scripts/lib.sh"
need jq "winget install jqlang.jq, brew install jq or asdf"
in="$(cat)"
tool="$(printf '%s' "$in" | jq -r '.tool_name // empty')"
fp="$(printf '%s' "$in" | jq -r '.tool_input.file_path // empty')"
[ -n "$fp" ] || exit 0
rel="$(relpath "$fp")"

case "$rel" in
  .gates/*) block 2 "guard-write: .gates/ holds evidence. Only scripts/gate.sh and the gate-capture hook write it." ;;
  docs/decisions/[0-9][0-9][0-9][0-9]-*.md)
    if git -C "$ROOT" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
      block 2 "guard-write: $rel is a committed ADR and immutable. Write a new ADR with supersedes: [$(basename "$rel" | cut -c1-4)]."
    fi ;;
esac

if [ "$tool" = "Write" ]; then
  case "$rel" in
    docs/*/index.md|docs/index.md|docs/*/log.md|docs/log.md) ;;
    docs/*.md)
      printf '%s' "$in" | jq -r '.tool_input.content // empty' | awk 'NR==1&&$0!="---"{exit 1} NR>1&&$0=="---"{exit (f?0:1)} NR>1&&/^type:/{f=1}' \
        || block 2 "guard-write: $rel needs OKF front matter with 'type' (see docs/STATE.md for the schema)." ;;
  esac
fi
exit 0

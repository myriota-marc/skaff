#!/bin/sh
# PostToolUse Write|Edit|MultiEdit: Vale plus OKF key check on the touched in-scope Markdown file.
. "$CLAUDE_PROJECT_DIR/scripts/lib.sh"
need jq "winget install jqlang.jq, brew install jq or asdf"
fp="$(jq -r '.tool_input.file_path // empty')"
[ -n "$fp" ] || exit 0
rel="$(relpath "$fp")"
in_scope "$rel" || exit 0
[ -f "$ROOT/$rel" ] || exit 0
cd "$ROOT"
out="$(okf_check "$rel" "$rel")"
need vale "winget install errata-ai.Vale, brew install vale or asdf"
v="$(vale --output=line "$rel" 2>&1)" || out="$out
$v"
[ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ] || block 2 "lint-md: fix $rel:" "$out"
exit 0

#!/bin/sh
# PreToolUse Bash: block commits on main, hook bypass, force push, amend of pushed commits,
# and shell writes to .gates/ or docs/decisions/ outside scripts/.
. "$CLAUDE_PROJECT_DIR/scripts/lib.sh"
need jq "winget install jqlang.jq, brew install jq or asdf"
cmd="$(jq -r '.tool_input.command // empty')"
[ -n "$cmd" ] || exit 0

if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])git([[:space:]]+-[cC][[:space:]]+[^[:space:]]+)*[[:space:]]+commit'; then
  b="$(git -C "$ROOT" symbolic-ref --short HEAD 2>/dev/null || true)"
  case "$b" in main|master) block 2 "guard-bash: no commits on $b. Create a branch first." ;; esac
  if printf '%s' "$cmd" | grep -qE -- '--amend' && [ -n "$(git -C "$ROOT" branch -r --contains HEAD 2>/dev/null)" ]; then
    block 2 "guard-bash: HEAD is already pushed. Make a new commit instead of --amend."
  fi
fi
printf '%s' "$cmd" | grep -qE -- '--no-verify' && block 2 "guard-bash: --no-verify bypasses the hooks. Fix the failure instead."
printf '%s' "$cmd" | grep -qE 'git[[:space:]].*push.*([[:space:]](-f|--force|--force-with-lease)([=[:space:]]|$)|[[:space:]]\+[^[:space:]]+)' \
  && block 2 "guard-bash: force push is not allowed."

case "$cmd" in
  scripts/*|./scripts/*|sh\ scripts/*|bash\ scripts/*) exit 0 ;;
esac
printf '%s' "$cmd" | grep -qE '(>|\btee\b|\bcp\b|\bmv\b|\brm\b|sed[[:space:]]+-i|\btouch\b|\bdd\b|\bln\b)[^;&|]*(\.gates/|docs/decisions/)' \
  && block 2 "guard-bash: write .gates/ via scripts/gate.sh and ADRs via the Write tool (new files only)."
exit 0

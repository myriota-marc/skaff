#!/bin/sh
# Hook self-test: runs every hook against sample input in a throwaway worktree of HEAD.
# Prints case | expected | actual and exits 1 on any mismatch.
set -u
SRC="$(git rev-parse --show-toplevel)"
tmp="$(mktemp -d)"; wt="$tmp/wt"; br="selftest/tmp-$$"
git -C "$SRC" worktree add -q -b "$br" "$wt" HEAD || exit 1
cleanup() { git -C "$SRC" worktree remove --force "$wt" 2>/dev/null; git -C "$SRC" branch -q -D "$br" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT INT TERM
for p in "$SRC"/.vale/styles/*/; do [ -d "$wt/.vale/styles/$(basename "$p")" ] || cp -r "$p" "$wt/.vale/styles/"; done
export CLAUDE_PROJECT_DIR="$wt" CONTINUITY_ENFORCEMENT=fail-closed
cd "$wt" || exit 1
H=.claude/hooks; fail=0; rows=''
EM="$(printf '\342\200\224')"
fm() { printf -- '---\ntype: Note\ntitle: %s\ndescription: Self-test fixture.\nstatus: draft\nupdated: 2026-01-01\nstale_after: %s\n---\n%s\n' "$1" "${3:-2999-01-01T00:00:00Z}" "$2"; }
row() { rows="$rows$1 | $2 | $3
"; [ "$2" = "$3" ] || fail=1; }
code() { "$@" >"$tmp/out" 2>&1; echo $?; }
tag() { c="$1"; grep -q "$2" "$tmp/out" && echo "$c" || echo "$c (no $2)"; }
adr1="$(ls docs/decisions/0001-*.md 2>/dev/null | head -n 1)"
if [ -z "$adr1" ]; then # fresh repo: stage a fixture ADR so case 1 has a tracked ADR to protect
  adr1=docs/decisions/0001-selftest-fixture.md
  printf -- '---\ntype: Decision Record\ntitle: "0001: Fixture"\n---\n' > "$adr1"; git add "$adr1"
fi

row "1 edit ADR 0001" 2 "$(code sh $H/guard-write.sh <<EOF
{"tool_name":"Edit","tool_input":{"file_path":"$wt/$adr1"}}
EOF
)"
case "$adr1" in *selftest-fixture*) git rm -q -f "$adr1" ;; esac
row "2 docs file without type" 2 "$(code sh $H/guard-write.sh <<EOF
{"tool_name":"Write","tool_input":{"file_path":"$wt/docs/notes.md","content":"# Notes\\n"}}
EOF
)"
fm "Dash test" "Pick one option ${EM} the first." > docs/dash.md
c="$(printf '{"tool_input":{"file_path":"%s/docs/dash.md"}}' "$wt" | code sh $H/lint-md.sh)"
row "3 em dash in a doc" "2" "$(tag "$c" Local.Dashes)"
fm "Passive test" "The file was written by the agent." > docs/passive.md
c="$(printf '{"tool_input":{"file_path":"%s/docs/passive.md"}}' "$wt" | code sh $H/lint-md.sh)"
row "4 passive sentence" "2" "$(tag "$c" write-good.Passive)"
printf 'updated stuff\n' > "$tmp/m1"
row "5 bad commit subject" 1 "$(code sh .githooks/commit-msg "$tmp/m1")"
git symbolic-ref HEAD refs/heads/main
row "6 commit on main" 1 "$(code sh .githooks/pre-commit)"
git symbolic-ref HEAD "refs/heads/$br"
row "7 --no-verify" 2 "$(code sh $H/guard-bash.sh <<'EOF'
{"tool_input":{"command":"git commit --no-verify -m 'chore: x'"}}
EOF
)"
printf 'chore: close item\n\nCloses-Item: Z9\n' > "$tmp/m2"
row "8 Closes-Item without evidence" 1 "$(code sh .githooks/commit-msg "$tmp/m2")"
fm "Old doc" "Old." 2000-01-01T00:00:00Z > docs/old.md
sh $H/session-start.sh > "$tmp/out" 2>&1
row "9 stale doc listed at SessionStart" listed "$(grep -q 'STALE docs/old.md' "$tmp/out" && echo listed || echo missing)"
printf -- '---\ntype: Project State\nnext_actions:\n  - {id: T1, do: open thing, done_when: human, status: open}\n---\n' > docs/STATE.md
c="$(echo '{"stop_hook_active":false,"session_id":"selftest"}' | code sh $H/stop-check.sh)"
row "10 stop with an open item" "2" "$(tag "$c" T1)"
git checkout -q -- . && rm -f docs/dash.md docs/passive.md docs/old.md
fm "Clean note" "This note shows that a clean commit passes every hook." > docs/clean.md
git add docs/clean.md
row "11 clean commit passes" 0 "$(code git -c core.hooksPath=.githooks commit -q -m 'docs: add clean self-test note')"
row "12 STATE edit mentioning .gates passes" 0 "$(code sh $H/guard-bash.sh <<'EOF'
{"tool_input":{"command":"sed -i 's#^verified: .*#verified: [.gates/A1.json]#' docs/STATE.md"}}
EOF
)"
row "13 shell write into .gates" 2 "$(code sh $H/guard-bash.sh <<'EOF'
{"tool_input":{"command":"echo x > .gates/A1.json"}}
EOF
)"
git symbolic-ref HEAD refs/heads/main
row "14 switch and commit in one call on main" 2 "$(code sh $H/guard-bash.sh <<'EOF'
{"tool_input":{"command":"git switch -c topic && git commit -m 'chore: x'"}}
EOF
)"
m="$(jq -r '.hooks.PreToolUse[] | select(any(.hooks[]; .command | test("guard-bash"))) | .matcher' .claude/settings.json | tr -d '\r')"
if printf 'PowerShell' | grep -qxE "$m"; then
  c="$(code sh $H/guard-bash.sh <<'EOF'
{"tool_name":"PowerShell","tool_input":{"command":"git commit --no-verify -m 'chore: x'"}}
EOF
)"
else c="unmatched ($m)"; fi
row "15 PowerShell tool is guarded" 2 "$c"
other="$tmp/other"; git init -q -b main "$other"; git -C "$other" symbolic-ref HEAD refs/heads/topic
row "16 git -C commit, other repo on a branch" 0 "$(code sh $H/guard-bash.sh <<EOF
{"tool_input":{"command":"git -C $other commit -m 'chore: x'"}}
EOF
)"
git -C "$other" symbolic-ref HEAD refs/heads/main
row "17 git -C commit, other repo on main" 2 "$(code sh $H/guard-bash.sh <<EOF
{"tool_input":{"command":"git -C $other commit -m 'chore: x'"}}
EOF
)"
git symbolic-ref HEAD "refs/heads/$br"
{ # a grown STATE: 27 done items, 3 open ones, a long verified list
  printf -- '---\ntype: Project State\ntitle: Big state\ndescription: Self-test fixture.\nstatus: stable\n'
  printf -- 'updated: 2026-01-01\nstale_after: 2999-01-01T00:00:00Z\nverified: [.gates/D1.json, .gates/D2.json, .gates/D3.json]\n'
  printf -- 'purpose: Exercise the cold start cap.\nstate: Many items are done.\nnext_actions:\n'
  i=1; while [ "$i" -le 27 ]; do printf '  - {id: D%s, do: finished work, done_when: human, status: done}\n' "$i"; i=$((i + 1)); done
  for i in 1 2 3; do printf '  - {id: O%s, do: open work, done_when: human, status: open}\n' "$i"; done
  printf -- '---\n'
} > docs/STATE.md
fm "Old doc" "Old." 2000-01-01T00:00:00Z > docs/old.md
sh $H/session-start.sh > "$tmp/out" 2>&1
c=ok; [ "$(wc -l < "$tmp/out")" -le 40 ] || c="over 40 lines"
for want in 'STALE docs/old.md' 'O1 (open)' 'O2 (open)' 'O3 (open)'; do grep -qF "$want" "$tmp/out" || c="missing $want"; done
row "18 cold start keeps stale docs and open items within 40 lines" ok "$c"
git checkout -q -- docs/STATE.md && rm -f docs/old.md
[ "$fail" -eq 0 ] || { echo "last output:"; head -n 20 "$tmp/out"; }

printf 'case | expected | actual\n--- | --- | ---\n%s' "$rows"
exit "$fail"

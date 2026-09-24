#!/bin/sh
# PreToolUse Bash|PowerShell: block commits on main, hook bypass, force push, amend of pushed
# commits, and shell writes to .gates/ or docs/decisions/ outside scripts/.
. "$CLAUDE_PROJECT_DIR/scripts/lib.sh"
need jq "winget install jqlang.jq, brew install jq or asdf"
in="$(cat)"
cmd="$(printf '%s' "$in" | jq -r '.tool_input.command // empty' | tr -d '\r')"
[ -n "$cmd" ] || exit 0
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' | tr -d '\r')"

# tokens <command>: quote-aware shell words, one per line. "@@SEG@@" ends each simple command
# (at ; & | ( ) or newline) and "@@REDIR@@" precedes the target word of > or >>.
tokens() {
  printf '%s' "$1" | awk -v SQ="'" '
    function endword() {
      if (w == "" && !quoted) return
      gsub(/\n/, " ", w); print w; w = ""; quoted = 0
    }
    { s = s $0 "\n" }
    END {
      for (p = 1; p <= length(s); p++) {
        ch = substr(s, p, 1)
        if (q == SQ) { if (ch == SQ) q = ""; else w = w ch; continue }
        if (q == "\"") {
          if (ch == "\\") { p++; w = w substr(s, p, 1); continue }
          if (ch == "\"") q = ""; else w = w ch
          continue
        }
        if (ch == SQ || ch == "\"") { q = ch; quoted = 1; continue }
        if (ch == "\\") { p++; w = w substr(s, p, 1); continue }
        if (ch == " " || ch == "\t") { endword(); continue }
        if (ch == "\n" || ch == ";" || ch == "&" || ch == "|" || ch == "(" || ch == ")") { endword(); print "@@SEG@@"; continue }
        if (ch == ">") { endword(); print "@@REDIR@@"; if (substr(s, p + 1, 1) == ">") p++; continue }
        if (ch == "<") { endword(); continue }
        w = w ch
      }
      endword(); print "@@SEG@@"
    }'
}

# commit_repo <command>: if the command runs git commit, print "FOUND <dir>", where <dir> is the
# git -C directory, else the directory of a preceding cd / Set-Location, else empty (project repo).
commit_repo() {
  tokens "$1" | awk '
    function isabs(d) { return d ~ /^\// || d ~ /^[A-Za-z]:/ || d ~ /^~/ }
    function seg(   k, j, gd, d) {
      k = 1; while (k <= n && a[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) k++
      if (k > n) return
      if (a[k] == "cd" || a[k] == "Set-Location" || a[k] == "sl" || a[k] == "pushd" || a[k] == "Push-Location") {
        for (j = k + 1; j <= n; j++) if (a[j] !~ /^-/) { cd = (cd != "" && !isabs(a[j])) ? cd "/" a[j] : a[j]; break }
        return
      }
      if (a[k] == "sudo" || a[k] == "command" || a[k] == "env") k++
      if (a[k] != "git" && a[k] != "git.exe") return
      gd = ""
      for (j = k + 1; j <= n; j++) {
        if (a[j] == "-C") { j++; gd = (gd != "" && !isabs(a[j])) ? gd "/" a[j] : a[j]; continue }
        if (a[j] == "-c") { j++; continue }
        if (a[j] ~ /^-/) continue
        break
      }
      if (a[j] != "commit") return
      d = gd
      if (d == "") d = cd; else if (!isabs(d) && cd != "") d = cd "/" d
      print "FOUND " d; exit
    }
    $0 == "@@SEG@@" { seg(); n = 0; next }
    $0 == "@@REDIR@@" { next }
    { a[++n] = $0 }'
}

# protected_writes <command>: print each shell write target under .gates/ or docs/decisions/.
# Only real targets count (the word after > or >>, tee/rm/mv/touch/truncate arguments, the
# cp/ln destination, dd of=, sed -i files, git rm/mv paths), so a command that merely mentions
# .gates/ in a sed script or a message while writing docs/STATE.md passes.
protected_writes() {
  tokens "$1" | awk '
    function isbad(t) { sub(/^\.\//, "", t); return t ~ /(^|\/)(\.gates|docs\/decisions)\// }
    function check(   i, k, c, t, inplace, script, skip) {
      k = 1; while (k <= n && a[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) k++
      if (k > n) return
      c = a[k]; sub(/.*\//, "", c)
      if (c == "sudo" || c == "command" || c == "env") { k++; c = a[k]; sub(/.*\//, "", c) }
      if (c == "git" && (a[k+1] == "rm" || a[k+1] == "mv")) {
        for (i = k + 2; i <= n; i++) if (a[i] !~ /^-/ && isbad(a[i])) print a[i]
        return
      }
      if (c == "rm" || c == "mv" || c == "touch" || c == "tee" || c == "truncate") {
        for (i = k + 1; i <= n; i++) if (a[i] !~ /^-/ && isbad(a[i])) print a[i]
        return
      }
      if (c == "cp" || c == "ln" || c == "install") { if (n > k && isbad(a[n])) print a[n]; return }
      if (c == "dd") {
        for (i = k + 1; i <= n; i++) if (a[i] ~ /^of=/) { t = a[i]; sub(/^of=/, "", t); if (isbad(t)) print t }
        return
      }
      if (c == "sed") {
        inplace = 0; script = 1
        for (i = k + 1; i <= n; i++) {
          if (a[i] ~ /^-[A-Za-z]*i/ || a[i] ~ /^--in-place/) inplace = 1
          if (a[i] == "-e" || a[i] == "-f" || a[i] ~ /^--(expression|file)/) script = 0
        }
        if (!inplace) return
        skip = script
        for (i = k + 1; i <= n; i++) {
          if (a[i] ~ /^-/) { if (a[i] == "-e" || a[i] == "-f") i++; continue }
          if (skip) { skip = 0; continue }
          if (isbad(a[i])) print a[i]
        }
      }
    }
    $0 == "@@SEG@@" { check(); n = 0; redir = 0; next }
    $0 == "@@REDIR@@" { redir = 1; next }
    redir { if (isbad($0)) print; redir = 0; next }
    { a[++n] = $0 }'
}

# Commit checks run against the repo the command targets (git -C or a leading cd), resolved
# against the tool cwd, else the project repo. The branch is read before the command runs, so
# "git switch -c x && git commit" on main is blocked: switch in one call, commit in the next.
res="$(commit_repo "$cmd")"
if [ -n "$res" ]; then
  dir="${res#FOUND}"; dir="${dir# }"
  case "$dir" in
    '') repo="$ROOT" ;;
    /*|[A-Za-z]:*|~*) repo="$dir" ;;
    *) repo="${cwd:-$ROOT}/$dir" ;;
  esac
  b="$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || true)"
  case "$b" in main|master) block 2 "guard-bash: no commits on $b in $repo. Switch to a branch in one call, then commit in the next." ;; esac
  if printf '%s' "$cmd" | grep -qE -- '--amend' && [ -n "$(git -C "$repo" branch -r --contains HEAD 2>/dev/null)" ]; then
    block 2 "guard-bash: HEAD in $repo is already pushed. Make a new commit instead of --amend."
  fi
fi
printf '%s' "$cmd" | grep -qE -- '--no-verify' && block 2 "guard-bash: --no-verify bypasses the hooks. Fix the failure instead."
printf '%s' "$cmd" | grep -qE 'git[[:space:]].*push.*([[:space:]](-f|--force|--force-with-lease)([=[:space:]]|$)|[[:space:]]\+[^[:space:]]+)' \
  && block 2 "guard-bash: force push is not allowed."

case "$cmd" in
  scripts/*|./scripts/*|sh\ scripts/*|bash\ scripts/*) exit 0 ;;
esac
hits="$(protected_writes "$cmd")"
[ -z "$hits" ] || block 2 "guard-bash: write .gates/ via scripts/gate.sh and ADRs via the Write tool (new files only):" "$hits"
exit 0

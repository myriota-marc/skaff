# Continuity Protocol

How this repo stays resumable from artifact state alone. Read before touching `docs/`, `.gates/`, `.githooks/`, `.claude/hooks/`, or `scripts/{gate,adr-index,bootstrap,selftest}.sh`. `HUMAN` below is the human actor id recorded in `.gates/` evidence (for example `human:<username>`).

Goal: any future agent or human resumes from artifact state alone. Minimise tokens carried and tokens read at cold start. Time matters.

Operating rules: repo is the memory; grep before read; evidence is only a passing approved objective test or a human Accept captured by the gate hook; checklist in docs/STATE.md front matter next_actions; questions only at Phase 1 and Gate G1, else conventional default + ADR; Phase 1 answers settled; NO em or en dashes anywhere.

## Living docs (OKF 0.2)
Every docs/**/*.md except ADRs and reserved index.md/log.md is a living doc. Front matter holds truth, body < 40 lines, never repeats front matter.
```yaml
---
type: Project State
title: <repo> state
description: Resume point for agents and humans. Read first.
status: stable                 # draft | stable | deprecated
updated: YYYY-MM-DD
stale_after: YYYY-MM-DDT00:00:00Z   # STATE = updated + 14d, other docs + 90d
generated: {by: claude-code/<model-id>, at: <ISO8601>}
verified: []                   # only ever copied from .gates evidence
purpose: <one sentence>
state: <1-3 sentences>
open_questions:
  - {id: Q1, q: <question>, owner: <actor>}
next_actions:
  - {id: A1, do: <action>, done_when: "test: <cmd>" | human, status: open | awaiting | blocked | done, evidence: .gates/A1.json}
---
```
Minimum doc set: docs/STATE.md and docs/decisions/. No log.md (git history is the log).

## ADRs
docs/decisions/NNNN-<kebab>.md, body < 20 lines:
```yaml
---
type: Decision Record
title: "NNNN: <decision, imperative>"
description: <one sentence>
status: stable
date: YYYY-MM-DD
supersedes: []
generated: {by: claude-code/<model-id>, at: <ISO8601>}
tags: []
---
## Context
## Decision
## Alternatives
## Consequences
```
Immutable once committed; change via new ADR with supersedes. scripts/adr-index.sh generates docs/decisions/index.md (front matter only okf_version: "0.2"), one line per ADR with effective status (superseded computed from later supersedes). pre-commit fails if index stale.

## Gates
scripts/gate.sh <ID> runs done_when test; on pass writes .gates/<ID>.json {id, by: "process:gate", at, head, cmd, exit: 0}. Human gates: evidence from hooks only, {id, by: HUMAN, at, head, answer}. .gates/ committed. Close with commit trailer Closes-Item: <ID>, status: done, copy evidence path into verified.

## Claude Code hooks (.claude/settings.json project scope, .claude/hooks/*.sh POSIX sh + jq, $CLAUDE_PROJECT_DIR, block = exit 2 + stderr truncated to 20 lines)
- SessionStart startup|resume|clear|compact -> session-start.sh: <= 40 lines: branch, STATE front matter, last 10 ADR index lines, git log --oneline -5, open gates, stale docs.
- PreToolUse Write|Edit|MultiEdit -> guard-write.sh: blocks change to tracked docs/decisions/NNNN-*.md; any path under .gates/; Write of docs/**/*.md without OKF type.
- PreToolUse Bash -> guard-bash.sh: blocks git commit on main/master; --no-verify; force push; commit --amend of pushed commit; shell writes to .gates/ or docs/decisions/ other than via scripts/.
- PostToolUse Write|Edit|MultiEdit -> lint-md.sh: in-scope .md: Vale on that file + OKF key check.
- PostToolUse AskUserQuestion -> gate-capture.sh: header "Gate <ID>" and chosen label starts with Accept -> .gates/<ID>.json. Payload (confirmed live): tool_input.{questions,answers,annotations}, answers keyed by full question text, value = chosen label; tool_response mirrors the same keys. Every payload is also logged raw to .claude/.cache/gate-capture-last.json.
- UserPromptSubmit -> gate-capture.sh: prompt ^ACCEPT <ID> writes same evidence.
- Stop -> stop-check.sh: exit 0 if stop_hook_active; else open next_actions -> exit 2 listing them; max 2 blocks per session counted in .claude/.cache/ (gitignored).

## Git hooks (.githooks/, core.hooksPath via scripts/bootstrap.sh which also checks pinned tool versions and runs vale sync)
- pre-commit: reject staged M/D/R under docs/decisions/NNNN-*.md; OKF + Vale on staged in-scope .md; fail if index stale; gitleaks protect --staged --redact when present else Skaff regex fallback; reject commits on main.
- commit-msg: ^(feat|fix|docs|style|refactor|test|chore|build|ci|perf)(\([a-z0-9-]+\))?!?: .{1,72}$ ; reject em/en dashes; ADR: NNNN trailer when ADR added; Closes-Item: <ID> requires committed .gates/<ID>.json.
- Scope: docs/** and root *.md; exclude .claude/, do-work/, .github/, tool mirror dirs. Warn-only mode: all hooks exit 0 and print to stderr.

## Relation to other Skaff conventions
- knowledge-protocol.md: ADRs use supersedes + the generated index, never a Status line edit; sections Context/Decision/Alternatives/Consequences; schema is this file.
- do-work/templates/ADR-template.md: the ADR format above.
- .claude/agents/git-workflow.md: hooks are versioned in .githooks/ via core.hooksPath; its secret scan runs in .githooks/pre-commit. Frozen pack versions still carry the old text.
- CLAUDE.md and AGENTS.md: identical "Continuity" section <= 8 lines: read SessionStart output then docs/STATE.md; ADRs immutable; gates decide done.
- Only doc-writer writes ADRs after bootstrap; ADRs 0001-0003 are bootstrap exceptions.
- Knobs: CONTINUITY_ENFORCEMENT (fail-closed | warn-only), CONTINUITY_HUMAN (default set in scripts/lib.sh by the installer), CONTINUITY_EXCLUDE_ROOT_MD.

## Vale
.vale.ini: StylesPath=.vale/styles, MinAlertLevel=error, Vocab=Base, Packages pinned by release URL (Google, write-good), [*.md] BasedOnStyles = Vale, write-good, Google, Local; write-good.Passive/Weasel/TooWordy = error; Google.Units = NO; Vale.Terms = NO. Local/Dashes.yml (existence, error, \u2014 \u2013), Local/Banned.yml (existence, error, load-bearing). Vale version pinned in .tool-versions. Commit Local/ + vocab, gitignore synced packages. "Dash and banned-words only" mode: BasedOnStyles = Local, no packages.

## Selftest
scripts/selftest.sh in throwaway worktree on temp branch; feeds hook scripts sample JSON; prints case|expected|actual; non-zero on mismatch. Cases: edit ADR 0001; docs without type; em dash; passive sentence; bad commit subject; commit on main; --no-verify; Closes-Item without evidence; stale doc at SessionStart; Stop with open item; clean commit passes. A repo with no ADR gets a staged fixture ADR for case 1. The self-test is the gate for any hook change (item A1).

## Install commit sequence
Skaff install.sh / install.ps1 ship this layer (see INSTALL.md). 1 chore: bootstrap claude agent scaffold (on main, before hooks exist); then scripts/bootstrap.sh and a branch; 2 docs(adr): record scaffold decisions (0001-0003, optional); 3 chore(state): record gate A1 (Closes-Item: A1, after scripts/gate.sh A1); 4 chore(state): record gate A2 (Closes-Item: A2, human validates cold start).

## Pitfalls
1. Git hooks set CLAUDE_PROJECT_DIR from `git rev-parse --show-toplevel` before sourcing lib.sh; otherwise a commit from a worktree lints the wrong tree.
2. Vale lints YAML front matter values too (a passive `state:` fails). Quote YAML flow map values that contain `?` or `: `.
3. Windows: core.autocrlf breaks sh scripts, hence `* text=auto eol=lf` and bootstrap setting autocrlf false. jq emits CRLF: pipe `@tsv` output through `tr -d '\r'` (a captured answer read as `Accept A2\r` and never matched); gate evidence JSON also has CRLF on disk and eol=lf normalises it on commit.
4. Windows: winget shims are not on PATH for shells that were already running; put jq and gitleaks in ~/bin. The Claude Code Bash tool heredoc collapses `\\`, so write files that contain backslashes with the Write tool.
5. Claude Code picks up project .claude/settings.json hooks mid-session (confirmed on 2.1.281: guard-write blocked a live Write). guard-bash also matches literal text, so a command that merely mentions a blocked flag or a write into .gates/ is refused.
6. `sed -n "/x/,$p"` in double quotes expands `$p`; the self-test caught it. Keep the self-test as the gate.
7. state_items reads only the next_actions block, never open_questions, or questions show up as open gates.

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
- PostToolUse AskUserQuestion -> gate-capture.sh: header "Gate <ID>" and chosen label starts with Accept -> .gates/<ID>.json. Log one raw payload to .claude/.cache/ first to confirm field names.
- UserPromptSubmit -> gate-capture.sh: prompt ^ACCEPT <ID> writes same evidence.
- Stop -> stop-check.sh: exit 0 if stop_hook_active; else open next_actions -> exit 2 listing them; max 2 blocks per session counted in .claude/.cache/ (gitignored).

## Git hooks (.githooks/, core.hooksPath via scripts/bootstrap.sh which also checks pinned tool versions and runs vale sync)
- pre-commit: reject staged M/D/R under docs/decisions/NNNN-*.md; OKF + Vale on staged in-scope .md; fail if index stale; gitleaks protect --staged --redact when present else Skaff regex fallback; reject commits on main.
- commit-msg: ^(feat|fix|docs|style|refactor|test|chore|build|ci|perf)(\([a-z0-9-]+\))?!?: .{1,72}$ ; reject em/en dashes; ADR: NNNN trailer when ADR added; Closes-Item: <ID> requires committed .gates/<ID>.json.
- Scope: docs/** and root *.md; exclude .claude/, do-work/, .github/, tool mirror dirs. Warn-only mode: all hooks exit 0 and print to stderr.

## Relation to other Skaff conventions
- knowledge-protocol.md: replace "edit old Status line to Superseded" with supersedes + generated index; section order Context/Decision/Alternatives/Consequences; point to OKF schema.
- do-work/templates/ADR-template.md: match ADR format above.
- .claude/agents/git-workflow.md: replace "Do not commit the hook itself" with versioned .githooks/ via core.hooksPath; merge its secret scan into .githooks/pre-commit.
- CLAUDE.md and AGENTS.md: identical "Continuity" section <= 8 lines: read SessionStart output then docs/STATE.md; ADRs immutable; gates decide done.
- Only doc-writer writes ADRs after bootstrap; ADRs 0001-0003 are bootstrap exceptions.

## Vale
.vale.ini: StylesPath=.vale/styles, MinAlertLevel=error, Vocab=Base, Packages pinned by release URL (Google, write-good), [*.md] BasedOnStyles = Vale, write-good, Google, Local; write-good.Passive/Weasel/TooWordy = error; Google.Units = NO; Vale.Terms = NO. Local/Dashes.yml (existence, error, \u2014 \u2013), Local/Banned.yml (existence, error, load-bearing). Vale version pinned in .tool-versions. Commit Local/ + vocab, gitignore synced packages. "Dash and banned-words only" mode: BasedOnStyles = Local, no packages.

## Selftest
scripts/selftest.sh in throwaway worktree on temp branch; feeds hook scripts sample JSON; prints case|expected|actual; non-zero on mismatch. Cases: edit ADR 0001; docs without type; em dash; passive sentence; bad commit subject; commit on main; --no-verify; Closes-Item without evidence; stale doc at SessionStart; Stop with open item; clean commit passes.

## Install commit sequence
1 chore(scaffold): install skaff <pack>@<version>; 2 docs(adr): record scaffold decisions; 3 feat(continuity): add OKF state doc, ADR index and gate scripts; 4 build(hooks): enforce ADR, doc and commit hygiene in git hooks; 5 build(claude): add Claude Code hooks for lint, gates and cold start; 6 docs(conventions): reconcile skaff knowledge protocol with immutable ADRs; 7 test(hooks): add hook self-test (Closes-Item: A1); 8 chore(state): record gate A2 (Closes-Item: A2).

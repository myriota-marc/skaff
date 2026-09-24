# AGENTS.md

## Overview

This repository was scaffolded with skaff. Shared agent instructions live here so any supported coding tool can work consistently.

## Continuity

- Cold start: read the SessionStart hook output, then the `docs/STATE.md` front matter. Do not rebuild state from chat or code.
- ADRs in `docs/decisions/` are immutable once committed. Change one with a new ADR listing it in `supersedes`, then run `scripts/adr-index.sh`.
- Gates decide done: an item closes only with `.gates/<ID>.json` evidence (a passing `done_when` test or a captured human Accept) and a `Closes-Item: <ID>` commit trailer.
- Full rules: `.claude/conventions/continuity-protocol.md`.

## Repository Structure

- `do-work/` - task queue, plans, and summaries
- `.claude/agents/` - specialist agent definitions
- `.claude/conventions/` - reusable working rules and style guides

## Behavioral Guidelines

1. **Think Before Coding** - state assumptions, surface ambiguity, and ask rather than guess.
2. **Simplicity First** - write the minimum solution, with no speculative features or over-abstraction.
3. **Surgical Changes** - touch only what is needed, match existing style, and clean up only orphans created by your change.
4. **Goal-Driven Execution** - make a short plan with verification criteria before coding, then verify the result.
5. **House Rules** - no em dashes, use AskUserQuestion for blocking ambiguity, write summaries to `do-work/summaries/`, and use Conventional Commits.

Before coding, read the relevant file from `.claude/conventions/`.

## Dev Environment Tips

- Use the repository's documented install, test, lint, and build commands.
- Before finishing, run the relevant checks for the files you changed.
- If a command is missing, do not invent a new workflow. Note the gap instead.

## do-work Workflow

Follow the queue in order: capture, scout, plan, implement, review, ratchet, git. Read `.claude/conventions/do-work-protocol.md` before changing anything under `do-work/`.

## Agent Roster

Specialist agents defined in `.claude/agents/` handle scout, implement, doc-write, review, ratchet, and git. For tools that support sub-agent spawning, use the `agent` tool to invoke them.

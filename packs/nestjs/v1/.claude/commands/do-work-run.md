---
name: do-work-run
description: Drain the do-work queue. Main session orchestrates; spawns nestjs-scout, nestjs-implement, nestjs-doc-writer, reviewer, ratchet, and git-workflow specialists per REQ, plus nestjs-module-specialist and nestjs-persistence-specialist when a REQ needs them. Use when the user says "do work run", "work", "go", "start", or confirms the work prompt.
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Agent
  - "Bash(git status*)"
  - "Bash(git log*)"
  - "Bash(mv do-work/*)"
  - "Bash(cp do-work/*)"
  - "Bash(cat do-work/.lock*)"
  - "Bash(rm do-work/.lock*)"
  - "Bash(date*)"
---

# /do-work-run

**You (the main Claude Code session) are the orchestrator.** Read this command body, then drain
the queue. Delegate all implementation, doc, review, ratchet, and git work to specialist
sub-agents via the Agent tool. You own state transitions and escalation decisions only. You do
not write code, docs, or commits yourself.

Be concise. Avoid long reasoning explanations. Report progress to the user in short updates
between specialist spawns.

## First rule, loudest rule - YOU DO NOT AUTHOR

You spawn specialists. You do not write. Before ANY Write or Edit or Bash-that-creates-content
call, ask yourself: **"Is this a state transition or is this authoring?"**

**State transitions you own** (these, and only these, you may perform yourself):

- `mv` a REQ between `do-work/`, `do-work/working/`, `do-work/archive/`
- `do-work/.lock` acquire and release
- Update a REQ's frontmatter `status` / `claimed_at` / `route` / `completed_at` fields
- Append or update `## Loop Counters` (increment-and-timestamp only)
- Append `## Override` section on user-selected escalation override
- Write the final `do-work/summaries/do-work-run-<date>.md` loop summary

**Authoring you MUST NOT perform even if it seems faster** (spawn the owner instead):

| If you catch yourself writing... | Stop. Spawn this specialist. |
| -------------------------------- | ---------------------------- |
| `## Plan` or `## Plan Hash` content | `nestjs-implement` in plan-only mode |
| Any `.ts` file under `src/` or `test/`, or a migration file | `nestjs-implement` in implement mode |
| TSDoc edits, README updates, or ADRs under `docs/decisions/` | `nestjs-doc-writer` |
| Review verdicts, blocking-issue lists, `## Plan Verification` edits | `reviewer` (or skill-owned) |
| Ratchet scoresets, `## Ratchet` sections, `baselines.jsonl` entries | `ratchet` |
| Commit messages, branch creation, PR bodies | `git-workflow` |
| Scout findings briefs | `nestjs-scout` |
| Module placement, export, or DI advice | `nestjs-module-specialist` |
| Migration plans, index or transaction advice | `nestjs-persistence-specialist` |

**Heuristic for borderline cases:** if you are generating prose that will live on disk past this
command's execution and was not listed in State transitions above, you are authoring. Stop.
Spawn the owner.

If you have already started authoring - mid-sentence, mid-file - stop the current tool call
flow, revert any partial authored content from disk if possible, and spawn the correct
specialist with the intent (not your partial draft) as the dispatch brief.

## AskUserQuestion is REQUIRED, not optional, for three cases

You must use `AskUserQuestion` before proceeding when any of these fire. Guessing is a bug.

1. **Clarification** - the REQ body, scout findings, or a specialist's output contains an Open
   Question, a "resolve before implementation" note, or a decision that has no defensible
   default.
2. **Architectural decisions** - a plan or implementation proposes a cross-REQ or cross-surface
   change not explicitly authorised in the REQ (a new module boundary, a new dependency, a new
   ORM or transport, or a destructive schema change).
3. **Escalation** - any condition in the Escalation Rules section below. Use the four-option
   structured question verbatim from that section.

Do **not** use AskUserQuestion for:

- Formatting preferences the conventions already decide
- Choices a specialist is chartered to make within their own scope
- Progress pings ("should I continue?") - drive the loop unless paused by an escalation trigger

## Scale limits

The main session's context grows across a queue drain - every specialist summary stays in your
context. Guard rails:

- **Recommended:** drain queues of 10 or fewer REQs per invocation.
- **Warn-on-start:** queue size > 20 triggers an AskUserQuestion before beginning:

  > The queue has N pending REQs. Draining this many in one pass may cause drift as context
  > fills. Continue with all N, split into batches, or cancel?

- **Hard ceiling:** queue size > 40 refuses to start. User must move REQs to `do-work/deferred/`
  or process in batches.
- **Mid-drain backstop:** when your own context exceeds ~80%, finish the current REQ cleanly
  through archive, write a progress note to
  `do-work/summaries/do-work-run-<date>-progress.md`, release the lock, and tell the user the
  queue is partial. Re-invoke `/do-work-run` in a fresh session to continue.

This is explicit pause, not auto-compaction. Auto-compaction corrupts orchestration state
mid-loop.

## Why this is a command, not a sub-agent

A sub-agent cannot spawn sibling sub-agents via the Agent tool - the project's specialist roster
isn't in a sub-agent's scope. The main interactive session can. That is this command's reason
for existing. If you find yourself wanting to delegate orchestration to a sub-agent, stop. You
are the orchestrator.

## Before acting

Read these conventions in full, then cite them by name in your first user-facing update:

- `.claude/conventions/do-work-protocol.md`
- `.claude/conventions/coverage-protocol.md`

## Queue lock

Before touching anything, acquire `do-work/.lock` per do-work-protocol.md. If the lock is held
and fresh, refuse to start and surface the lock holder. If stale (>= 2 hours), overwrite and log
a stale-lock-cleared summary. Release the lock on any exit path - clean drain, paused escalation,
or abort.

## Processing Loop

For each `REQ-*-pending.md` in `do-work/`, process one at a time:

1. **Pre-flight Verification gate.** Read the REQ in `do-work/`. If it does not already have a
   `## Verification` section, **do not proceed**. Escalate via AskUserQuestion and instruct the
   user to run `do work verify` before `do work run`. If the user confirms they want to proceed
   without verification, require an explicit `override_verification: true` field in the REQ
   frontmatter before continuing. Record the override in the loop summary.
2. Move REQ file to `do-work/working/`. Rename to `REQ-NNN-in-progress.md`.
3. **Triage complexity** by reading the REQ file:
   - If REQ frontmatter has a `complexity:` field, use it directly.
   - Otherwise classify: **Simple** (small fix, location known), **Medium** (clear goal, location
     unknown), **Complex** (new feature, architectural, multi-module).
4. **Scout** (medium and complex only): spawn `nestjs-scout` via
   `Agent(subagent_type: "nestjs-scout", prompt: <dispatch brief>)`. Wait for its findings brief
   at `do-work/scout/REQ-NNN-*-findings.md`.
5. **Domain advisors** (conditional, read-only, may run in parallel with each other after the
   scout returns). Spawn only when the trigger fires - an advisor with nothing to advise on is
   wasted context:
   - `nestjs-module-specialist` when the REQ adds a module or provider, moves code between
     modules, changes what a module exports, or when the scout reported an import cycle or a
     cross-boundary relative import.
   - `nestjs-persistence-specialist` when the REQ adds or changes an entity, a schema, a
     migration, or a query on a hot path.

   Each writes an advice brief to `do-work/scout/REQ-NNN-<topic>-advice.md`. Pass the brief paths
   into the planning brief at step 6.
6. **Plan**: spawn `nestjs-implement` in **plan-only mode**. Brief must name the mode
   explicitly. The agent writes `## Plan` and `## Plan Hash` sections inline in the REQ file and
   returns without touching code.
7. **Plan verification**: the `verify-plan` skill action runs automatically and appends
   `## Plan Verification` to the REQ. Do not proceed until post-fix coverage is 100%. If below
   100%, escalate via AskUserQuestion.
8. **Implement**: spawn `nestjs-implement` with the full REQ content (including `## Plan`) in
   **implement mode**.
9. **Documentation**: if complex, if docs are explicitly in scope, or if any specialist
   recommended an ADR, spawn `nestjs-doc-writer`.
10. **Review**: spawn `reviewer`. Act on verdict:
    - `Approve` - proceed to step 11.
    - `Request Changes` - increment the REQ's `implement_review_ratchet_cycles` counter (Loop
      Counters section), write back. If counter > 5, escalate. Otherwise re-spawn
      `nestjs-implement` with blocking issues as the task brief. Return to step 10.
    - `Escalate` - AskUserQuestion with the escalation reason. Pause. Wait.
11. **Ratchet**: spawn `ratchet`. Act on verdict:
    - `Kept` - proceed to step 12. The ratchet has written a `## Ratchet` section into the REQ
      and appended the new scoreset to `do-work/ratchet/baselines.jsonl`.
    - `Rejected` - increment the loop counter. If > 5, escalate. Otherwise re-spawn
      `nestjs-implement` with failing dimensions from Blocking Dimensions. Return to step 10
      (reviewer re-reviews before ratchet re-runs).
12. **Git**: spawn `git-workflow`.
13. **Archive**: move REQ file to `do-work/archive/`. Rename to `REQ-NNN-done.md`. Append
    implementation summary.
14. Continue to the next pending REQ.

After queue drained, the `cleanup` skill action runs automatically. Do not perform it manually.
Then release the lock.

## Knowledge artefacts

Specialists that write to `docs/decisions/` or `do-work/proposed-conventions/` end their return
summary with a `Knowledge Artefacts:` block per `.claude/conventions/knowledge-protocol.md`.
Aggregate those into a `## Knowledge Artefacts This Run` section in the loop summary, and name
any proposal that reached Maturity 3 so the user can open a promotion REQ.

## Escalation Rules

Escalate via AskUserQuestion when any of these fire:

- Reviewer returns verdict `Escalate`.
- Same blocking issue returned to `nestjs-implement` more than twice.
- REQ's total implement-review-ratchet cycle count > 5.
- No specialist can be determined as owner of a failing phase.

**Escalation options** (structured AskUserQuestion with these four):

1. **Override ratchet (document reason)** - user types a reason. Write a `## Override` section in
   the REQ with reason, timestamp, and which gate was overridden. The `## Ratchet` section is
   untouched. Proceed to step 12.
2. **Split REQ into smaller units** - move to `do-work/archive/abandoned/REQ-NNN-abandoned.md`
   with a note. Continue with next pending REQ.
3. **Abandon REQ** - same archive path as Split, no re-capture expectation.
4. **Continue looping** - total-loop cap += 3. Resume from step 10.

All other decisions are autonomous.

## Dispatch brief budget

Every Agent invocation respects the 2000-token verbatim-content cap from do-work-protocol.md
Dispatch Brief Budget. REQ body, scout findings, advisor briefs, reviewer blocking issues,
ratchet blocking dimensions, and plan delta notes all count. File paths do not. Over budget:
include the REQ path with a two-sentence summary; the specialist re-reads from disk.

## Loop counters

Track per-REQ cycles in the REQ file itself by appending a `## Loop Counters` section on first
increment:

```markdown
## Loop Counters

| Counter | Value | Last updated |
| ------- | ----- | ------------ |
| implement_review_ratchet_cycles | 3 | 2026-04-24T11:17:00Z |
| same_issue_cycles | 2 | 2026-04-24T11:17:00Z |
```

Counters survive process restart. On re-spawn, read current value, increment, write back, pass
updated count in the dispatch brief.

## Hard rules

- Never implement, review, or commit code yourself. Spawn a specialist.
- Never summarise or paraphrase a REQ in a dispatch brief in a way that replaces the source.
  Specialists always have the option to re-read from disk.
- Never touch `## Plan`, `## Plan Hash`, `## Ratchet`, or `## Verification` /
  `## Plan Verification` sections. Those are specialist-owned or skill-owned.
- Never release the lock mid-REQ without writing a progress summary.
- Specialists hit turn limits (30 to 50 turns) on long REQs. When one returns unfinished, resume the same agent with SendMessage (its ID from the spawn result); a fresh spawn loses its context.
- The verify-request, verify-plan and cleanup actions come from the `bladnman/do-work` skill, which Skaff does not install. If it is missing, install it (`npx skills add bladnman/do-work`) or use the stand-in procedure in INSTALL.md "do-work skill"; never skip the gates.
- No em dashes anywhere. Use " - " instead.

## Definition of Done

- [ ] Conventions cited in first output
- [ ] Lock acquired; released on every exit
- [ ] All pending REQ files either archived to `do-work/archive/` or paused with documented escalation reason
- [ ] Every processed REQ has `## Plan` written before implementation began
- [ ] Every processed REQ has `## Plan Verification` at 100% post-fix coverage before implementation began
- [ ] Domain advisors spawned only where their trigger fired, and their briefs passed into the planning brief
- [ ] No orphan files left in `do-work/working/`
- [ ] Each archived REQ has an appended implementation summary
- [ ] Loop summary written to `do-work/summaries/do-work-run-<date>.md` naming every REQ, specialists spawned per REQ, final verdict, and a `## Knowledge Artefacts This Run` section

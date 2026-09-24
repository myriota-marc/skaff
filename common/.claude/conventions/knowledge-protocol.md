# Knowledge Protocol

How agents capture project-specific knowledge that does not belong in conventions yet. Read this before writing to `docs/decisions/` or `do-work/proposed-conventions/`.

## Placeholders in this file

This file ships once in `common/` and installs identically into every pack, so it cannot hard-code any single pack's agent names. Angle-bracket placeholders stand in for values that vary per installed pack, the same convention `packs/TEMPLATE-CHECKLIST.md` uses for `<lang>` when describing a new pack:

- `<pack>-doc-writer` - this project's doc-writer agent (e.g. `react-doc-writer`, `tf-doc-writer`). Check `.claude/.pack` or `.claude/agents/` for the actual name.
- `<pack>-implement` - this project's implement agent (e.g. `react-implement`, `tf-implement`).
- "domain advisor or specialist agent" - any read-only, knowledge-contributing agent this project defines (for example a `*-specialist.md` agent, or a project-local long-lived domain agent). Not every pack ships one. Packs and projects without a dedicated advisor simply do not use Lane 2 until one is added; see `.claude/agents/` for this project's actual roster.

## Why two lanes exist

Conventions in `.claude/conventions/` earn their authority by being curated and stable. If any agent could append, they would drift into a dumping ground that future agents trust without vetting.

So agent-authored knowledge has two protected lanes outside conventions:

| Lane                              | Purpose                                                              | Owner                       | Lifecycle                                                       |
| --------------------------------- | -------------------------------------------------------------------- | --------------------------- | --------------------------------------------------------------- |
| `docs/decisions/` (ADRs)          | One-off decisions made in a REQ that future readers must understand   | `<pack>-doc-writer`         | Append-only. Superseded by a later ADR, never deleted.          |
| `do-work/proposed-conventions/`   | Recurring patterns observed by advisors that may harden later         | Any domain advisor or specialist agent | Mature entries promoted into a convention via a normal REQ.     |

Conventions stay authoritative. ADRs record decisions. Proposed-conventions records candidates.

## Lane 1: Architecture Decision Records (`docs/decisions/`)

### When to write an ADR

A REQ produces an ADR when it makes a decision that:

- Locks in a choice future readers will not understand from the code alone (e.g. "we picked library X over library Y because of the auth helper").
- Sets a tradeoff that future REQs need to respect (e.g. "we accepted no SSR for the admin tree because of session-token size").
- Reverses or supersedes a previous decision (e.g. "we are migrating off the old data store for write paths").

A REQ does NOT produce an ADR when it is a routine bug fix, a refactor inside an existing decision, or a docs-only change.

### Filename and structure

Files live at `docs/decisions/NNNN-<kebab-title>.md` where `NNNN` is the next zero-padded sequence number. Pick the next number from the highest existing `docs/decisions/[0-9][0-9][0-9][0-9]-*.md` plus one (`index.md` is generated and not an ADR).

Required structure (OKF 0.2 front matter, body under 20 lines; schema and field meanings in `.claude/conventions/continuity-protocol.md`):

```markdown
---
type: Decision Record
title: "NNNN: <decision, imperative>"
description: <one sentence>
status: stable
date: YYYY-MM-DD
supersedes: []
generated: {by: <agent or human id>, at: <ISO8601>}
tags: []
---
## Context

<2-5 sentences: the situation forcing the decision. Constraints, prior state, what triggered the call.>

## Decision

<1-3 sentences: what was decided. Imperative voice. No hedging.>

## Alternatives

- **<option>**: <why rejected in one line>

## Consequences

- <positive, negative, and tradeoffs accepted>
```

There is no Status line. Effective status (accepted or superseded) is computed, never written: `scripts/adr-index.sh` regenerates `docs/decisions/index.md` with one line per ADR and marks an ADR superseded when a later ADR lists it in `supersedes`.

### Authoring rules

- **Only `<pack>-doc-writer` writes ADRs.** Other agents can recommend an ADR in their summary; doc-writer drafts during the doc phase of `/do-work-run`.
- **Immutable once committed.** Never edit, rename, or delete a committed ADR, not even to mark it superseded. To change a decision, write a new ADR whose `supersedes` lists the old number(s), then run `scripts/adr-index.sh` to regenerate `docs/decisions/index.md`. The pre-commit hook rejects modified ADRs and a stale index.
- **Bootstrap exception.** ADRs 0001-0003 recording the scaffold install may be written by the installing agent; after bootstrap only `<pack>-doc-writer` writes ADRs.
- **Self-contained.** A reader two years later must be able to understand the decision without the originating REQ open. Restate context in the ADR body.
- **No ADR for guideline changes.** If the decision is "we will always use X for Y from now on", that is a convention edit, not an ADR.

### Promotion of an ADR pattern

An ADR is the record of a decision, not a request to change conventions. If the decision encodes a project-wide rule that future work must honour, the doc-writer also drops a paired entry in `do-work/proposed-conventions/` so a curator review can fold the rule into the actual convention.

## Lane 2: Proposed Conventions (`do-work/proposed-conventions/`)

### When to write a proposal

A domain advisor or specialist agent (see `.claude/agents/` for this project's roster) writes a proposal when:

- The same pattern appears in advice for **two or more REQs** within the same advisor's domain. Single-occurrence observations stay in the advice brief.
- A doc-writer or implementer asks for one off the back of an ADR.

The advisor never writes a proposal speculatively. Two real occurrences is the floor.

### Filename and structure

Files live at `do-work/proposed-conventions/<kebab-title>.md`. No sequence number - title is the key.

If a proposal already exists for the pattern, **bump it** rather than create a new one. Add an Occurrence line and increment Maturity.

Required structure:

```markdown
# Proposed: <pattern title>

- First seen: YYYY-MM-DD
- Last seen: YYYY-MM-DD
- Originating REQs: REQ-AAA, REQ-BBB, ...
- Author(s): <advisor role(s)>
- Maturity: 1 | 2 | 3
- Target convention: <filename in .claude/conventions/, or "new" if it would be a new file>

## Pattern

<one paragraph: the recurring pattern in concrete terms>

## Why it should harden into a convention

<one paragraph: what breaks if it stays informal; how often it has actually shown up>

## Suggested convention edit

<draft text, or pointer to the section of the target convention to amend>

## Occurrences

- YYYY-MM-DD - REQ-AAA - <one-line context>
- YYYY-MM-DD - REQ-BBB - <one-line context>
```

### Maturity ladder

- **1** - First written observation. Patterns at this level are advisory only; future agents should not treat them as binding.
- **2** - Second independent occurrence logged. The pattern is real but may still be coincidence. Convert advisor advice to "consider X" but not "do X".
- **3** - Third independent occurrence OR an explicit promotion request from a doc-writer/implementer. Ready for curator review.

Never skip levels. Each occurrence is a separate REQ with the pattern surfacing in real work.

### Promotion

Promotion is a deliberate human (or curator-agent) act, not automatic. The flow:

1. A proposal reaches Maturity 3.
2. Orchestrator surfaces it in the loop summary (see "Flagging" below).
3. The user (or a future curator agent) opens a REQ titled `convention: promote <pattern title>`.
4. That REQ's `<pack>-implement` edits the target convention; `<pack>-doc-writer` deletes the proposal file in the same commit.
5. Resulting commit message: `docs(convention): promote <pattern title> from proposed to <filename>`.

Mature proposals that the user rejects after review get edited to `Maturity: 0 - rejected, see REQ-NNN` and stay in place as a tombstone so the same pattern does not re-emerge silently.

## Flagging - how the orchestrator sees these

Every agent that writes to either lane MUST flag it in its return summary using this exact shape so the main session can spot it without reading the artefact:

```text
Knowledge Artefacts:
- ADR: docs/decisions/NNNN-<title>.md (new | superseding ADR-MMMM)
- Proposed convention: do-work/proposed-conventions/<title>.md (new | bumped to maturity N)
```

Absent that section, the agent declares "Knowledge Artefacts: none." in its summary.

The orchestrator's loop summary at `do-work/summaries/do-work-run-<date>.md` aggregates these into a top-level `## Knowledge Artefacts This Run` section so a single read tells you what landed and what reached promotion.

## Path restrictions reminder

- Only `<pack>-doc-writer` (this project's doc-writer agent) may write to `docs/decisions/**`.
- Only this project's domain advisor / specialist agents (if any are defined) may write to `do-work/proposed-conventions/**`. Other agents must read-only.
- Neither lane may modify `.claude/conventions/**` directly. Convention edits go through a normal REQ owned by `<pack>-implement`.

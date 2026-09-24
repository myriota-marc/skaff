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

<2-5 sentences. The situation forcing the decision. A reader two years from now must understand it without the originating REQ open.>

## Decision

<1-3 sentences. What was decided. Imperative voice. No hedging.>

## Alternatives

- **<option>**: <why rejected in one line>

## Consequences

- <positive, negative, and tradeoffs accepted>

<!--
Authoring rules (see .claude/conventions/knowledge-protocol.md and continuity-protocol.md):
- Filename: docs/decisions/NNNN-<kebab-title>.md, NNNN the next zero-padded number. Body under 20 lines.
- Immutable once committed. To change a decision, write a new ADR listing the old number in `supersedes`, then run scripts/adr-index.sh. No Status line: effective status is computed in docs/decisions/index.md.
- Only this project's doc-writer (<pack>-doc-writer) writes ADRs after bootstrap. Name the originating REQ in Context.
- Commit with an `ADR: NNNN` trailer. Flag in the agent's return summary under Knowledge Artefacts.
-->

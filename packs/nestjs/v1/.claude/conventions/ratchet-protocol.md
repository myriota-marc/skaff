# Ratchet Protocol

A quality ratchet that measures code on every approved REQ and refuses to let scores regress. Derived from the SkillTest harness. Enforced by the `ratchet` agent, applied after `reviewer` returns Approve and before `git-workflow` commits.

The ratchet makes one promise: scores can stay flat or go up. They cannot silently go down.

## The Eight Dimensions

Every ratchet evaluation scores the codebase against these dimensions. Each dimension produces a float between 0.0 and 1.0.

| Dimension | What it measures |
| --------- | ---------------- |
| `parse_check` | TypeScript parse and type-check health. Binary signal. |
| `lint` | ESLint and project lint violations relative to changed lines and file count. |
| `complexity` | Class and method size, injected-dependency count, and nesting depth across modified providers and controllers. |
| `structure` | Module boundaries, DI hygiene, layering, and file placement consistency. |
| `dead_code` | Unused exports, unreferenced providers, unreachable branches, and orphaned files introduced by the change. |
| `test_coverage` | Line and branch coverage across modified providers, controllers, guards, pipes, and filters. |
| `doc_quality` | TSDoc completeness on exported APIs plus markdown integrity. |
| `security` | Validation at the request boundary, guard coverage on new routes, secret and config handling, parameterised queries, and dependency advisories. |

Each dimension is **N/A-aware** - when a dimension genuinely cannot be scored (for example, coverage tooling or a dead-code analyser is not configured), the score is recorded as `null` and dropped from the composite weighted average rather than penalised as zero.

## Composite Score

```text
composite = weighted_mean(scores_excluding_null)
```

Default weights (tunable per project via `ratchet.conf`):

```text
parse_check     1.0    # binary - if it fails, composite is 0
lint            1.0
complexity      1.0
structure       1.5    # emphasised - module boundaries and DI hygiene
dead_code       0.5    # noisy; half weight
test_coverage   1.5    # emphasised
doc_quality     1.0
security        1.5    # emphasised - a backend owns the trust boundary
```

`parse_check` is a gate, not a weight. If `parse_check < 1.0`, the composite is 0 regardless of other scores. No lint score can rescue a file that does not parse.

## Baselines

Every run produces a scoreset. Scoresets are stored at `do-work/ratchet/baselines.jsonl` as one JSON object per line, append-only:

```json
{"req": "REQ-018", "timestamp": "2026-04-24T10:33:00Z", "scope_hint": "broad", "files_changed": 8, "lines_changed": 247, "composite": 0.8742, "dimensions": {"parse_check": 1.0, "lint": 0.84, "complexity": 0.93, "structure": 0.87, "dead_code": 0.98, "test_coverage": 0.76, "doc_quality": 0.89, "security": 0.88}}
```

The current baseline is the **most recent entry**. History is preserved for audit and regression detection.

## The Graduated Kept Bar

The cost of accepting a change scales with the baseline composite. The higher the score, the harder it is to keep a small improvement. This stops the ratchet gaming itself at high scores.

The bar also **scales with change scope**. A focused one-file fix should not need three dimensions improving to pass. Scope is objectively derived, not agent-claimed.

### Scope Hint

`scope_hint` is computed from `git diff --stat HEAD` on the REQ's branch:

| Scope hint | Derivation |
| ---------- | ---------- |
| `focused` | 3 or fewer files changed, and fewer than 100 lines added+removed |
| `broad` | Anything else |

The ratchet agent computes this, does not accept the value from any other agent, and records it in the `## Ratchet` section. A focused REQ that touches 9 files is treated as `broad` regardless of the implementer's intent - that is the correct outcome, and the signal to either split the REQ or accept the broader rigor.

### Kept Bar by Band and Scope

| Current composite | `focused` scope | `broad` scope |
| ----------------- | --------------- | ------------- |
| 0.00 - 0.69 | Composite does not decrease. | Composite does not decrease. One dimension must improve. |
| 0.70 - 0.84 | Composite does not decrease. No dimension regresses beyond threshold. | Composite does not decrease. Two dimensions improve. No dim regresses by > 0.02. |
| 0.85 - 0.92 | Composite does not decrease. At least one dimension improves. External validation passes. | Composite increases by >= 0.005. Three dims improve. Zero regressions. External validation passes. |
| 0.93 and above | Composite does not decrease. At least one dimension improves. External validation passes. Override required in REQ. | Composite increases by >= 0.005. Three dims improve. Zero regressions. External validation passes. Override required in REQ. |

A "regression" means any dimension dropping below its previous baseline value, not below an absolute threshold.

The focused column is more permissive because focused changes have less opportunity to improve many dimensions simultaneously. A bugfix that touches one service method legitimately cannot improve structure and complexity and test_coverage all at once. Requiring it to do so forces either scope creep or ratchet override.

### Saturated Dimensions (Held at Max)

A mature codebase can have most dimensions already at 1.0. Those dimensions cannot improve, so without this rule the "N dims improve" and "+0.005 composite" requirements become unreachable and every clean change needs an override. The rule below is part of the bar, not a widening of it.

- **Held at max.** A scored dimension that is 1.0 on the baseline and 1.0 on this run. N/A dimensions and dimensions appearing this run (see Dimension Appearance) are never held at max. A held-at-max dimension that drops below 1.0 is a regression.
- **Improving-dimension count.** Wherever a row requires N dimensions to improve (including "at least one"), count improved dimensions plus held-at-max dimensions.
- **Composite delta cap.** "Composite increases by >= 0.005" becomes "increases by >= min(0.005, 1.0 minus baseline composite)".
- **Held-at-max pass.** When held-at-max dimensions alone meet the row's dimension count, there are zero regressions, and the composite does not decrease, the change is Kept: the composite delta requirement is waived and, in the 0.93 and above band, no override is required. External validation still runs wherever the row requires it, and a failure still Rejects.
- **Strict otherwise.** Scope, regression, dimension disappearance and external validation rules are unchanged. A change that relies on improved dimensions to meet the count still needs the (capped) composite delta, and still needs the override in the 0.93 and above band.
- **Record it.** The `## Ratchet` section lists `Held at max: <dims>` and names the clause applied (count, cap, or held-at-max pass).

Worked example (seven scored dimensions, broad scope, 0.93 and above band):

| Case | Baseline | This run | Old bar | New bar |
| ---- | -------- | -------- | ------- | ------- |
| A | 0.9775; five dims at 1.0, two at 0.935 and 0.94 | Same values; composite 0.9775; reviewer Approve; external validation passes | Rejected: +0.005 and three improving dims are unreachable, override needed | Kept: five held at max >= three, zero regressions, composite held, so held-at-max pass; no override |
| B | As A | One of the two lower dims drops 0.94 to 0.93 | Rejected | Rejected: a regression, the held-at-max pass needs zero |
| C | 0.9975; two dims at 1.0 | Two held at max plus one improved; composite 0.9990 | Rejected unless +0.005, which exceeds the 0.0025 headroom | Count met (2 + 1 = 3); delta needed is min(0.005, 0.0025) = 0.0025, and +0.0015 falls short, so Rejected; with composite 1.0000 it passes the bar but still needs the override, since held-at-max alone (2) is below 3 |

## External Validation

At composite >= 0.85, the ratchet must dispatch an independent reviewer pass before accepting the change. This is a second `reviewer` invocation with a different seed and a prompt that explicitly does **not** include the implementing agent's scores or self-assessment - only the diff, the REQ, and the dimension definitions.

The adversarial prompt snippet, scope rules, and what-to-exclude list live in [`external-validation.md`](./external-validation.md). The ratchet agent prepends that snippet to its dispatch brief when invoking the external validator.

The external reviewer returns a pass or fail on the new scoreset. If it fails, the change is rejected even if the numbers look good. The purpose is to stop the implementing agent grading its own homework.

External validation is configurable via `ratchet.conf`:

```text
external_validation_after_composite = 0.85
```

## N/A Handling

A dimension is N/A when:

- No tooling exists to measure it.
- The change did not touch files relevant to the dimension.
- The dimension is explicitly disabled in `ratchet.conf`.

N/A dimensions are recorded as `null` in the scoreset. They are dropped from the composite weighted average. They cannot improve and they cannot regress - they simply do not participate.

An agent cannot mark a dimension N/A to avoid a low score. If the dimension was measurable on the previous run and is not on this run, the ratchet treats that as suspicious and reports it as a **dimension disappearance**, which the reviewer must explain before the change can proceed.

## Dimension Appearance

A dimension appears when it was `null` on the previous baseline and has a real value on the current run. This happens when tooling is added mid-project - for example, REQ-003 wires `ts-prune` into the lint step and `dead_code` goes from `null` to `0.88`.

Rules for the run that introduces a dimension:

- The dimension's value is recorded in the scoreset as a real number.
- The dimension does **not** count as improvement, regression, or held for that run. It is neutral.
- The `## Ratchet` section records an `Appearance:` line naming the dimension and its initial value.
- Subsequent runs baseline against the initial value and apply normal improvement, regression, and threshold rules.

This prevents two failure modes: treating a new dimension as a win and treating it as a regression against `null`.

## Honesty Mechanisms

Three mechanisms keep the ratchet from gaming itself:

1. **Graduated kept bar.** Higher scores demand broader improvement. A single tooltip cannot graduate a feature from 0.87 to 0.875.
2. **External validation.** At high scores, a second independent reviewer pass with no visibility into the implementing agent's scores.
3. **Baseline transparency.** Every scoreset is committed to `baselines.jsonl`. A regression is not a policy call - it is a visible history.

These mechanisms must not be silently bypassed. An agent that disables any mechanism must flag it in the REQ's `## Ratchet` section with justification.

## Ratchet Block in the REQ

Every ratcheted REQ gets a `## Ratchet` section appended before archive. Written by the `ratchet` agent. Not skill-owned; agent-owned.

```markdown
## Ratchet

**Baseline composite (pre-change)**: 0.8742
**New composite**: 0.8815
**Delta**: +0.0073
**Scope**: broad (8 files, 247 lines changed)
**Held at max**: <dims at 1.0 on baseline and this run, or none>
**Kept criterion**: 0.85-0.92 / broad - requires +0.005 composite, 3 dims improving, 0 regressions, external validation
**Kept**: Yes

### Dimensions

| Dimension | Before | After | Delta | Status |
| --------- | ------ | ----- | ----- | ------ |
| parse_check | 1.0000 | 1.0000 | 0.0000 | Held |
| lint | 0.8400 | 0.8600 | +0.0200 | Improved |
| complexity | 0.9300 | 0.9400 | +0.0100 | Improved |
| structure | 0.8700 | 0.8750 | +0.0050 | Improved |
| dead_code | 0.9800 | 0.9800 | 0.0000 | Held |
| test_coverage | 0.7600 | 0.7800 | +0.0200 | Improved |
| doc_quality | 0.8900 | 0.8900 | 0.0000 | Held |
| security | 0.8800 | 0.9000 | +0.0200 | Improved |

Status values: `Improved`, `Held`, `Regressed`, `Appeared`, `Disappeared`, `N/A`.

**Appearance** (used when a dimension went from `null` to a real value this run):

```text
Appearance: dead_code = 0.8800 (was null)
```

Appeared dimensions get `Appeared` in the Status column with `null` in the Before column. They do not contribute to improvement or regression counts for this run.

### External Validation

Status: Passed
Reviewer notes: <brief>

### Baseline Written

`do-work/ratchet/baselines.jsonl`
```

If `Kept: No`, the ratchet agent returns a blocking verdict to the main session and the REQ loops back to `nestjs-implement` with the failing dimensions as the task brief. The archive step does not run until the ratchet keeps.

## Non-Regression Commitment

Once a dimension crosses a threshold, it cannot drop back below it on subsequent REQs without explicit justification:

- **Implicit thresholds**: `parse_check = 1.0`, `doc_quality >= 0.85`, `test_coverage >= 0.70`, `security >= 0.85`.
- **Project thresholds**: defined in `ratchet.conf` per project.

Dropping below an implicit or project threshold triggers the same blocking verdict regardless of composite direction.

## What Not To Do

- Do not edit `baselines.jsonl` by hand. It is append-only.
- Do not mark a dimension N/A to dodge a low score.
- Do not run the external validator yourself as the implementing agent - the main session dispatches it.
- Do not treat the graduated bar as advisory. It blocks archive.
- Do not widen the kept criterion in `ratchet.conf` to force a stuck REQ through. Fix the code or escalate.

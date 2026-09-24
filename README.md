# Claude Agent Scaffold

A production-grade agent harness for AI coding tools. Takes natural-language requests to "add a feature" or "fix a bug", captures them as structured work items, runs them through a delegated pipeline of specialist sub-agents (scout, implement, document, review, ratchet quality-gate, commit), and archives them as self-contained, auditable units. Works with Claude Code, GitHub Copilot (CLI and cloud agent), Gemini CLI, Cursor, Windsurf, Aider, OpenHands, and Continue.

Packs per language/stack. Ships `csharp` (.NET 9+) and `appsheet` (Google AppSheet + Apps Script + Sheets governance) at v2 (maintained) with v1 (frozen), plus `python`, `go`, `nextjs`, `gcli`, `react`, `vue3-vite`, `html-css`, `designer`, `appscript`, `sveltekit`, `terraform`, and `nestjs` at v1 (maintained). Skaff installs a unified directory tree that works across the major AI coding tools while preserving the Claude Code `/do-work-run` workflow where supported. Contract for building new packs in [packs/README.md](./packs/README.md). Standardisation checklist in [packs/TEMPLATE-CHECKLIST.md](./packs/TEMPLATE-CHECKLIST.md).

## Table of contents

- [What this is](#what-this-is)
- [What this is not](#what-this-is-not)
- [Use cases](#use-cases)
- [Install](#install)
- [Quick start](#quick-start)
- [Architecture](#architecture)
- [Multi-LLM support](#multi-llm-support)
- [Data flows](#data-flows)
- [Agent roster](#agent-roster)
- [Conventions](#conventions)
- [The ratchet](#the-ratchet)
- [Safety mechanisms](#safety-mechanisms)
- [Extending](#extending)
- [Roadmap](#roadmap)
- [FAQ](#faq)

## What this is

A drop-in directory tree - `CLAUDE.md`, `GEMINI.md`, `AGENTS.md`, `.claude/`, `.github/`, `.cursor/`, `.windsurf/`, `.continue/`, `do-work/` - that turns major AI coding tools into a repeatable engineering pipeline. Skaff installs one unified directory tree that works natively across Claude Code, GitHub Copilot, Gemini CLI, Cursor, Windsurf, Aider, OpenHands, and Continue. Not a framework, not an MCP server, not an app. Just markdown files and a few YAML/TOML templates that the target tools read and act on.

Core promises:

- **Capture is fast.** Describing a feature takes seconds. Structuring it, verifying coverage, planning it, and routing it is the scaffold's job.
- **Execution is delegated.** The orchestrator does not write code. Specialist sub-agents do, each with isolated context windows. Context does not bloat.
- **Quality does not regress.** Every approved change is scored across seven dimensions against an append-only baseline. A change that reduces quality is refused.
- **Human review stays required.** Git-workflow opens PRs. Branch protection blocks merges without human approval. Automation goes up to the merge gate, not through it.

## What this is not

- Not a replacement for human judgement on architectural decisions.
- Not a substitute for real tests. The ratchet measures coverage; it does not vouch for test quality.
- Not an auto-merge tool. Every PR still goes through human review.
- Not one-size-fits-all out of the box. Pick the closest pack, then tune the shipped agents, skills, and instructions for your repo.

## Use cases

Works well for:

- **Greenfield MVPs in .NET.** Bootstrap a solution, then drive feature work through `do work` capture and `do work run` processing. Each REQ becomes an atomic commit.
- **Maintaining existing services.** Feature additions, bugfixes, and refactors with a built-in quality ratchet so the codebase does not drift downward.
- **Documentation passes.** The `csharp-doc-writer` agent audits public APIs, adds XML doc comments, updates markdown. Focused REQ tier in the ratchet accommodates docs-only changes.
- **Dependency upgrades.** Scout maps what uses what, implement applies upgrades surgically, ratchet catches any regression before merge.
- **Multi-REQ features.** Capture a batch with `do work <long prompt>`, the skill splits into REQs linked to a single UR (user request), the orchestrator drains them sequentially with state preserved across process restarts.

Does not fit:

- **Ambiguous research spikes.** If the requirements genuinely cannot be stated, the plan-verify gate will escalate repeatedly. Use a conversational Claude Code session for exploration, then capture concrete REQs afterward.
- **Architecturally-invasive rewrites.** The ratchet's graduated kept bar rejects large multi-dimension regressions. For deliberate architectural change that trades short-term scores for long-term gain, use the Override escalation option and document the trade.
- **Broad content workflows.** The scaffold now ships frontend and design-system packs, but it still does not target content-only or open-ended research workflows.

## Install

Run the installer, point it at an empty directory or an existing repo.

**Windows / PowerShell:**

```powershell
.\install.ps1 -NewProjectDir C:\repos\MyService
.\install.ps1 -NewProjectDir C:\repos\MyApp -Pack appsheet
.\install.ps1 -NewProjectDir C:\repos\MyScript -Pack appscript
.\install.ps1 -NewProjectDir C:\repos\MyApp -Pack csharp@v1 -Force
```

**Linux / macOS / Git Bash:**

```bash
./install.sh /path/to/my-project
./install.sh /path/to/my-app --pack appsheet
./install.sh /path/to/my-script --pack appscript
./install.sh /path/to/my-app --pack csharp@v1 --force
```

Default pack is `csharp`. Pinning: `<pack>@<version>`. Full pack list and version manifests under [packs/](./packs/).

| Pack | Versions | What it targets |
| --- | --- | --- |
| `csharp` | v2 (maintained), v1 (frozen) | .NET 9+ projects |
| `appsheet` | v2 (maintained), v1 (frozen) | Google AppSheet + Apps Script + Sheets |
| `python` | v1 (maintained) | Python 3.12+ with uv, ruff, pytest |
| `go` | v1 (maintained) | Go 1.22+ with modules, go test, and golangci-lint |
| `nextjs` | v1 (maintained) | Next.js 14 + TypeScript on Cloud Run |
| `gcli` | v1 (maintained) | Python agentic CLI + Chrome MV3 + Gemini |
| `react` | v1 (maintained) | React 18+ + TypeScript 5+ + Vite |
| `vue3-vite` | v1 (maintained) | Vue 3 + TypeScript 5+ + Vite |
| `html-css` | v1 (maintained) | HTML5/CSS3/vanilla JS + Playwright |
| `designer` | v1 (maintained) | Design systems + Storybook + CSS tokens |
| `appscript` | v1 (maintained) | Google Apps Script V8 + clasp |
| `sveltekit` | v1 (maintained) | SvelteKit 2+ + Svelte 5 + TypeScript 5+ + Vite |
| `terraform` | v1 (maintained) | Terraform 1.7+ / OpenTofu-compatible HCL2 + tflint + checkov |
| `nestjs` | v1 (maintained) | NestJS 10+ + TypeScript 5+ backend services on Node 20+/22+ with yarn |

The installer is idempotent. Existing files are preserved unless `-Force` or `--force` is supplied. Only `common/` and `packs/<pack>/<version>/` are copied; repo-root files and other packs are out of scope by construction. `common/` is copied first and the pack overlay second, sharing one `-Force` flag: without it, a file present in both wins by first-writer (`common/`), not the pack; with it, the pack (copied second) wins. See [INSTALL.md](./INSTALL.md#what-gets-installed) for detail.

### After install

1. Review `CLAUDE.md` and `.claude/conventions/`.
2. For GitHub Copilot, `.github/copilot-instructions.md` is already installed.
3. For Gemini CLI, `GEMINI.md` is already installed.
4. For Cursor, `.cursorrules` and `.cursor/rules/` are already installed.
5. For Windsurf, `.windsurfrules` and `.windsurf/rules/` are already installed.
6. For Aider, `.aider.conf.yml` is already installed.
7. Confirm the agent roster in `.claude/agents/` and tool-specific equivalents in `.gemini/skills/`, `.agents/skills/`, `.github/agents/`.
8. Optional: tune `do-work/templates/ratchet.conf.template` and copy to `ratchet.conf` at repo root.
9. Optional: copy `do-work/templates/.gitleaks.toml.template` to `.gitleaks.toml` for secret-scan allowlists.
10. Optional: copy `do-work/templates/ci/ratchet-gate.yml.template` to `.github/workflows/ratchet-gate.yml` for CI-side PR gating. See `do-work/templates/ci/README.md` for branch protection settings.
11. Commit:

   ```bash
   git add .
   git commit -m "chore: bootstrap claude agent scaffold"
   ```

12. Activate the continuity layer: `sh scripts/bootstrap.sh`, switch to a branch, then `sh scripts/gate.sh A1`. See [INSTALL.md](./INSTALL.md) "After install".

### Prerequisites

- **Claude Code** CLI - full agent workflow with sub-agent spawning.
- **GitHub Copilot** (CLI, VS Code, cloud agent) - reads `CLAUDE.md`, `GEMINI.md`, and `AGENTS.md` natively; agents in `.github/agents/`.
- **Gemini CLI** - reads `GEMINI.md`; skills in `.gemini/skills/`.
- **Cursor** - reads `.cursor/rules/` and `.cursorrules`.
- **Windsurf** - reads `.windsurf/rules/` and `.windsurfrules`.
- **Aider** - reads `AGENTS.md` via `.aider.conf.yml`.
- **OpenHands** - reads `AGENTS.md`; skills in `.agents/skills/`.
- **Continue** - reads `.continue/rules/`.
- **Pack-specific toolchains** still apply - for example .NET SDK 9.x and `dotnet format` for `csharp`.
- **git** with `gh` CLI remains recommended for the git-workflow agent. **gitleaks** is still strongly recommended for secret scanning.
- **Continuity layer** - `sh`, `jq`, `vale` and `gitleaks` at the versions pinned in the installed `.tool-versions` (`scripts/bootstrap.sh` checks them). Skip the layer with `--no-continuity`.

## Quick start

Inside Claude Code, in the target project:

```text
do work I need a webhook endpoint at POST /orders that accepts a JSON
payload, persists via EF Core, returns 202 with a correlation id, and is
idempotent on orderId.
```

The `do` skill action captures this as one or more `REQ-NNN-pending.md` files in `do-work/` plus a `user-requests/UR-NNN/input.md` preserving your verbatim prompt. `verify-request` auto-appends a `## Verification` coverage map to each REQ.

```text
do work run
```

The orchestrator drains the queue. For each REQ: acquire queue lock, triage, scout (if medium/complex), plan (inline in REQ), verify plan, implement, document (if complex), review, ratchet, git-workflow commits and opens a PR, archive. Concurrent `do work run` refuses to start while the lock is held.

At the end, `cleanup` moves completed UR folders to `archive/UR-NNN/` as self-contained units.

## Architecture

### Folder layout (installed target, using `csharp` pack as example)

```text
<project-root>/
├── CLAUDE.md                           project-wide behavioural rules (from pack template)
├── .claude/
│   ├── .pack                           pack identity sentinel (pack, version, commit)
│   ├── agents/                         sub-agent definitions
│   └── conventions/                    read-before-acting references
├── do-work/                            work queue, runtime state
│   ├── REQ-NNN-pending.md              queue entries
│   ├── user-requests/UR-NNN/           verbatim user inputs + assets
│   ├── working/                        at most one REQ mid-flight
│   ├── scout/                          scout findings briefs
│   ├── ratchet/baselines.jsonl         append-only quality scores
│   ├── summaries/                      agent and loop summaries
│   ├── archive/                        completed work (immutable)
│   └── templates/                      starter files (generic REQ/UR + pack specifics)
└── src/, tests/                        your code
```

### Scaffold source layout (this repo)

```text
Skaff/
├── CLAUDE.md, README.md, INSTALL.md    docs (never installed)
├── install.sh, install.ps1             installers (never installed)
├── common/                             shared overlay copied first
│   ├── AGENTS.md, GEMINI.md
│   ├── .github/, .continue/            shared multi-LLM instructions
│   ├── .cursorrules, .windsurfrules
│   ├── .aider.conf.yml
│   ├── .claude/conventions/commit-style.md, knowledge-protocol.md, continuity-protocol.md
│   └── do-work/                        generic templates + runtime dir skeletons + proposed-conventions/
├── continuity/                         continuity layer: files/ (hooks, scripts, Vale), merge/, templates/STATE.md.template
└── packs/
    ├── README.md, SHARED-NOTES.md      pack contract, backport checklist
    ├── csharp/PACK.md + v1/, v2/       .NET 9+ pack, version manifest + overlay
    ├── appsheet/PACK.md + v1/, v2/     AppSheet/GAS/Sheets pack
    ├── python/PACK.md + v1/            Python 3.12+ pack, uv + ruff + pytest
    ├── go/PACK.md + v1/                Go 1.22+ pack, modules + go test + golangci-lint
    ├── nestjs/PACK.md + v1/            NestJS 10+ backend pack, yarn + Jest
    ├── nextjs/PACK.md + v1/            Next.js 14 + TypeScript on Cloud Run
    ├── gcli/PACK.md + v1/              Python agentic CLI + Chrome MV3 + Gemini
    ├── react/PACK.md + v1/             React 18+ + TypeScript 5+ + Vite
    ├── vue3-vite/PACK.md + v1/         Vue 3 + TypeScript 5+ + Vite
    ├── html-css/PACK.md + v1/          HTML5/CSS3/vanilla JS + Playwright
    ├── designer/PACK.md + v1/          Design systems + Storybook + CSS tokens
    ├── appscript/PACK.md + v1/         Google Apps Script V8 + clasp
    ├── sveltekit/PACK.md + v1/         SvelteKit 2+ + Svelte 5 + TypeScript 5+ + Vite
    └── terraform/PACK.md + v1/         Terraform 1.7+ / OpenTofu-compatible HCL2 + tflint + checkov
```

### Design principles

1. **File-system as state.** Every piece of context - user input, plans, scoresets, counters - lives on disk in markdown or JSON. No in-memory state between agent invocations. Process restart loses nothing.
2. **Separation of concerns.** Each agent has one job. Orchestrator delegates; scout maps; implement codes; reviewer grades; ratchet gates; git-workflow commits. Agents never claim each other's responsibilities.
3. **Explicit ownership.** Every file section has a named owner in the Skill Action Boundaries table of `do-work-protocol.md`. No agent writes another agent's section.
4. **Immutability past the gate.** Once a REQ enters `working/` or `archive/`, its body is immutable except for append-only sections owned by the pipeline (loop counters, ratchet block). Modifications require a new addendum REQ.
5. **Context budget discipline.** Sub-agents get at most 2000 tokens of verbatim content per dispatch brief. Beyond that, file paths. Agents re-read from disk inside their isolated contexts.
6. **Honesty mechanisms.** The ratchet uses graduated kept bar, external validation at composite >= 0.85, and append-only baselines. All three are defeat-resistant by design.

### Isolation model

```text
                   ┌──────────────────────────────────────────┐
                   │           claude.ai main session         │
                   │  (user conversation, never touches code) │
                   └──────────────────┬───────────────────────┘
                                      │
                              do work run
                                      │
                                      ▼
                   ┌──────────────────────────────────────────┐
                   │           orchestrator agent             │
                   │  (own context window, delegates only)    │
                   └──┬──────┬──────┬──────┬──────┬──────────┘
                      │      │      │      │      │
           ┌──────────┘      │      │      │      └──────────┐
           ▼                 ▼      ▼      ▼                 ▼
      ┌────────┐       ┌─────────┐ ┌──┐ ┌──────┐        ┌───────┐
      │ scout  │       │implement│ │..│ │ratch.│        │  git  │
      │ (own   │       │(own ctx)│ │  │ │(own  │        │(own   │
      │ ctx)   │       │         │ │  │ │ ctx) │        │ ctx)  │
      └────────┘       └─────────┘ └──┘ └──────┘        └───────┘
```

Each sub-agent runs with its own system prompt, tool permissions, and context window. Summaries return to the orchestrator; full working state stays inside the sub-agent. The main user conversation never sees the bulk of the work.

## Multi-LLM support

Skaff generates instruction files for all major AI coding tools from a single install. Every target project ships:

| File / Directory | Tool |
| --- | --- |
| `CLAUDE.md` | Claude Code (primary), GitHub Copilot CLI |
| `GEMINI.md` | Gemini CLI, GitHub Copilot CLI |
| `AGENTS.md` | OpenHands, Aider, GitHub Copilot cloud agent |
| `.github/copilot-instructions.md` | GitHub Copilot Chat (VS Code, GitHub.com) |
| `.github/instructions/` | Copilot path-specific instructions |
| `.github/agents/` | GitHub Copilot custom agents (sub-agents) |
| `.cursorrules` | Cursor IDE (legacy format) |
| `.cursor/rules/` | Cursor IDE (current format, glob-aware) |
| `.windsurfrules` | Windsurf IDE (legacy format) |
| `.windsurf/rules/` | Windsurf IDE (current format) |
| `.windsurf/workflows/` | Windsurf slash-command workflows |
| `.gemini/skills/` | Gemini CLI sub-agent skills |
| `.agents/skills/` | OpenHands sub-agent skills |
| `.aider.conf.yml` | Aider CLI |
| `.continue/rules/` | Continue VS Code extension |

The behavioral guidelines (think before coding, simplicity first, surgical changes, goal-driven execution, house rules) are embedded in every file. Tool-specific capabilities (sub-agent spawning, skill activation, Copilot agent system) are configured for tools that support them.

**Note:** GitHub Copilot CLI reads `CLAUDE.md`, `GEMINI.md`, and `AGENTS.md` natively. Projects scaffolded with skaff are immediately compatible with Copilot CLI without any extra steps.

## Data flows

### Request capture flow

```text
User: "do work add dark mode to settings, also fix header alignment"
                          │
                          ▼
              ┌──────────────────────────┐
              │      do skill action     │
              └────────────┬─────────────┘
                           │
          ┌────────────────┼──────────────────┐
          ▼                ▼                  ▼
     UR-005/input.md   REQ-021-dark-mode  REQ-022-header-align
      (verbatim)        pending.md          pending.md
                          │                    │
                          └────────┬───────────┘
                                   ▼
                       ┌──────────────────────────┐
                       │   verify-request skill   │
                       └────────────┬─────────────┘
                                    │
                      ## Verification appended to each REQ
                      (coverage map, auto-fix gaps)
```

### Processing flow (per REQ)

```text
REQ-021-pending.md (do-work/)
       │
       ▼ orchestrator acquires do-work/.lock
       ▼ mv → do-work/working/REQ-021-in-progress.md
       │
       ▼ triage: simple | medium | complex
       │
       ▼ if medium|complex: delegate csharp-scout
       │     └─ writes do-work/scout/REQ-021-*-findings.md
       │
       ▼ delegate csharp-implement (plan-only mode)
       │     └─ writes ## Plan section
       │     └─ writes ## Plan Hash (SHA-256 drift anchor)
       │
       ▼ verify-plan skill action (auto)
       │     └─ appends ## Plan Verification (coverage map)
       │     └─ may edit ## Plan to close gaps
       │
       ▼ delegate csharp-implement (implement mode)
       │     └─ hash check vs ## Plan Hash, write Plan Delta if drift
       │     └─ writes src/ and tests/
       │     └─ dotnet build, test, format
       │     └─ commits on feature branch
       │     └─ writes do-work/summaries/REQ-021-implement.md
       │
       ▼ if complex|docs-in-scope: delegate csharp-doc-writer
       │
       ▼ delegate reviewer
       │   verdict: Approve | Request Changes | Escalate
       │     └─ Request Changes: bump counter, back to implement
       │     └─ Escalate: structured AskUserQuestion
       │
       ▼ delegate ratchet
       │   score 7 dimensions, compute scope_hint from git diff
       │   verdict: Kept | Rejected
       │     └─ Rejected: bump counter, back to implement
       │     └─ if composite >= 0.85: external validation (adversarial reviewer)
       │     └─ on Kept: append scoreset to baselines.jsonl
       │                 write ## Ratchet section to REQ
       │
       ▼ delegate git-workflow
       │     └─ secret scan (gitleaks preferred, regex fallback)
       │     └─ push, open PR, link issues
       │
       ▼ mv → do-work/archive/REQ-021-done.md
       │
       ▼ next REQ; on queue drain, cleanup runs, lock released
```

### Escalation flow

Triggered when: same blocking issue > 2 retries, total cycles > 5, reviewer returns Escalate, or no agent owns a failing phase.

```text
AskUserQuestion with 4 options:
  1. Override ratchet → orchestrator writes ## Override section → git-workflow
  2. Split REQ        → mv to archive/abandoned/, user re-captures
  3. Abandon REQ      → mv to archive/abandoned/, no re-capture
  4. Continue looping → cap += 3, resume review step
```

### Ratchet scoring flow

```text
Read tail -1 do-work/ratchet/baselines.jsonl → baseline
Run dotnet build, dotnet test, dotnet format, analyser warnings
Score 7 dimensions → new scoreset
Compute scope_hint from git diff --stat (focused | broad)
Compute composite (weighted, parse_check is a gate not a weight)

If baseline composite >= 0.85: dispatch reviewer as external validator
    (adversarial prompt from external-validation.md,
     no scoreset, no self-assessment visible)

Apply graduated kept bar by (composite band × scope_hint)
Check non-regression thresholds
If Kept: append scoreset to baselines.jsonl
         write ## Ratchet section to REQ
If Rejected: return Blocking Dimensions list to orchestrator
```

## Agent roster

| Agent              | Model   | Role                                                                 | Writes to                                   |
| ------------------ | ------- | -------------------------------------------------------------------- | ------------------------------------------- |
| orchestrator       | opus    | Drains the queue, delegates all work, owns state transitions only    | `do-work/.lock`, `working/`, `archive/`, `summaries/` |
| csharp-scout       | haiku   | Read-only dependency and usage mapping                               | `do-work/scout/`, `summaries/`              |
| csharp-implement   | sonnet  | Plan-only mode (writes plan + hash), implement mode (code + tests)  | `src/`, `tests/`, `working/` (Plan sections), `summaries/` |
| csharp-doc-writer  | sonnet  | XML doc comments, markdown documentation                             | `src/`, `tests/`, `docs/`, root `*.md`, `summaries/` |
| reviewer           | sonnet  | Approve / Request Changes / Escalate verdicts                        | `summaries/`                                |
| ratchet            | sonnet  | Seven-dimension quality gate, graduated kept bar, external validation | `do-work/ratchet/`, `working/` (## Ratchet), `summaries/` |
| git-workflow       | sonnet  | Commits, PRs, secret scanning, pre-commit hook                       | `.git/hooks/`, `.gitignore`, branches       |

## Conventions

Eight convention files in `.claude/conventions/`. Agents read specific ones before acting (declared in each agent's directive #1). Conventions are the load-bearing part of the scaffold - edit these to adapt the scaffold to your stack or team style.

| File                     | Read before...                                                                  |
| ------------------------ | ------------------------------------------------------------------------------- |
| `csharp-style.md`        | Writing or reviewing any C# code (naming, nullability, async, DI, XML docs)     |
| `markdown-style.md`      | Writing or editing any `.md` file (headings, fences, tables, admonitions)       |
| `commit-style.md`        | Writing commit messages, PR titles, or PR bodies (Conventional Commits)         |
| `do-work-protocol.md`    | Reading, writing, or moving any file under `do-work/`                           |
| `coverage-protocol.md`   | Running or interpreting verify-request or verify-plan (coverage formula, bands) |
| `external-validation.md` | Dispatching reviewer as an adversarial external validator at composite >= 0.85  |
| `ratchet-protocol.md`    | Scoring, keeping, or reviewing the `## Ratchet` section in a REQ                |
| `knowledge-protocol.md`  | Writing an ADR (`docs/decisions/`) or a proposed-convention entry (`do-work/proposed-conventions/`) |

`commit-style.md` and `knowledge-protocol.md` ship from `common/` and install identically into every pack; the other six are pack-specific overlay files.

## The ratchet

The quality gate runs between reviewer and git-workflow. Seven dimensions:

| Dimension        | What it measures                                                           |
| ---------------- | -------------------------------------------------------------------------- |
| `parse_check`    | Every source file parses without syntax errors (gate, not weight)          |
| `lint`           | Lint and analyser violations relative to changed files                     |
| `complexity`     | Cyclomatic and cognitive complexity on modified methods                    |
| `structure`      | Project layout, namespace hygiene, DI registration consistency             |
| `dead_code`      | Unreachable code, unused symbols, orphans introduced by the change         |
| `test_coverage`  | Line and branch coverage across modified projects                          |
| `doc_quality`    | XML doc completeness on public/protected members; markdown integrity       |

**Composite** = weighted mean of non-null dimensions. `parse_check < 1.0` zeros the composite.

**Graduated kept bar** scales with baseline composite *and* scope_hint:

- **focused** (<= 3 files changed, < 100 lines): relaxed bar, docs-only and bugfix REQs can land without broad multi-dim improvement
- **broad** (anything else): strict bar, higher bands require three dims improving and composite +0.005

scope_hint is computed from `git diff --stat`, not agent-claimed. A "focused" fix that touches 9 files is treated as broad.

**External validation** at composite >= 0.85: a second reviewer invocation with an adversarial prompt (from `external-validation.md`) that cannot see the scoreset or self-assessment. Correlated-failure research (arXiv 2603.25773, Dec 2025) shows same-distribution reviewers share failure modes; the adversarial prompt breaks that.

**Baselines** are append-only JSON lines at `do-work/ratchet/baselines.jsonl`. History is permanent and auditable. No agent rewrites the file.

**Overrides** land in an orchestrator-owned `## Override` section in the REQ when the user escalates. The ratchet block itself is never edited after write.

## Safety mechanisms

1. **Queue lock** at `do-work/.lock` prevents concurrent orchestrator runs from corrupting the queue. JSON format with pid/started_at/host. 2-hour staleness auto-clear. Shared across git worktrees because the queue is a shared resource.

2. **Plan drift check** - csharp-implement hashes the `## Plan` at end of plan-only mode. At start of implement mode, rehashes and compares. If verify-plan edited the plan mid-flight, a Plan Delta note is written so the reviewer can see what changed.

3. **Loop caps** - same-issue cap (>2 retries of the same blocking issue) and total cycles cap (>5 implement-review-ratchet cycles) both trigger structured escalation with four explicit user options.

4. **Immutability rules** - files in `working/` and `archive/` are immutable except for named append-only sections. Addendum REQs are the only way to modify an in-flight or completed request.

5. **Secret scanning** - gitleaks (150+ patterns, industry baseline) preferred, inline regex fallback when gitleaks is not installed. File-type blocklist rejects `.env`, `.pfx`, `*.pem`, etc. Runs in the versioned `.githooks/pre-commit` shipped by the continuity layer.

6. **CI-side gate** - `ratchet-gate.yml.template` workflow enforces build, test, format, CS1591, gitleaks, and baseline-composite-floor regressions on every PR. Auto-merge is deliberately not enabled.

7. **Continuity layer** - versioned git hooks and Claude Code hooks keep ADRs immutable, lint docs with Vale and OKF keys, enforce Conventional Commits without em or en dashes, block commits on main and hook bypass flags, and close work items only with `.gates/` evidence. `scripts/selftest.sh` proves the hooks. See `.claude/conventions/continuity-protocol.md`.

8. **Dispatch budget** - 2000-token cap on verbatim content in sub-agent dispatch briefs. Over that, file paths only; sub-agents re-read from disk inside their isolated contexts. Prevents context bloat at scale.

## Extending

### Build a new pack

The scaffold's pipeline is language-agnostic. The specialist agents live in packs.

1. `cp -r packs/csharp packs/<yourlang>` (or copy the pack closest to your stack).
2. Rename `<yourlang>/v1/` subdirs: agents (`csharp-*.md` -> `<yourlang>-*.md`) and the style convention (`csharp-style.md` -> `<yourlang>-style.md`).
3. Rewrite the renamed agents' directives, tool permissions, and ratchet signal mappings to match your build/test/lint tools.
4. Update `orchestrator.md`'s `Agent(...)` frontmatter and the agent-name references in `do-work-protocol.md`, `ratchet-protocol.md`, `external-validation.md`, and `CLAUDE.md.template`.
5. Tune `ratchet.conf.template` weights, thresholds, and `na_dimensions`.
6. Adjust `.gitleaks.toml.template` paths for your stack's test fixtures and examples.
7. Write `packs/<yourlang>/PACK.md` with the version manifest and target tool baseline.
8. Test: `./install.sh /tmp/scratch --pack <yourlang>` against a throwaway directory.
9. Update the top-level `INSTALL.md` and `README.md` pack tables.

See [packs/README.md](./packs/README.md) for the full pack contract and [packs/SHARED-NOTES.md](./packs/SHARED-NOTES.md) for which conventions should track across packs.

### Add a new agent

1. Write `.claude/agents/<new-agent>.md` with the standard sections: frontmatter (name, description, tools, model), Role, Inputs/Outputs/Handoff, Path Restrictions, Directives, Definition of Done.
2. Add a row to the Skill Action Boundaries table in `do-work-protocol.md`.
3. Wire the agent into the orchestrator's Processing Loop if it belongs in the main pipeline.

### Tune the ratchet

Copy `do-work/templates/ratchet.conf.template` to `ratchet.conf` at repo root. Adjust:

- Dimension weights
- `external_validation_after_composite` threshold
- Non-regression thresholds per dimension
- `na_dimensions` list if your project legitimately cannot score some dimensions

## Roadmap

### Near-term candidates (would fit a PR 3)

- **Risk-weighted coverage** - `test_coverage` currently treats all code equal. A dedicated critical-path annotation in the REQ body could weight coverage of flagged files higher.
- **Cross-REQ pattern library** - agents discover patterns during work (e.g. "this project uses Polly", "this service uses MediatR"). Currently re-discovered every REQ via scout. An append-only `do-work/patterns/` directory could persist.
- **Addendum enforcement** - a lightweight linter that fails the pipeline if an addendum REQ tries to alter the original's code intent, rather than layer on top.
- **Skip-verification honouring** - the `do` skill supports "skip verification" in prompts but no agent honours it. Wire through.

### Medium-term candidates

- **Agent-team mode** - Anthropic's experimental agent teams feature (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS) allows agents to communicate. Currently the orchestrator handles all coordination. Certain workflows (e.g. parallel doc audits across independent modules) could genuinely benefit from fan-out/fan-in.
- **Drift detection on conventions** - over 50+ REQs, a project's actual style may diverge from `csharp-style.md`. A periodic audit agent could flag when the convention no longer matches practice.
- **MCP tool integration** - the scaffold is pure-file. Connecting to project-management tools (Jira, Linear) via MCP would let REQs sync bi-directionally.
- **Metrics dashboard** - `baselines.jsonl` contains rich signal over time. A small static-site generator could plot composite, per-dimension scores, and reject rates over 100+ REQs.

### Long-term / speculative

- **Self-improving conventions** - the pattern library above, extended. After N REQs where a specific reviewer comment recurs, the scaffold suggests a convention update.
- **Additional packs** - Python, nextjs, html-css, designer, gcli, go, sveltekit, terraform, and nestjs ship at v1 (maintained). Rust remains open. See [packs/TEMPLATE-CHECKLIST.md](./packs/TEMPLATE-CHECKLIST.md) for the build steps.
- **Adversarial ratchet** - the current external validator uses a prompt-level adversarial stance. A stronger mechanism would actually run a different model family (e.g. GPT or Gemini) for the external validation pass, eliminating same-model correlated failure entirely.

### Deliberately not roadmapped

Six gaps from the original triage remain deferred and are unlikely to land soon:

- **Rollback if git-workflow runs pre-ratchet** - the pipeline order prevents this; the gap only exists if an operator rewires the loop.
- **Cleanup vs orchestrator race** - both are orchestrator-triggered; the documented invocation model precludes the race.
- **Custom subagent warnings from sshh.io research** - the Master-Clone architecture (main agent delegates to copies of itself rather than specialists) has merit, but would require rewriting the whole scaffold. Not on the table.

## FAQ

### Why not just let Claude Code's main agent do everything?

Context bloats. Four hours into a session, the main agent forgets decisions made in hour one and starts drifting from established patterns. Sub-agents with isolated contexts prevent this. The scaffold is specifically the "context discipline" pattern that heavy Claude Code users converge on.

### Why so much prose in the conventions?

LLMs follow detailed rules better than vague ones. A 50-line convention file encodes the tacit knowledge that would otherwise need to live in every prompt. Cost: some files look verbose. Benefit: agents behave consistently across hundreds of invocations.

### Can I use this without the ratchet?

Delete `.claude/agents/ratchet.md` and `ratchet-protocol.md`, remove the ratchet step from the orchestrator's Processing Loop, and skip the `ratchet-gate.yml` template. The scaffold still works as a capture-and-delegate pipeline without the quality gate. You lose the baseline regression protection.

### What if my team already uses GitHub Issues / Linear / Jira?

Nothing in the scaffold prevents layering on top. The `do` action still captures; you can then mirror `do-work/REQ-NNN-pending.md` into your tracker with a hook or CI job. Future MCP integration would automate this.

### Is this production-ready?

It's production-usable for a solo developer or a small team. The design deliberately avoids multi-user concurrency (the queue lock is single-writer) and has no secret-management story beyond gitleaks. For larger organisations with compliance requirements, treat this as a starting point, not a finished product.

### How do I contribute back?

This is a scaffold, not a hosted project. Fork it, adapt it, and share what you change. If you find a real bug in the delegated-agent pattern itself (not just a convention gap), the repository this comes from welcomes issues.

## Credits and further reading

Design borrows heavily from:

- Anthropic's Claude Code subagent documentation
- The `bladnman/do-work` skill (the capture/process/verify/cleanup action model)
- CodeScene's 2026 agentic coding patterns (coverage as regression signal)
- arXiv 2603.25773 "The Specification as Quality Gate" (correlated-failure research informing the external validation design)
- SkillTest (the seven-dimension scoring harness that became this scaffold's ratchet)

The graduated kept bar, external validation, and append-only baselines descend from the SkillTest "honesty mechanisms" - mechanisms that prevent the ratchet from gaming itself at high scores.

## License

MIT. Use it, adapt it, ship with it. Attribution appreciated but not required.

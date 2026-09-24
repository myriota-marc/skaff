# Claude Agent Scaffold - Install

Installs a `CLAUDE.md`, shared multi-LLM instruction files, agent and skill definitions, convention files, and `do-work/` runtime skeleton into a target project. The agent roster, tool-specific overlays, and conventions are pulled from a **pack** you pick at install time.

## Packs

A pack is a language or platform bundle. Each pack ships one or more versions.

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

Legacy v1 packs such as `csharp@v1` and `appsheet@v1` carried an orchestrator-as-sub-agent topology that cannot spawn specialists via the Agent tool. Maintained packs use a `/do-work-run` slash command executed by the main session. See each pack's `PACK.md` for the upgrade path.

Full list and manifests under [packs/](./packs/). Pack contract and version bumping rules in [packs/README.md](./packs/README.md).

## Install

### Windows / PowerShell

```powershell
.\install.ps1 -NewProjectDir C:\repos\MyService
.\install.ps1 -NewProjectDir C:\repos\MyApp -Pack appsheet
.\install.ps1 -NewProjectDir C:\repos\MyScript -Pack appscript
.\install.ps1 -NewProjectDir C:\repos\MyApp -Pack csharp@v1 -Force
```

### Linux / macOS / Git Bash

```bash
./install.sh /path/to/my-project
./install.sh /path/to/my-app --pack appsheet
./install.sh /path/to/my-script --pack appscript
./install.sh /path/to/my-app --pack csharp@v1 --force
```

Default pack is `csharp`. Default version is the latest numeric `v<N>` directory in the pack. Pinning: `<pack>@<version>` (e.g. `appsheet@v1`).

## What gets installed

The installer copies two source trees in order, then adds the continuity layer:

1. **`common/`** - Language-agnostic files installed in every project:
   - Behavioral convention (`commit-style.md`)
   - Generic REQ/UR templates
   - `do-work/` runtime dir skeletons
   - Multi-LLM instruction files: `GEMINI.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `.github/instructions/conventions.instructions.md`, `.cursorrules`, `.windsurfrules`, `.aider.conf.yml`, `.continue/rules/behavioral-guidelines.md`

2. **`packs/<pack>/<version>/`** - Pack overlay (wins on collisions):
   - Agent roster (`.claude/agents/`, `.github/agents/`, `.gemini/skills/`, `.agents/skills/`)
   - Pack conventions (`.claude/conventions/`)
   - Cursor rules (`.cursor/rules/`)
   - Windsurf rules and workflows (`.windsurf/rules/`, `.windsurf/workflows/`)
   - GitHub Copilot instructions (`.github/instructions/`)
   - `CLAUDE.md.template` (installed as `CLAUDE.md`)
   - `ratchet.conf.template`, `.gitleaks.toml.template`
   - Optional CI workflows (`ci/`)

3. **`continuity/`** - Zero-reconstruction continuity layer (skip with `-NoContinuity` / `--no-continuity`). Rules in `.claude/conventions/continuity-protocol.md`.
   - `files/` copied like the trees above: `.githooks/{pre-commit,commit-msg}`, `scripts/{lib,gate,adr-index,bootstrap,selftest}.sh`, `.claude/hooks/*.sh`, `.vale.ini`, `.vale/styles/Local/`, the Vale vocabulary, `docs/decisions/index.md`, `.gates/`. With `-Force` scaffold-owned files are overwritten, but existing `docs/` and `.gates/` files never are.
   - `merge/` merged, never overwritten: missing lines are appended to `.gitignore`, `.gitattributes` and `.tool-versions` (tools matched by name, so an existing pin wins), and hook groups whose command is not already present are added to `.claude/settings.json` (install.sh needs `jq` for this, else it reports the file as skipped).
   - `templates/STATE.md.template` rendered to `docs/STATE.md` only when absent, with the repo name, today, `stale_after` 14 days out, `-Purpose` / `--purpose`, and gate item A1 (self-test) open.
   - The human gate id in `scripts/lib.sh` comes from `-Human` / `--human`, else `human:<local part of git config user.email>`.
   - The installer never sets `core.hooksPath`; `scripts/bootstrap.sh` does, after the first commit.

On a fresh target, `common/` is copied first and the pack overlay second, and both copies share one `-Force` flag - so without `-Force`, a file that exists in both wins by first-writer, meaning `common/` wins, not the pack. With `-Force`, both copies overwrite unconditionally, so the pack (copied second) wins. The one file that currently ships in both trees is `.claude/conventions/commit-style.md`, byte-identical across every pack, so this ordering has no visible effect today - but it will if a pack's copy of a shared file ever diverges. The `CLAUDE.md.template` is special-cased: it installs to `<target>/CLAUDE.md` and is not preserved under `do-work/templates/` in the target.

## Pack identity sentinel

After copy, the installer writes `<target>/.claude/.pack`:

```text
pack: csharp
version: v1
installed_at: 2026-04-24T13:42:40Z
scaffold_commit: abc1234
```

Future tooling reads this to detect pack mismatches on upgrade. Do not edit by hand.

## Behaviour

- Idempotent. Re-running on an already-installed project is safe.
- Existing target files are preserved by default. Use `-Force` or `--force` to overwrite.
- The target directory is created if it does not exist.
- `.gitkeep` sentinels preserve empty runtime directories so they survive a clean checkout.
- Repo-root files (`install.*`, `README.md`, `INSTALL.md`, `CLAUDE.md`, `packs/README.md`, `packs/SHARED-NOTES.md`, `packs/*/PACK.md`) are not copied to the target by construction - the installers only walk `common/` and `packs/<pack>/<version>/`.

## Upgrading an installed project

There is no in-place upgrade. To move a target from one pack or version to another:

```bash
./install.sh /path/to/project --force --pack <pack>@<new-version>
```

Review the diff in the target's git history, keep what you want, discard what you do not.

## After install

1. Review `CLAUDE.md` and `.claude/conventions/` before first use.
2. Confirm the agent roster in `.claude/agents/` matches your project's stack.
3. Optional: copy `do-work/templates/ratchet.conf.template` to `ratchet.conf` at the repo root and tune weights, thresholds, and N/A overrides.
4. Optional: copy `do-work/templates/.gitleaks.toml.template` to `.gitleaks.toml` at the repo root.
5. Optional (packs that ship one): copy `do-work/templates/ci/ratchet-gate.yml.template` to `.github/workflows/ratchet-gate.yml`.
6. For GitHub Copilot, `.github/copilot-instructions.md` is already installed.
7. For Gemini CLI, `GEMINI.md` is already installed.
8. For Cursor, `.cursorrules` and `.cursor/rules/` are already installed.
9. For Windsurf, `.windsurfrules` and `.windsurf/rules/` are already installed.
10. For Aider, `.aider.conf.yml` is already installed.
11. Confirm the tool-specific agents in `.gemini/skills/`, `.agents/skills/`, and `.github/agents/`.
12. Confirm the Copilot path-specific instructions in `.github/instructions/`.
13. Commit the scaffold:

   ```bash
   git add .
   git commit -m "chore: bootstrap claude agent scaffold"
   ```

14. Activate the continuity layer (needs `vale`, `jq`, `gitleaks` at the versions in `.tool-versions`):

   ```bash
   sh scripts/bootstrap.sh          # core.hooksPath=.githooks, tool pins, vale sync
   git switch -c chore/continuity   # hooks reject commits on main
   sh scripts/gate.sh A1            # runs scripts/selftest.sh, writes .gates/A1.json
   ```

   Then set A1 to `status: done` in `docs/STATE.md`, add `.gates/A1.json` to `verified`, and commit with the trailer `Closes-Item: A1`.

## Running the queue

Only one orchestrator may drain the queue at a time. `do work run` acquires `do-work/.lock`. Concurrent invocations refuse to start. See `.claude/conventions/do-work-protocol.md` in the installed pack for lock semantics.

## Dispatch budget

Sub-agents receive at most 2000 tokens of verbatim content per dispatch brief. Over that, the orchestrator passes file paths and the sub-agent re-reads from disk inside its isolated context window. See the installed pack's `do-work-protocol.md`.

# Shared notes across packs

Files that are *conceptually* the same across packs. No automation enforces this - the list is a maintainer checklist when updating one pack's convention that should logically track across others.

## Files that should stay aligned

| File (within each pack) | Why it should track |
| --- | --- |
| `.claude/conventions/markdown-style.md` | Generic markdown rules. Only language-tag examples diverge per pack. |
| `.claude/conventions/do-work-protocol.md` | Queue, lock, and ownership semantics are protocol-level. Agent names within the ownership table legitimately diverge per pack. |
| `.claude/conventions/ratchet-protocol.md` | Seven dimensions and the graduated kept bar are protocol-level. Tool mapping in the per-pack ratchet agent legitimately diverges. |
| `.claude/conventions/coverage-protocol.md` | Coverage formula and band thresholds are protocol-level. |
| `.claude/conventions/external-validation.md` | Adversarial prompt is protocol-level. |
| `.cursor/rules/behavioral-guidelines.mdc` | Behavioral guidelines are protocol-level; frontmatter schema is shared. |
| `.cursor/rules/do-work-protocol.mdc` | Queue semantics are protocol-level. |
| `.windsurf/rules/behavioral-guidelines.md` | Same as Cursor version. |
| `.windsurf/workflows/do-work.md` | Queue drain workflow steps are protocol-level. |
| `.gemini/skills/reviewer/SKILL.md` | Reviewer role and verdict format are protocol-level. |
| `.gemini/skills/git-workflow/SKILL.md` | Git conventions and secret-scan protocol are protocol-level. |
| `.agents/skills/reviewer/SKILL.md` | Mirror of Gemini reviewer. |
| `.agents/skills/git-workflow/SKILL.md` | Mirror of Gemini git-workflow. |
| `.github/agents/reviewer.agent.md` | Mirror of Gemini reviewer in Copilot format. |
| `.github/agents/git-workflow.agent.md` | Mirror of Gemini git-workflow in Copilot format. |
| `.github/instructions/do-work.instructions.md` | Queue semantics are protocol-level. |

**Not listed** (deliberately pack-specific, never backport):

- `<lang>-style.md` - the pack's defining convention.
- Most agent files - each pack owns its agent roster. The protocol-level mirrors listed above should track.
- `commands/do-work-run.md` - each pack's slash command names its own specialists.
- Ratchet signal-source table in `ratchet.md`.
- `ratchet.conf.template` - tuned per stack.
- `.gitleaks.toml.template` - allowlist tuned per stack.
- CI workflow templates - per-toolchain.
- `CLAUDE.md.template` - lists the pack's conventions by name.

## Backport workflow

When editing a protocol-level convention in one pack:

1. Make the change.
2. Identify which other live packs should track. Use the table above.
3. Apply the equivalent change in each pack (verbatim or adapted as needed).
4. Commit each pack's change as a separate file edit in the same commit; commit message scope is `packs`.
5. If a pack is deliberately diverging on a previously shared convention, note it in that pack's `PACK.md` under a "Divergence from shared" heading.

## Outstanding drift to backport

Stale references found while authoring `nestjs/v1` against `react/v1`. They were fixed in the new
pack on the way in, but remain in the source pack and in whichever packs copied from it. Each is a
one-line edit; none has been applied across the maintained packs yet.

| File | Stale text | Should read |
| --- | --- | --- |
| `.claude/conventions/do-work-protocol.md` | `XML doc and markdown edits` in the Skill Action Boundaries table | the pack's own doc format (`TSDoc`, `godoc`, `docstring`) |
| `.claude/conventions/external-validation.md` | axis 5: `do the XML docs and comments accurately describe...` | the pack's own doc format |
| `.claude/conventions/ratchet-protocol.md` | `doc_quality` row wording, and `react/v1`'s focused kept-bar rationale `a bugfix that touches one hook` | the pack's own doc format; a stack-neutral unit for the kept-bar example |

`XML doc` is a leftover from the csharp pack, the same class of defect fixed in `830ebac`, and it is
still present in **27 convention files across 12 non-csharp pack versions** (appscript, appsheet v1
and v2, designer, gcli, html-css, nextjs, python, react, sveltekit, vue3-vite). Only `csharp` should
say it. Run these before assuming a pack is clean:

```bash
grep -rn "XML doc" packs/*/v*/.claude/conventions/   # expect csharp only
grep -rn "one hook" packs/*/v*/.claude/conventions/  # expect zero
```

## Shared base in `common/`

The truly pack-agnostic files live in `common/` (not under `packs/`) and are installed before any pack overlay:

- `common/.claude/conventions/commit-style.md` - Conventional Commits rules, language-agnostic.
- `common/.claude/conventions/knowledge-protocol.md` - the two-lane ADR / proposed-convention knowledge trail (promoted from the nextjs pack, the only place it used to ship). Uses `<pack>` and "domain advisor or specialist agent" placeholders since it cannot name any one pack's agents; see the file's own "Placeholders in this file" section.
- `common/.claude/conventions/continuity-protocol.md` - zero-reconstruction continuity layer: OKF 0.2 living docs (`docs/STATE.md`), immutable ADRs with a generated index, `.gates/` evidence, Claude Code and git hooks, Vale, self-test. Referenced from the Continuity section of every CLAUDE.md template and `AGENTS.md`.
- `common/do-work/templates/REQ-template.md` and `UR-template.md` - generic request shapes. `REQ-template.md` uses the same `<pack>-implement` placeholder convention as `knowledge-protocol.md`, and explains it inline; it previously hard-coded `csharp-implement` and so shipped a wrong agent name into every non-csharp target.
- `common/do-work/templates/ADR-template.md` and `proposed-convention-template.md` - starter files for the two knowledge-protocol lanes (also promoted from the nextjs pack).
- `common/do-work/` runtime dir skeletons (`.gitkeep` sentinels), including `do-work/proposed-conventions/.gitkeep`.
- `common/GEMINI.md`, `common/AGENTS.md`, `.github/copilot-instructions.md`, `.github/instructions/conventions.instructions.md`, `.cursorrules`, `.windsurfrules`, `.aider.conf.yml`, `.continue/rules/behavioral-guidelines.md` - shared multi-LLM files installed into every target.

The common multi-LLM files are not pack-specific and do not need backporting. They live in `common/` and auto-install to every pack.

If a pack ever needs to diverge on one of these, it can ship the file under its own version dir, but the override only takes effect with `-Force` / `--force`: the installer copies `common/` first and the pack second, sharing one force flag, so without it the file that lands first (`common/`'s copy) wins and the pack's copy is silently skipped. See [INSTALL.md](../INSTALL.md#what-gets-installed) for the full collision behaviour. The override should be called out in `PACK.md`.

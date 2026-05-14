# Dotfiles Package Contract v2

## Problem Statement

The dotfiles repo just completed a 5-phase re-architecture, but the package lifecycle contract is incomplete and the CLI surface has accumulated inconsistencies. Each future tool addition or removal currently requires special-case logic (clean/doctor hardcode mise/vfox) and naming/convention archaeology (underscore-prefixed files, mixed numeric prefixes, redundant `verify` vs `doctor`). Left unfixed, every new package compounds the inconsistency tax — and `uninstall` will keep silently leaving packages installed.

## Evidence

- Doctor and clean commands hardcode `mise` and `vfox` paths instead of iterating packages (`bin/dotfiles:doctor_dotfiles`, `bin/dotfiles:clean_dotfiles` — vfox-specific block at the end of each)
- `zsh/lib/` contains both `installer.zsh` (plain) and `_log.sh` (underscore prefix) — same directory, two conventions
- `zsh/packages/minimal/` contains both `00-sheldon.zsh` (numeric prefix) and `tmux.zsh` (plain) — convention exists but not consistently applied
- Profile name `server` is a misnomer — none of its tools (bat, eza, fd, fzf, jq, ripgrep, tealdeer, zoxide, vfox) are server-specific; they're general CLI productivity tools
- `verify` command exists as a separate CLI entry but is fully subsumed by `doctor`'s symlink-integrity check
- `update` auto-stashes local changes silently — surprises the user instead of warning
- `uninstall_dotfiles` removes symlinks + repo dir but leaves all installed brew/apt packages on the system

## Proposed Solution

Extend the existing per-package lifecycle pattern (`pkg_pre_install`, `pkg_install`, `pkg_install_fallback`, `pkg_post_install`, `pkg_init`) with three new optional hooks: **`pkg_clean`**, **`pkg_doctor`**, **`pkg_uninstall`**. Refactor `clean_dotfiles`, `doctor_dotfiles`, and `uninstall_dotfiles` in `bin/dotfiles` to iterate active-profile package files and dispatch the corresponding hook. Drop `verify` (subsumed by `doctor`). Rename profiles (`minimal` → `core`, `server` → `full`) — names signal cumulativity (`core ⊆ full`). Standardize file/function naming conventions. Add short CLI flags and alphabetize help.

Alternatives considered:
- **Declarative manifest** (chezmoi/Nix style): too heavy for this tool's intent and breaks the "one file per package" mental model the project already invested in.
- **Per-command hardcoded dispatch tables**: works but doesn't scale — every new package requires editing `bin/dotfiles`. The hook pattern is already proven.
- **Defer cleanup to OS package managers** (`brew bundle dump`/`apt-mark`): would offload tracking to brew/apt but couldn't handle the `curl|bash` and `git clone` install paths we use.

## Key Hypothesis

We believe a uniform per-package lifecycle contract (`install` → `init` → `clean` → `doctor` → `uninstall`) plus consistent naming conventions will let Leo add or remove any tool in under 5 minutes without grepping other packages for conventions, and `dotfiles uninstall` will cleanly return a machine to its pre-install state. We'll know we're right when Leo can ship a new package in one sitting and `uninstall` followed by `which <tool>` returns "not found" for every previously-installed tool.

## What We're NOT Building

- **Windows / PowerShell support** — Architecture stays unix-first; design must not preclude a future port, but no PowerShell hooks ship in this PRD. Rationale: out of scope for the immediate consistency goal.
- **Declarative state management** (no manifest file, no diff engine, no rollback DB) — Hooks are imperative shell functions; tracking state would change the project's nature.
- **Public-template polish** (CONTRIBUTING.md, issue templates, fork-friendly docs) — Rationale: this is personal tooling; fork-ability is incidental.
- **New CLI commands beyond existing surface** — `install/update/sync/clean/doctor/uninstall/profile/link/packages/help/version` is enough.
- **Per-machine config layering** (`.zshenv.local`, machine-specific overrides) — Out of scope; the current `DOTFILES_PROFILE` env var is the only intended axis of variation.

## Success Metrics

| Metric | Target | How Measured |
|--------|--------|--------------|
| Time to add a new package | < 5 min | Primary user self-report after first new-package addition post-v2 |
| `dotfiles uninstall` completeness | 100% of installed tools removed | `which <tool>` returns "not found" for each tool listed in active profile |
| Convention compliance | 0 outliers | `find zsh/lib zsh/packages -name '_*'` returns nothing unintended; all lifecycle functions named `pkg_<verb>` |
| `verify` references | 0 | `grep -rn "dotfiles verify" .` returns nothing after migration; old aliases removed |
| Doctor output usefulness | Each package reports ≥1 actionable result | Manual review of `dotfiles doctor` output across all packages |

Validation method: experiential — primary user (Leo) uses the system across multiple machines after the refactor and reports whether the friction disappeared.

## Open Questions

- [ ] For dual-platform install paths (brew on macOS, apt on Linux), is the uninstall expected to detect platform and reverse accordingly? — Assumed yes; matches install hook structure

*(Three earlier open questions resolved by user during PRD refinement: profile naming locked to `core`/`full`; `pkg_uninstall` is REQUIRED not optional; failure path must report cause + remaining state + manual recovery — see "Solution Detail" and "Decisions Log" for full contract.)*

---

## Users & Context

**Primary User**
- **Who**: Leo, sole user and maintainer of this dotfiles repo
- **Current behavior**: Adds tools by copying an existing package file, then hits convention archaeology when conventions diverge. Tries `dotfiles uninstall` and finds tools still installed. Hits `verify` and wonders why `doctor` doesn't already cover it.
- **Trigger**: Anytime a new tool is desired, a tool is no longer needed, or a machine misbehaves and `doctor` is the natural diagnosis.
- **Success state**: Picks any package file as a template, fills in 4–6 hooks, ships. Or runs `dotfiles uninstall` and confirms a clean machine.

**Job to Be Done**
When I add or remove a tool from my dotfiles, I want every package to follow the same lifecycle contract, so I can extend the system in 5 minutes without re-learning conventions and trust that uninstall actually returns my machine to a clean state.

**Non-Users**
Public consumers wanting a turnkey dotfiles framework, anyone wanting declarative state management, anyone running primarily on Windows today.

---

## Solution Detail

### Core Capabilities (MoSCoW)

| Priority | Capability | Rationale |
|----------|------------|-----------|
| Must | `pkg_clean` / `pkg_doctor` / `pkg_uninstall` hooks in lifecycle engine | The whole point — required for package-agnostic clean/doctor/uninstall |
| Must | `clean_dotfiles` / `doctor_dotfiles` / `uninstall_dotfiles` iterate packages, dispatch hooks | Required to consume the new hooks |
| Must | Drop `verify` command (hard removal + CHANGELOG note) | User decided "A" — keeps surface clean |
| Must | Rename `_log.sh` → `log.sh`; rename profiles `minimal` → `core`, `server` → `full` | Naming consistency is half the PRD goal; `core ⊆ full` is self-explanatory |
| Must | `pkg_uninstall` is REQUIRED for every package — engine errors hard if missing | Uninstall is the inverse of install; missing hook = incomplete package |
| Must | `pkg_uninstall` failure must report cause + remaining state + manual recovery | Failed uninstall must leave the user with everything they need to finish manually |
| Must | Alphabetize help text; add short flags (`-i`/`-u`/`-c`/`-d`/`-s`) | CLI ergonomics |
| Must | `update` warns + aborts on dirty tree; add explicit `--stash` flag | Less-destructive default |
| Must | Implement `pkg_clean`/`pkg_doctor`/`pkg_uninstall` for all existing packages | Otherwise the engine is unused |
| Must | Document naming conventions in CLAUDE.md + architecture.md Appendix B | Future packages must follow the contract |
| Should | Each `pkg_doctor` returns issue count; aggregate prints one-line summary per package, full detail under `-v` | Default doctor output stays readable; depth available |
| Should | Reverse-alphabetical iteration for `clean`/`uninstall`, forward for everything else | Mirrors typical dependency ordering (sheldon last) |
| Could | `dotfiles doctor <package>` to target a single package | Convenient but not required for v2 hypothesis |
| Could | Aggregate output color-codes per-package status (green/yellow/red) | Polish, not required |
| Won't | Windows / PowerShell hooks | Out of scope per constraint #1 |
| Won't | Manifest file / declarative state | Out of scope per "What We're NOT Building" |
| Won't | Per-machine config overrides | Out of scope per constraint |

### MVP Scope

Engine + CLI refactor + per-package hook implementations for every existing package, plus naming sweep and documentation update. The CLI must iterate, the hooks must exist for every active package, and a `dotfiles uninstall` on a fully-installed system must return clean.

### User Flow

**Critical path: add a new package**
1. Copy an existing package file as template (e.g., `cp zsh/packages/full/zoxide.zsh zsh/packages/full/newtool.zsh`)
2. Edit `PKG_NAME` / `PKG_DESC` and the 6 lifecycle functions (install/init/clean/doctor/uninstall + optional pre/post/fallback)
3. Run `dotfiles install` — provisions; `dotfiles doctor` — verifies; done

**Critical path: uninstall everything**
1. `dotfiles uninstall` → iterates packages in reverse-alphabetical order, calls each `pkg_uninstall`, then removes symlinks + repo dir
2. User confirms each tool is gone with `which <tool>`

---

## Technical Approach

**Feasibility**: HIGH

**Architecture Notes**
- Extend `init_package_template()` in `zsh/lib/installer.zsh` with three new optional hook dispatches (`pkg_clean`, `pkg_doctor`, `pkg_uninstall`) — same `typeset -f X >/dev/null && X` pattern as the five existing hooks. Pure addition.
- The hook dispatches DON'T fire from `init_package_template` itself (which runs on shell startup). Instead, the new `clean_dotfiles` / `doctor_dotfiles` / `uninstall_dotfiles` CLI commands source each active-profile package file and invoke its hook directly. This keeps shell startup unaffected.
- Iteration order: forward alphabetical for clean/doctor (parallel-safe); reverse alphabetical for uninstall (so sheldon comes last, matching dependency ordering — same reason `00-sheldon.zsh` is prefixed).
- Naming conventions documented in CLAUDE.md become the contract; any new package failing them is a code-review reject (or future lint).

**Technical Risks**

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Per-package `pkg_uninstall` correctness varies | High | Per-package author writes the reversal; document the contract; add `dotfiles doctor` as the sanity check after uninstall |
| Reverse-iteration breaks if a package has unstated dependencies | Medium | Sheldon is the only known cross-package dependency (plugin loader); reverse-alphabetical handles it; document the convention |
| Renaming `_log.sh` breaks the source path in `installer.zsh` + `bin/dotfiles` | High locally, easy to fix | Single coordinated commit; syntax-check both files post-rename |
| Profile rename breaks `~/.zshenv` saved value `DOTFILES_PROFILE=server` or `=minimal` | High on existing machines | Add a one-time migration in `set_defaults`: `server` → `full`, `minimal` → `core`; warn user once, persist new value |
| `dotfiles update` on dirty tree changes default behavior | High; user relies on auto-stash today | Add CHANGELOG entry; show recovery hint when `update` aborts (suggest `--stash`) |
| `set -u` strictness interacts with optional hooks | Low (same pattern works for existing hooks) | Use `typeset -f X >/dev/null && X` consistently |
| Aggregate doctor output becomes noisy with many packages | Medium | Default to one-line-per-package summary; full detail with `-v` |

---

## Implementation Phases

| # | Phase | Description | Status | Parallel | Depends | PRP Plan |
|---|-------|-------------|--------|----------|---------|----------|
| 1 | Engine hooks | Add `pkg_clean`/`pkg_doctor`/`pkg_uninstall` dispatch to `init_package_template` (no-op until CLI consumes them) | complete | - | - | `.claude/PRPs/plans/completed/engine-hooks.plan.md` |
| 2 | Naming sweep | Rename `_log.sh` → `log.sh`; rename profile dirs `minimal` → `core`, `server` → `full`; update zshrc/CLAUDE.md/README.md/architecture.md; add `DOTFILES_PROFILE` migration in `set_defaults` | complete | with 1 | - | `.claude/PRPs/plans/completed/naming-sweep.plan.md` |
| 3 | CLI refactor | Refactor `clean_dotfiles`/`doctor_dotfiles`/`uninstall_dotfiles` to iterate active profile and dispatch hooks; drop `verify`; alphabetize help; add short flags; `update` warn-and-abort default + `--stash` flag | complete | - | 1, 2 | `.claude/PRPs/plans/completed/cli-refactor.plan.md` |
| 4 | Per-package hook impls | For each package under `base/` and `tools/`: implement `pkg_clean`/`pkg_doctor`/`pkg_uninstall` | complete | - | 1, 3 | `.claude/PRPs/plans/completed/per-package-hooks.plan.md` |
| 5 | Convention docs + verify | Update CLAUDE.md naming section + architecture.md Appendix B with the locked conventions; run smoke tests (full install → doctor each pkg → full uninstall → which-not-found for each tool) | pending | - | 4 | - |

### Phase Details

**Phase 1: Engine hooks**
- **Goal**: Extend `init_package_template()` so packages can define `pkg_clean` / `pkg_doctor` / `pkg_uninstall` without engine changes
- **Scope**: `zsh/lib/installer.zsh` only. Adds three more `typeset -f X >/dev/null && X` dispatches. Hooks fire when invoked by CLI commands (Phase 3), NOT on shell startup.
- **Success signal**: A package can define a new hook; calling it directly via `zsh -ic '. zsh/packages/full/zoxide.zsh; pkg_doctor'` works without engine error.

**Phase 2: Naming sweep**
- **Goal**: Lock conventions across the repo so future additions follow one shape
- **Scope**: Rename `_log.sh` → `log.sh` + update source paths (bin/dotfiles, installer.zsh); rename `zsh/packages/minimal/` → `zsh/packages/core/`, `zsh/packages/server/` → `zsh/packages/full/`; update `zshrc` profile dispatch; update CLAUDE.md profile table + README.md + architecture.md; add migration in `set_defaults` (`DOTFILES_PROFILE=server` → `full`, `=minimal` → `core` once with warning, persist).
- **Success signal**: `find zsh/lib zsh/packages -name '_*'` returns nothing unintended; `dotfiles install` works after rename without manual config edits; on a machine with `DOTFILES_PROFILE=server` saved, migration fires once and persists `full`.

**Phase 3: CLI refactor**
- **Goal**: Make CLI consume the engine hooks and tighten ergonomics
- **Scope**: Refactor `bin/dotfiles`: `doctor_dotfiles` iterates active profile + collects per-package issue counts; `clean_dotfiles` iterates + dispatches `pkg_clean`; `uninstall_dotfiles` iterates in reverse + dispatches `pkg_uninstall` before removing symlinks + repo. On `pkg_uninstall` failure: continue iterating other packages (collect failures, don't abort), then print per-failure block — `package: error message`, `remaining: <path1> <path2>`, `recovery: <command>` — sourced from convention where the hook sets local vars `_PKG_UNINSTALL_ERROR`, `_PKG_UNINSTALL_REMAINING`, `_PKG_UNINSTALL_RECOVERY` on its failure path. Drop `verify` and its menu entry + dispatcher case; alphabetize help text and short flags (`-i`/`-u`/`-c`/`-d`/`-s`); `update_dotfiles` warns + aborts on dirty tree by default + `--stash` flag re-enables auto-stash.
- **Success signal**: `dotfiles doctor` reports each package by name (no hardcoded mise/vfox blocks); `dotfiles --help` is alphabetical with short flags; `dotfiles update` on dirty tree shows warning and exits non-zero unless `--stash` passed.

**Phase 4: Per-package hook implementations**
- **Goal**: Every active-profile package implements all three new hooks
- **Scope**: For each `.zsh` file under `zsh/packages/core/` and `zsh/packages/full/`: write `pkg_clean` (remove caches/state created at runtime), `pkg_doctor` (sanity check + return 0/n issues), `pkg_uninstall` (EXACT reverse of `pkg_install` — every install action has a 1:1 reversal; OS-aware; on failure path, populate three values: error message, remaining state paths, manual recovery command). Each package contributes ~30–50 lines.
- **Success signal**: `grep -rn "pkg_uninstall" zsh/packages/` shows entries for every package; `dotfiles uninstall` on a populated machine results in `which <tool>` returning "not found" for every tool.

**Phase 5: Convention docs + final verify**
- **Goal**: Lock the conventions in docs and verify end-to-end
- **Scope**: Update CLAUDE.md "Adding a New Package" + "Naming Conventions" sections to include the new hooks and conventions table; expand architecture.md Appendix B with the full per-package template (all 8 hooks); run smoke tests (fresh install → doctor each pkg → full uninstall → confirm cleanliness).
- **Success signal**: A reader can copy the template, fill in 8 hooks, and ship a working package without reading other source files.

### Parallelism Notes

- **Phase 1 + Phase 2** can run in parallel — Phase 1 touches `zsh/lib/installer.zsh` (engine), Phase 2 touches everything else (paths, profiles, docs). They converge in Phase 3.
- **Phases 3, 4, 5 are sequential** — Phase 3 must consume the engine hooks (Phase 1) and the renamed profiles (Phase 2); Phase 4 must consume the dispatch in Phase 3; Phase 5 documents the final shape.
- **Within Phase 4**, per-package hook implementations are independent and could be split per package if helpful (e.g., sub-agent per package), though serial single-pass is likely simpler.

---

## Decisions Log

| Decision | Choice | Alternatives | Rationale |
|----------|--------|--------------|-----------|
| Profile name pair | `core` / `full` | `base/tools`, `cli/workstation`, `essentials/complete`, `lite/full` | `core` and `full` make the cumulative relationship self-explanatory (`core ⊆ full`); both 4 letters; no overloaded meanings |
| `pkg_uninstall` requirement | Required (hard error if missing) | Optional with warning | User decision — uninstall must be the inverse of install; missing hook = incomplete package |
| `pkg_uninstall` failure path | Must report cause + remaining state + manual recovery command | Generic "failed" message | User decision — failed uninstall must leave user with everything needed to finish manually |
| `verify` removal mode | Hard remove + CHANGELOG note | Alias `verify` → `doctor` for a release | User picked A — single-user repo, transition cost is zero |
| `update` on dirty tree | Warn + abort, opt-in `--stash` | Interactive prompt; auto-stash with notice | User picked A — least surprising default for a CLI |
| `uninstall` scope | Per-package + remove repo + symlinks (current behavior preserved on top) | Per-package only; leave repo for user `rm -rf` | User picked A — keeps the "fully reversible" promise complete |
| Doctor output default | One-line summary per package + `-v` for detail | Always show per-package detail | User picked A — keeps default readable as packages grow |
| Pkg-hook iteration order | Reverse alphabetical for clean/uninstall, forward for everything else | Always alphabetical | User picked A — matches dependency ordering (sheldon last) |
| Lib file naming | Plain names, no underscore prefix | Underscore prefix for internal-only files | Underscore was sole outlier; plain names + `_dotfiles_*` function prefix already signal internal scope |
| Package file naming | Plain names; numeric `NN-` prefix only when load order matters | Always numeric prefix; always plain | Already de facto convention (documented in CLAUDE.md pitfall #5) — just enforce |
| Cross-platform support scope | Unix-first now; design must not preclude Windows | Build PowerShell port in parallel | Out of scope for v2 effort; aspirational only |
| CLI short flags | First letter, mnemonic if collision (`-i`/`-u`/`-c`/`-d`/`-s`) | No short flags; full GNU-style `--install` | First-letter is the universal CLI norm and easy to remember |
| Naming standardization timing | Same PRD as hook addition | Separate PRD for naming | Both serve the same goal (consistency); one cohesive landing minimizes churn |

---

## Research Summary

**Market Context**
- chezmoi enforces lifecycle via filename conventions (`run_once_before_*`, `run_once_after_*`) — naming as enforcement. Different mechanism, same goal.
- yadm has no per-package lifecycle and suffers from monolithic bootstrap scripts — anti-pattern to avoid.
- Nix-Darwin / home-manager achieve clean uninstall via declarative state — too heavy for this tool's intent, but confirms "uninstall should be reversible" is a known goal.
- Ansible roles enforce structure via fixed directories (`tasks/`, `handlers/`, `defaults/`, `meta/`) — proves consistent skeletons improve maintainability.
- Shell plugin managers (zinit, antibody) use file-as-unit + named-hooks — exactly the pattern this PRD extends.

**Technical Context**
- Engine already supports 5 lifecycle hooks; adding 3 more follows the same `typeset -f X >/dev/null && X` pattern in `init_package_template()` (`zsh/lib/installer.zsh:113`).
- Profile iteration logic is already in `zshrc:25-37` (cumulative `core ⊆ full` after rename) — same iteration drives the new aggregate commands.
- Two-tier log helpers (`zsh/lib/_log.sh`) already render per-package output cleanly via `_dotfiles_log_step` / `_log_result` / `_log_detail`.
- The just-introduced `extract_config_value` understands `${VAR:-default}` syntax — handles the `DOTFILES_PROFILE` migration cleanly without `eval`.
- File renames are mechanical: `_log.sh` is sourced from exactly 2 paths; profile directory is referenced in `zshrc` + `bin/dotfiles` validator + docs.

---

*Generated: 2026-05-14*
*Status: DRAFT - needs implementation*

# CLAUDE.md — Dotfiles Development Guide

Developer and AI-agent reference. Architecture rationale lives in
[docs/ARCHITECT.md](docs/ARCHITECT.md). User-facing instructions live in
[README.md](README.md). The 18 use cases the system must support live in
[docs/USECASES.md](docs/USECASES.md).

---

## Language boundaries

| Path | Language | Constraint |
|------|----------|------------|
| `bin/dotfiles` | **Bash** (`#!/usr/bin/env bash`) | Runs before zsh is configured. Must work on bare Debian. Never use `#!/usr/bin/env zsh` here. |
| `bin/dotfiles.ps1` *(planned)* | **PowerShell 7+** | Windows-native CLI. Runs from a clean pwsh after scoop bootstrap. |
| `zsh/**/*.zsh` | **Zsh** | May use zsh-specific builtins (`typeset`, `zstyle`, glob qualifiers). Loaded by `~/.zshrc`. |
| `pwsh/**/*.ps1` *(planned)* | **PowerShell** | Mirror of zsh tree for Windows. Loaded by `$PROFILE`. |
| `zsh/lib/log.sh` | **POSIX sh** (`#!/bin/sh`) | Sourced by both `bin/dotfiles` (bash) and `installer.zsh` (zsh). Must stay POSIX-compatible. |
| `zsh/lib/ui.sh` | **Bash** (`#!/usr/bin/env bash`) | Sourced ONLY by `bin/dotfiles`. Bash-only helpers (spinner, table, badge, progress, Levenshtein). Never sourced by zsh shell startup. |
| `Makefile` | **GNU make + Git Bash** (Windows-only) | Hard-fails on macOS/Linux. Force-pins `SHELL` to Git-Bash via `git --exec-path`. |

Do not mix languages across these boundaries.

---

## Package contract — two file types

After the mise consolidation, package files come in two flavors:

### a. Shell-integration files (the default, ~90% of tool files)

Just shell code at the top level. **Do NOT call `init_package_template`.**
Every section gated by `command -v <tool>` so missing tools no-op gracefully.

```zsh
# zsh/packages/dev/01-mise-tools.zsh — consolidated example
if command -v bat &>/dev/null && [[ -z "${MANPAGER:-}" ]]; then
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi
```

PowerShell mirror lives at `pwsh/packages/<profile>/<same-name>.ps1`:

```powershell
if ((Get-Command bat -EA SilentlyContinue) -and -not $env:MANPAGER) {
    $env:MANPAGER = "sh -c 'col -bx | bat -l man -p'"
}
```

### b. Lifecycle packages (the minority — mise itself, sheldon, tmux)

Tools that mise can't manage cleanly. Call `init_package_template "$PKG_NAME"`
at the bottom to opt into the 8 lifecycle hooks below.

---

## Lifecycle hooks (only for lifecycle packages)

### Startup-flow hooks — fired by `init_package_template`

| Hook | When it fires | Notes |
|------|--------------|-------|
| `pkg_pre_install` | Before install, only if `DOTFILES_INSTALL=true` and not yet installed | May modify `PKG_NAME`/`PKG_CMD`; engine re-reads them after. |
| `pkg_install` | Install step, only if not installed and `DOTFILES_INSTALL=true` | If absent, falls back to OS pkg manager via `_dotfiles_install_package`. |
| `pkg_install_fallback` | Called by `_dotfiles_install_package` when pkg manager is `unknown` | Use `_dotfiles_safe_run_installer`, never bare `curl \| bash`. |
| `pkg_post_install` | After install AND on re-install during `dotfiles install` | **MUST be idempotent.** |
| `pkg_init` | Every shell start, after install check passes | Must be fast (< 5ms). Use idempotency guard for `eval`-based init. |

### CLI-driven hooks — fired by `_dotfiles_invoke_package_hook`

| Hook | Command | Required? | Exit codes |
|------|---------|-----------|------------|
| `pkg_clean` | `dotfiles clean` | Optional | `0` = ok; `2` = not defined (skip); other = warning |
| `pkg_doctor` | `dotfiles doctor` | Optional | `0` = healthy; `N` = N issues (added to total) |
| `pkg_uninstall` | `dotfiles uninstall` | **Required** | `0` = ok; `2` = not defined (treated as error); other = failure |

Hooks must use `return`, not `exit`. `exit` from a sourced function
terminates the parent shell.

---

## Profile + override system

### Profile (which group of packages loads)

Filesystem-derived: any directory `zsh/packages/<name>/` is a valid
profile. `DOTFILES_PROFILE` (in `~/.zshenv` managed block) selects one.
Cumulative — `core/` always loads first, then the named profile.

Migration in progress: `core` / `full` → `core` / `server` / `dev`.

### Override env vars (per-machine, written to `~/.zshenv` managed block)

| Var | Purpose | Read by |
|---|---|---|
| `DOTFILES_PROFILE` | Pick active profile | zshrc loader + bin/dotfiles |
| `DOTFILES_EXCLUDE` | Comma-sep tools to drop | bin/dotfiles install (planned) |
| `DOTFILES_EXTRA` | Comma-sep tools to add | bin/dotfiles install (planned) |
| `DOTFILES_VERBOSE` | Verbose logging on/off | log.sh helpers |
| `DOTFILES_INSTALL` | true during `dotfiles install` run | init_package_template gating |
| `DOTFILES_HOOK_ONLY` | true when CLI is invoking a single hook | init_package_template gating |
| `DOTFILES_NO_RELOAD` | Skip `exec zsh` at end of install | bin/dotfiles install |

All user-writable vars are managed via `dotfiles config set <key> <value>`,
which edits only the marker-delimited block in `~/.zshenv`.

---

## Two-tier logging model

Defined in `zsh/lib/log.sh`, sourced by both `bin/dotfiles` (bash) and
`zsh/lib/installer.zsh` (zsh).

**Tier 1 — Always-print** (visible without `-v`; for CLI command output):

| Helper | Output | Stream |
|--------|--------|--------|
| `_dotfiles_log_step` | `→ Bold message` | stdout |
| `_dotfiles_log_detail` | `• message` | stdout |
| `_dotfiles_log_result` | `  label: value` | stdout |
| `_dotfiles_log_summary` | `✓ message` | stdout |
| `_dotfiles_log_warning` | `⚠  message` | stderr |
| `_dotfiles_log_error` | `✗ Bold message` | stderr |
| `_dotfiles_log_hint` | `hint: …` (gray) | stderr |

**Tier 2 — Verbose-only** (silent unless `DOTFILES_VERBOSE=true`):

| Helper | Output |
|--------|--------|
| `_dotfiles_log_debug` | `[HH:MM:SS.mmm] [scope] message (+Δms)` |
| `_dotfiles_log_info` | `• white text` |
| `_dotfiles_log_dim` | `  gray indented` |
| `_dotfiles_log_success` | `✓ green text` |

**Rule**: shell startup (`pkg_init`, `pkg_post_install` on normal start)
uses **Tier 2 only**. CLI commands (`clean`, `doctor`, `uninstall`) use
**Tier 1** so output is visible without `-v`.

Colors are disabled automatically when stdout is not a TTY or `NO_COLOR`
is set.

### Debug scope tags

`_dotfiles_log_debug` reads `$DOTFILES_LOG_SCOPE` and renders the scope
in the prefix. `init_package_template` sets it to `PKG:<name>` for every
debug call from a package's hooks (auto-tagged).

---

## UI primitives (bash-only, used by `bin/dotfiles`)

`zsh/lib/ui.sh` adds bash-only helpers. All respect `DOTFILES_QUIET=true`
and degrade gracefully on non-TTY / `NO_COLOR`:

| Helper | Use |
|--------|-----|
| `_dotfiles_spin "<label>" -- <cmd>` | Spinner around a long subprocess. |
| `_dotfiles_table <k1> <v1> <k2> <v2> …` | Aligned `key : value` table. |
| `_dotfiles_badge <OK\|WARN\|FAIL\|INFO> <label>` | 256-color background pill. |
| `_dotfiles_progress <cur> <total> <label>` | In-place progress bar. |
| `_dotfiles_did_you_mean <input> <candidates…>` | Pure-bash Levenshtein. |

---

## Naming conventions

Each language follows its own native conventions ([NFR-3 in
docs/ARCHITECT.md](docs/ARCHITECT.md#code-quality)). Do not cross
patterns.

### Bash / zsh / POSIX sh

| Symbol | Convention | Example |
|--------|-----------|---------|
| Package variables (lifecycle pkgs) | `PKG_NAME`, `PKG_DESC`, `PKG_CMD`, `PKG_CHECK_FUNC` | `PKG_NAME="mise"` |
| Startup hook functions | `pkg_pre_install`, `pkg_install`, `pkg_install_fallback`, `pkg_post_install`, `pkg_init` | — |
| CLI hook functions | `pkg_clean`, `pkg_doctor`, `pkg_uninstall` | — |
| Log helpers | `_dotfiles_log_<level>` | `_dotfiles_log_step` |
| Platform helpers | `dotfiles_os`, `dotfiles_distro`, `dotfiles_pkg_manager` | — |
| Safe installer helpers | `_dotfiles_safe_run_installer`, `_dotfiles_safe_git_clone`, `_dotfiles_verify_sha256` | — |
| Internal/private functions | leading underscore: `_dotfiles_<name>` | `_dotfiles_did_you_mean` |
| Load flag (idempotency, NOT exported) | `_DOTFILES_<TOOL>_LOADED` | `_DOTFILES_MISE_LOADED` |
| File-prefix for "load first" | `00-<name>.zsh` / `01-<name>.zsh` | `00-mise.zsh` |
| Filenames | `lowercase-with-dashes.zsh` or `lowercase.zsh` | `01-mise-tools.zsh` |
| Linter | `shellcheck` for bash + POSIX sh | — |

### PowerShell (the `pwsh/` tree)

PowerShell has strong community conventions enforced by its tooling
(`PSScriptAnalyzer`, ISE/VSCode completion). Follow them — don't import
bash/zsh patterns into pwsh.

| Symbol | Convention | Example |
|--------|-----------|---------|
| Functions / cmdlets | `Verb-Noun` PascalCase, approved verbs only | `Install-DotfilesPackage` |
| Approved verbs | `Get`, `Set`, `New`, `Remove`, `Test`, `Invoke`, `Initialize`, `Update`, `Add`, `Clear`, `Find`, `Read`, `Write`, `Show`, `Sync` | Use `Get-Verb` in pwsh to list them |
| Locals / parameters | `$camelCase` | `$packageName` |
| Module-scoped / script-scoped | `$PascalCase` | `$DotfilesRoot` |
| Private functions | leading underscore: `_Verb-Noun` | `_Install-MiseTool` |
| Filenames (scripts) | `Verb-Noun.ps1` PascalCase | `Install-Dotfiles.ps1` |
| Filenames (modules) | `<Name>.psm1` PascalCase | `Dotfiles.Logging.psm1` |
| File-prefix for "load first" | `00-<Name>.ps1` (mirror of zsh) | `00-Mise.ps1` |
| Env var equivalent of `$DOTFILES_*` | Same name, accessed via `$env:DOTFILES_PROFILE` | — |
| Linter | `PSScriptAnalyzer` (Invoke-ScriptAnalyzer) | — |

**Naming bridge** (for tools shipped in both trees):

| Concept | zsh | pwsh |
|---|---|---|
| Init hook | `pkg_init` | `Initialize-Package` |
| Doctor hook | `pkg_doctor` | `Test-PackageHealth` |
| Load flag | `_DOTFILES_MISE_LOADED` (no export) | `$script:DotfilesMiseLoaded = $true` |
| Tool integration eval | `eval "$(starship init zsh)"` | `Invoke-Expression (&starship init powershell \| Out-String)` |

---

## Common pitfalls (actively guarded in the code)

1. **Load-flag must not be exported.** `00-mise.zsh` sets
   `_DOTFILES_MISE_LOADED="1"` without `export`. If exported, `exec zsh`
   inherits it and skips `mise activate`, leaving PATH without tool shims.

2. **`pkg_uninstall` is required.** The dispatcher treats exit code `2`
   (not-defined) as an error for `pkg_uninstall`, unlike `pkg_clean` and
   `pkg_doctor` which silently skip on code `2`.

3. **`pkg_init` must return 0 explicitly** when the last expression is a
   failing `[[ test ]]`. Common pattern:
   ```zsh
   pkg_init() {
       [[ -z "${MANPAGER:-}" ]] && export MANPAGER="…"
       return 0   # don't inherit the failed test's exit code
   }
   ```

4. **Never call `exit` inside a hook.** Hooks are sourced functions.
   `exit` kills the parent shell. Use `return <code>`.

5. **`pkg_post_install` re-runs during `dotfiles install`.** Even on
   already-installed packages. Must be idempotent.

6. **Alphabetical load order** in `zsh/packages/<profile>/`. mise must
   activate before any tool gated on `command -v` checks → use `00-mise.zsh`
   prefix to force first-load. Sheldon similarly uses load-first ordering
   in `core/`.

7. **`mise install` only runs when `DOTFILES_INSTALL=true`.** Plain shell
   startup never triggers tool installs — `pkg_init` only activates PATH.
   Together with `not_found_auto_install = false` in mise.toml, this means
   shell open is read-only.

8. **`config/mise/config.toml` uses bare tool names** (e.g. `jq = "latest"`)
   via mise's built-in registry. Don't use the deprecated `ubi:` backend —
   use bare names or `github:owner/repo` for explicit pinning.

9. **`/etc/nanorc` loads before `~/.nanorc`** — the repo's nanorc file
   intentionally omits syntax `include` lines; the system loader registers
   them already. Adding includes that match zero files errors on nano 7+.

10. **Marker-delimited block in `~/.zshenv`** — `dotfiles config set` only
    edits between `# DOTFILES MANAGED BEGIN/END`. Never use blanket
    `^export DOTFILES_` regex-replace — it eats user content outside the
    block.

---

## Cross-shell parity (zsh + pwsh)

Tools that need shell integration ship two files: one for each shell.
Naming and location mirror exactly:

```
zsh/packages/dev/starship.zsh    eval "$(starship init zsh)"
pwsh/packages/dev/starship.ps1   Invoke-Expression (&starship init powershell | Out-String)
```

**Skip the pwsh file** if you don't run the tool on Windows. The bootstrap
won't error on missing mirrors — each tree loads independently.

**Do not auto-translate.** Two short hand-written files beat one fragile
translator that breaks on non-trivial snippets.

---

## When you add a new tool

1. Add the binary to `config/mise/config.toml`: `<tool> = "latest"`.
2. (If shell integration needed) create `zsh/packages/<profile>/<tool>.zsh`
   with `command -v <tool> && <init>`-style code.
3. (If Windows parity needed) create the matching
   `pwsh/packages/<profile>/<tool>.ps1`.
4. Run `dotfiles install` to verify mise installs it and shell integration
   works.
5. (If lifecycle hooks needed — install/uninstall logic mise can't express)
   instead of steps 2-3, write a full lifecycle package calling
   `init_package_template`. Mirror the 8-hook pattern in `00-mise.zsh`.

---

See [docs/ARCHITECT.md](docs/ARCHITECT.md) for the full architecture and
why-this-shape decisions. See [docs/USECASES.md](docs/USECASES.md) for the
18 use cases the architecture must deliver.

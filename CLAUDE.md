# CLAUDE.md — Dotfiles Development Guide

## Bash vs zsh boundary

| Path | Language | Constraint |
|------|----------|------------|
| `bin/dotfiles` | **Bash** (`#!/usr/bin/env bash`) | Runs before zsh is configured. Must work on minimal systems. Never use `#!/usr/bin/env zsh` here. |
| `zsh/**/*.zsh` | **Zsh** | May use zsh-specific builtins: `typeset`, `zstyle`, glob qualifiers (`(N)`, `(#qN.md+7)`, etc.). |
| `zsh/lib/log.sh` | **POSIX sh** (`#!/bin/sh`) | Sourced by both bash (`bin/dotfiles`) and zsh (`installer.zsh`). Must stay POSIX-compatible. |

Do not mix languages across these boundaries.

---

## Two-tier logging model

All helpers are defined in `zsh/lib/log.sh` and sourced by both `bin/dotfiles` and
`zsh/lib/installer.zsh`.

**Tier 1 — Always-print** (visible without `-v`; use in CLI command output):

| Helper | Output | Stream |
|--------|--------|--------|
| `_dotfiles_log_step` | `→ Bold message` — CLI progress marker | stdout |
| `_dotfiles_log_detail` | `• message` — always-visible bullet | stdout |
| `_dotfiles_log_result` | `  label: value` — diagnostic pair | stdout |
| `_dotfiles_log_summary` | `✓ message` — final outcome line | stdout |
| `_dotfiles_log_warning` | `⚠  message` | stderr |
| `_dotfiles_log_error` | `✗ Bold message` | stderr |

**Tier 2 — Verbose-only** (silent unless `DOTFILES_VERBOSE=true`; use in package
hooks and shell startup):

| Helper | Output | Stream |
|--------|--------|--------|
| `_dotfiles_log_debug` | `[DEBUG] gray text` | stdout |
| `_dotfiles_log_info` | `• white text` | stdout |
| `_dotfiles_log_dim` | `  gray indented` | stdout |
| `_dotfiles_log_success` | `✓ green text` | stdout |

**Rule:** shell startup (`pkg_init`, `pkg_post_install` on normal start) uses
**only Tier 2** helpers. This keeps normal shell open silent. CLI commands
(`clean`, `doctor`, `uninstall`) use **Tier 1** helpers so output is visible
without `-v`.

Colors are disabled automatically when stdout is not a TTY or `NO_COLOR` is set.

---

## Lifecycle hooks

### Startup-flow hooks (fired by `init_package_template`)

Called automatically when a package file is sourced during shell startup or
`dotfiles install`. All are optional except the overall `init_package_template`
call at the end of every package file.

| Hook | When it fires | Notes |
|------|--------------|-------|
| `pkg_pre_install` | Before installation, only when `DOTFILES_INSTALL=true` and package not yet installed | May modify `PKG_NAME`, `PKG_CMD` etc. — engine re-reads them after. |
| `pkg_install` | Install step, only when not installed and `DOTFILES_INSTALL=true` | If absent, falls back to `_dotfiles_install_package` (OS pkg manager). |
| `pkg_install_fallback` | Called by `_dotfiles_install_package` when `dotfiles_pkg_manager` returns `unknown` | Must not be a bare `curl \| bash`; use `_dotfiles_safe_run_installer`. |
| `pkg_post_install` | After successful install **and** on re-install (`DOTFILES_INSTALL=true`) for already-installed packages | Idempotent sync: config copy, plugin lock, SDK provisioning. |
| `pkg_init` | Every shell start, after install (when package is installed) | Must be fast (< 5ms). Use idempotency guard for `eval`-based init. |

### CLI-driven hooks (fired by `_dotfiles_invoke_package_hook` from `bin/dotfiles`)

Called via a zsh subprocess with `DOTFILES_HOOK_ONLY=true`. When set,
`init_package_template` returns immediately without running the startup flow —
only hook function definitions are loaded.

| Hook | Command | Required? | Exit codes |
|------|---------|-----------|------------|
| `pkg_clean` | `dotfiles clean` | Optional | `0` = ok; `2` = not defined (skip); other = warning |
| `pkg_doctor` | `dotfiles doctor` | Optional | `0` = healthy; `N` = N issues (added to total) |
| `pkg_uninstall` | `dotfiles uninstall` | **Required** | `0` = ok; `2` = not defined (treated as error); other = failure |

Hooks must use `return`, not `exit`. `exit` from a sourced function terminates
the parent shell.

---

## Naming conventions

| Symbol | Convention | Example |
|--------|-----------|---------|
| Package variables | `PKG_NAME`, `PKG_DESC`, `PKG_CMD`, `PKG_CHECK_FUNC` | `PKG_NAME="bat"` |
| Startup hook functions | `pkg_pre_install`, `pkg_install`, `pkg_install_fallback`, `pkg_post_install`, `pkg_init` | — |
| CLI hook functions | `pkg_clean`, `pkg_doctor`, `pkg_uninstall` | — |
| Log helpers | `_dotfiles_log_<level>` | `_dotfiles_log_step` |
| Platform helpers | `dotfiles_os`, `dotfiles_distro`, `dotfiles_pkg_manager` | — |
| Safe installer helpers | `_dotfiles_safe_run_installer`, `_dotfiles_safe_git_clone`, `_dotfiles_verify_sha256` | — |
| Load flag (idempotency) | `_DOTFILES_<TOOL>_LOADED` — **NOT exported** | `_DOTFILES_VFOX_LOADED` |
| Internal pkg failure vars | `_PKG_UNINSTALL_ERROR`, `_PKG_UNINSTALL_REMAINING`, `_PKG_UNINSTALL_RECOVERY` | IPC between hook and dispatcher |

---

## Common pitfalls (actively guarded in the code)

1. **Load flag must not be exported.** `vfox.zsh` sets `_DOTFILES_VFOX_LOADED="1"`
   without `export`. If exported, `exec zsh` inherits it and skips `vfox activate`,
   leaving PATH without SDK entries. Same rule applies to any `eval`-based `pkg_init`.

2. **`pkg_uninstall` is required.** The dispatcher returns exit code `2` when
   `pkg_uninstall` is not defined and treats that as an error (unlike `pkg_clean`
   and `pkg_doctor` which silently skip on code `2`).

3. **`pkg_init` must return 0 explicitly** when the last expression is a failing
   `[[ test ]]`. `bat.zsh` guards `MANPAGER` with `[[ -z "${MANPAGER:-}" ]]` and
   adds `return 0` because a set `MANPAGER` would make the `[[` test fail, causing
   `init_package_template` to treat init as failed.

4. **Never call `exit` inside a hook.** Hooks are sourced functions. `exit` kills
   the parent shell. Use `return <code>`.

5. **`pkg_post_install` re-runs on already-installed packages during `dotfiles install`.**
   It must be idempotent. The engine sets `DOTFILES_INSTALL=true` and calls
   `pkg_post_install` even when the package binary is already present.

6. **Alphabetical load order in `zsh/packages/core/`.** `sheldon.zsh` loads first
   (`s` sorts before `t` for tmux). Any new file starting with `a`–`r` loads before
   sheldon and breaks the plugin system. Prefix with `00-` if strict ordering is needed.

7. **`vfox.zsh:pkg_post_install` spawns a child zsh with `DOTFILES_INSTALL=false`**
   to run `vfox use -g`. Without this, the child zsh re-fires every `pkg_post_install`
   (including `vfox`'s own), creating infinite recursion.

---

See [ARCHITECT.md](ARCHITECT.md) for the full package template, boot sequence,
and architecture internals.

# CLAUDE.md — Dotfiles Development Guide

## Project Overview

A cross-platform, profile-based zsh configuration system. Ships on macOS and common Linux
distros. Keeps shell startup under 200ms by deferring heavy work via sheldon and idempotency guards.

Two cumulative profiles (`core ⊆ full`):

| Profile | Tools added |
|---------|-------------|
| `core`  | tmux (+ sheldon infrastructure) |
| `full`  | bat, eza, fd, fzf, jq, ripgrep, tealdeer, zoxide, vfox |

Legacy names `minimal` / `server` are accepted as aliases for one release —
auto-migrated to `core` / `full` on next `dotfiles install`.

---

## Shell Language Rules

| Path | Language | Reason |
|------|----------|--------|
| `bin/dotfiles` | **Bash** | Runs before zsh is configured; must work on minimal systems |
| `zsh/**/*.zsh` | **Zsh** | Shell config; may use zsh-specific builtins (`typeset`, `zstyle`, glob qualifiers) |

Do **not** mix the two. Never use `#!/usr/bin/env zsh` in `bin/dotfiles`.

---

## Architecture

```
bin/dotfiles          Bash CLI — symlinks, install, update, profile switch
  │
zshrc                 Entry point (< 40 lines) — sources core/ + libs + packages
  │
  ├── zsh/core/       Always-loaded modules (setopt, history, completion, aliases, theme)
  ├── zsh/lib/        Shared libraries — installer, platform detection
  └── zsh/packages/   One file per tool, grouped by profile tier
```

Full details: `docs/architecture.md`
Requirements: `docs/architecture.md#appendix-a-system-requirements`
How to add a package: `docs/architecture.md#appendix-b-adding-a-package`

---

## Adding a New Package

1. Pick the right tier: `core` | `full`
2. Create **one file**: `zsh/packages/<tier>/<toolname>.zsh`
3. Do **not** modify `zshrc`, `installer.zsh`, or any other core file
4. Call `init_package_template "$PKG_NAME"` at the end

Minimal template:
```zsh
#!/usr/bin/env zsh

PKG_NAME="toolname"
PKG_DESC="One-line description"

pkg_init() {
    # runs every shell start — keep fast (< 5ms)
    alias t="toolname --flag"
}

init_package_template "$PKG_NAME"
```

---

## Naming Conventions

| Symbol | Convention | Trigger |
|--------|-----------|---------|
| Package variables | `PKG_NAME`, `PKG_DESC`, `PKG_CMD`, `PKG_CHECK_FUNC` | declared in package file |
| Hook functions (startup) | `pkg_pre_install`, `pkg_install`, `pkg_install_fallback`, `pkg_post_install`, `pkg_init` | fired by `init_package_template` on shell start |
| Hook functions (CLI) | `pkg_clean`, `pkg_doctor`, **`pkg_uninstall`** (REQUIRED) | fired by `_dotfiles_invoke_package_hook` from `bin/dotfiles` |
| Private helpers (check) | `_<tool>_is_installed` | called by `PKG_CHECK_FUNC` |
| Load flag (idempotency) | `_DOTFILES_<TOOL>_LOADED` (NOT exported) | guards `pkg_init` re-entry |

`pkg_uninstall` is REQUIRED for every package — it is the inverse of `pkg_install` and the engine treats a missing one as an incomplete package. The other CLI-driven hooks (`pkg_clean`, `pkg_doctor`) are optional; missing hooks are silently skipped.

---

## Idempotency Rules (Critical)

Shell startup must be **safe to run multiple times** (e.g. `source ~/.zshrc` after a tool
is already active). Any package with non-trivial `pkg_init` logic (sheldon, vfox) needs
a guard to prevent re-initialization:

```zsh
pkg_init() {
    [[ "${_DOTFILES_TOOL_LOADED:-}" == "1" ]] && return 0   # <-- required

    eval "$(tool activate zsh)"   # or other initialization

    export _DOTFILES_TOOL_LOADED="1"
}
```

> Without this guard: `source ~/.zshrc` re-runs the initialization, which can cause
> duplicate PATH entries, re-evaluated hooks, or degraded performance.

---

## Testing

```zsh
# Measure shell startup time (3-run average, discard first)
time zsh -i -c exit

# Verify all symlinks and package installs
dotfiles verify

# Test the version manager works correctly
source ~/.zshrc
vfox current nodejs   # should print configured node version

# Re-source safety check (should produce no errors)
source ~/.zshrc
source ~/.zshrc
```

---

## Common Pitfalls

1. **Modifying core files** — Never add tool logic to `zshrc`, `installer.zsh`, or `zsh/core/*.zsh`.
   Each tool is self-contained in its own package file.

2. **Forgetting idempotency guards** — Packages with `eval` init (sheldon, vfox) need
   a load flag guard (see above). Skipping it causes hard-to-debug re-source breakage.
   The guard MUST NOT be exported, or `exec zsh` will inherit it and skip re-init.

3. **Making `pkg_init` slow** — `pkg_init` runs synchronously at shell startup. Keep it
   under ~5ms. Use compiled tools (like vfox) that initialize quickly.

4. **Using `command -v` for shell-function tools** — Tools like `nvm` are not
   binaries. Set `PKG_CHECK_FUNC` to a custom function, or `command -v` will always fail.

5. **Adding a package that sorts before `sheldon.zsh`** — Files in `zsh/packages/core/`
   load alphabetically. `sheldon.zsh` currently loads first by natural order (`s < t`).
   Any new file starting with `a`–`r` would load before sheldon and break the plugin
   system. Either prefix the new file with `99-` (loads last) or rename sheldon back to
   `00-sheldon.zsh` to lock its position explicitly.

6. **Bare `curl | bash` in `pkg_install_fallback`** — Always download to a temp file and
   verify a checksum before executing. See `docs/architecture.md` for the safe pattern.

7. **Forgetting `pkg_uninstall`** — The engine treats a missing `pkg_uninstall` as a hard
   error during `dotfiles uninstall`. Every package must implement it as the exact reversal
   of `pkg_install` (OS-aware). On failure, write `ERROR=...`, `REMAINING=...`, and
   `RECOVERY=...` lines to `$_PKG_UNINSTALL_REPORT_FILE` (the dispatcher exports it) before
   `return 1` — the user then sees concrete manual-recovery instructions. See
   `zsh/packages/core/sheldon.zsh` for the canonical shape.

---

## Key Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DOTFILES_ROOT` | `~/.dotfiles` | Path to this repo |
| `DOTFILES_PROFILE` | `core` | Active profile (set via `dotfiles profile <name>`) |
| `DOTFILES_VERBOSE` | `false` | Detailed shell-startup + CLI logs (env-passed values override the saved default) |
| `DOTFILES_INSTALL` | `false` | Set to `true` to run the install flow (set internally by `dotfiles install`) |

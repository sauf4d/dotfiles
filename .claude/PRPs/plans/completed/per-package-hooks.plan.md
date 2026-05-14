# Plan: Per-Package Hooks (Phase 4)

## Summary

Implement `pkg_clean`, `pkg_doctor`, and `pkg_uninstall` for all 11 package files.
Also fix `_dispatch_pkg_hook` to source `platform.zsh` so hooks can use `dotfiles_os`
and `dotfiles_pkg_manager`, and wire the `_PKG_UNINSTALL_*` failure-vars via temp file.

## Metadata

- **Complexity**: Medium
- **Source PRD**: `.claude/PRPs/prds/dotfiles-package-contract-v2.prd.md`
- **PRD Phase**: 4 — Per-package hook implementations
- **Estimated Files**: 11 package files + `bin/dotfiles` (dispatcher upgrade)

---

## Pre-Implementation Fixes

### Fix 1: `_dispatch_pkg_hook` must source `platform.zsh`

`installer.zsh` does not source `platform.zsh`. The current subshell only loads
`log.sh` + `installer.zsh`, so `dotfiles_os` and `dotfiles_pkg_manager` are
undefined when hooks run. Every `pkg_uninstall` that branches on OS would fail.

**Fix**: Add `source "$DOTFILES_ROOT/zsh/lib/platform.zsh"` before `installer.zsh`
in `_dispatch_pkg_hook`.

### Fix 2: Wire `_PKG_UNINSTALL_*` vars across the subshell boundary

The PRD requires hooks to report `_PKG_UNINSTALL_ERROR`, `_PKG_UNINSTALL_REMAINING`,
`_PKG_UNINSTALL_RECOVERY` on failure. These are set in the zsh subshell and currently
lost at subshell exit. Use temp-file approach (option b from the spec):

- `_dispatch_pkg_hook` creates `_PKG_UNINSTALL_REPORT_FILE=$(mktemp)` before the
  zsh invocation and exports it into the subshell environment.
- On failure, the hook writes `KEY=VALUE` lines to that file.
- After the zsh subshell returns non-zero, the dispatcher sources the file (three
  vars into local bash vars), then unlinks it.
- The `uninstall_dotfiles` aggregator uses these vars to populate its failure summary.
- Backward-compat: if a hook fails without writing the report file (e.g. sourcing
  error), the dispatcher falls back to `rc=N|see hook output above|investigate manually`.

---

## Package Hook Designs

### sheldon (`core/00-sheldon.zsh`)

**install actions**:
- macOS: nothing custom (uses `_dotfiles_install_package` via brew)
- Linux: curl installer to `/usr/local/bin`
- post_install: copies `plugins.toml` to `~/.config/sheldon/`, runs `sheldon lock`

**pkg_doctor**: check `sheldon` binary exists → print version; check
`~/.config/sheldon/plugins.toml` readable; return 0 if healthy.

**pkg_clean**: sheldon lock file at `~/.config/sheldon/sheldon.lock` and plugin
cache at `~/.local/share/sheldon/`. Dry-run: report sizes. `--force`: remove both.

**pkg_uninstall**:
- remove `plugins.toml` symlink if it points into dotfiles repo
- remove `~/.config/sheldon/` dir
- remove `~/.local/share/sheldon/` plugin cache
- macOS (brew): `brew uninstall sheldon`
- Linux: `rm -f /usr/local/bin/sheldon` (mirrors curl-to-`/usr/local/bin` install)

### tmux (`core/tmux.zsh`)

**install actions**:
- uses `_dotfiles_install_package` (brew/apt/etc.)
- post_install: symlinks `tmux.conf`; clones TPM to `~/.tmux/plugins/tpm`; runs plugin install

**pkg_doctor**: check `tmux` binary; check `~/.tmux.conf` symlink resolves; check TPM dir exists.

**pkg_clean**: tmux plugin download cache is in `~/.tmux/plugins/` (everything except `tpm` itself
is a plugin installed by TPM). Dry-run: list plugin dirs. `--force`: remove non-tpm subdirs.
Resurrection plugin stores sessions in `~/.local/share/tmux/resurrect/` — report count, remove
with `--force`.

**pkg_uninstall**:
- remove `~/.tmux.conf` symlink (only if it points into dotfiles repo)
- remove `~/.tmux/` directory (TPM + plugins)
- macOS: `brew uninstall tmux`
- Linux: `sudo apt remove -y tmux` / `sudo dnf remove -y tmux` / etc.

### bat (`full/bat.zsh`)

**install actions**: `_dotfiles_install_package`; Linux post_install: compat symlink `batcat→bat`
in `~/.local/bin/`

**pkg_doctor**: check `bat` (or `batcat`) binary; print version.

**pkg_clean**: bat theme cache at `$(bat --config-dir)/themes/` and `$(bat cache --build)` output.
Dry-run: report presence. `--force`: `bat cache --clear` (built-in command, safe).

**pkg_uninstall**:
- macOS: `brew uninstall bat`
- Linux apt: `sudo apt remove -y bat || sudo apt remove -y batcat`; remove compat symlink
  `~/.local/bin/bat`
- run `bat cache --clear` to remove compiled theme cache

### eza (`full/eza.zsh`)

**install actions**: `_dotfiles_install_package` only; no post_install.

**pkg_doctor**: check `eza` binary; print version.

**pkg_clean**: no runtime state — return 0 silently.

**pkg_uninstall**:
- macOS: `brew uninstall eza`
- Linux apt: `sudo apt remove -y eza`

### fd (`full/fd.zsh`)

**install actions**: `_dotfiles_install_package` (with `PKG_NAME=fd-find` on apt);
Linux post_install: compat symlink `fdfind→fd`.

**pkg_doctor**: check `fd` binary (or `fdfind`); print version.

**pkg_clean**: no runtime state — return 0 silently.

**pkg_uninstall**:
- macOS: `brew uninstall fd`
- Linux apt: `sudo apt remove -y fd-find`; remove compat symlink `~/.local/bin/fd`
- other Linux: `sudo dnf/yum/pacman remove fd` etc.

### fzf (`full/fzf.zsh`)

**install actions**: `_dotfiles_install_package`; no post_install.

**pkg_doctor**: check `fzf` binary; print version.

**pkg_clean**: no runtime state — return 0 silently.

**pkg_uninstall**:
- macOS: `brew uninstall fzf`
- Linux apt: `sudo apt remove -y fzf`

### jq (`full/jq.zsh`)

**install actions**: `_dotfiles_install_package` only.

**pkg_doctor**: check `jq` binary; print version.

**pkg_clean**: no runtime state — return 0 silently.

**pkg_uninstall**:
- macOS: `brew uninstall jq`
- Linux apt: `sudo apt remove -y jq`

### ripgrep (`full/ripgrep.zsh`)

**install actions**: `_dotfiles_install_package` only.

**pkg_doctor**: check `rg` binary; print version; check config file exists.

**pkg_clean**: no runtime state — return 0 silently.

**pkg_uninstall**:
- macOS: `brew uninstall ripgrep`
- Linux apt: `sudo apt remove -y ripgrep`

### tealdeer (`full/tealdeer.zsh`)

**install actions**: `_dotfiles_install_package`; post_install: `tldr --update`.

**pkg_doctor**: check `tldr` binary; print version; report cache freshness.

**pkg_clean**: tldr page cache (typically `~/.cache/tealdeer/`). Dry-run: report size.
`--force`: `tldr --clear-cache` or `rm -rf` the cache dir.

**pkg_uninstall**:
- clear cache first
- macOS: `brew uninstall tealdeer`
- Linux apt: `sudo apt remove -y tealdeer`

### vfox (`full/vfox.zsh`)

**install actions**: custom `pkg_install` (brew on macOS, apt Fury repo on Linux);
post_install: reads `~/.config/vfox/sdks` manifest, adds plugins, installs SDKs.

**pkg_doctor**: check `vfox` binary; print version; check SDK manifest exists;
list installed plugins and their active versions.

**pkg_clean**:
- dry-run: report vfox SDK download cache at `~/.version-fox/cache/` and size
- `--force`: remove `~/.version-fox/cache/`
- mise leftover hint (moved from hardcoded CLI): if `~/.local/share/mise` or
  `~/.config/mise` exist, warn. `--force`: remove them.

**pkg_uninstall**:
- `vfox remove --all` to deactivate all SDKs (if vfox available)
- remove `~/.version-fox/` (all vfox state)
- remove `~/.config/vfox/` (config dir, but NOT the dotfiles-managed sdks symlink —
  that gets removed by the symlink sweep in `uninstall_dotfiles`)
- macOS: `brew uninstall vfox`
- Linux apt: remove Fury apt source + keyring, `sudo apt remove -y vfox`
  (`/etc/apt/sources.list.d/versionfox.list`, `/etc/apt/keyrings/vfox.gpg`)

### zoxide (`full/zoxide.zsh`)

**install actions**: `_dotfiles_install_package` only; no post_install.

**pkg_doctor**: check `zoxide` binary; print version; check db file exists.

**pkg_clean**: zoxide database at `~/.local/share/zoxide/db.zo`. It is user data, not
cache — do NOT remove in dry-run or `--force`. Return 0 silently (nothing to clean).

**pkg_uninstall**:
- macOS: `brew uninstall zoxide`
- Linux apt: `sudo apt remove -y zoxide`
- Note: database `~/.local/share/zoxide/db.zo` is user-accumulated navigation history.
  Preserve by default; emit a hint about manual removal if the user wants it.

---

## Dispatcher Upgrade Design

```bash
_dispatch_pkg_hook() {
    local pkg_file="$1" hook_name="$2"
    local report_file=""
    local extra_env=""

    if [[ "$hook_name" == "pkg_uninstall" ]]; then
        report_file="$(mktemp)"
        extra_env="export _PKG_UNINSTALL_REPORT_FILE=\"$report_file\""
    fi

    zsh -c "
        export DOTFILES_ROOT=\"$DOTFILES_ROOT\"
        export DOTFILES_VERBOSE=\"${DOTFILES_VERBOSE:-false}\"
        $extra_env
        source \"$DOTFILES_ROOT/zsh/lib/log.sh\"
        source \"$DOTFILES_ROOT/zsh/lib/platform.zsh\"
        source \"$DOTFILES_ROOT/zsh/lib/installer.zsh\"
        _dotfiles_invoke_package_hook \"$pkg_file\" \"$hook_name\"
    "
    local rc=$?

    # Read failure report if hook wrote one
    if [[ -n "$report_file" && -f "$report_file" && $rc -ne 0 ]]; then
        local line key val
        while IFS='=' read -r key val; do
            case "$key" in
                ERROR)     _PKG_UNINSTALL_ERROR="$val" ;;
                REMAINING) _PKG_UNINSTALL_REMAINING="$val" ;;
                RECOVERY)  _PKG_UNINSTALL_RECOVERY="$val" ;;
            esac
        done < "$report_file"
    fi
    [[ -n "$report_file" ]] && rm -f "$report_file"

    return $rc
}
```

In `uninstall_dotfiles`, after each `_dispatch_pkg_hook` call that fails (rc not 0 and not 2),
read the populated bash-scope vars:

```bash
local err="${_PKG_UNINSTALL_ERROR:-rc=$rc}"
local rem="${_PKG_UNINSTALL_REMAINING:-see hook output above}"
local rec="${_PKG_UNINSTALL_RECOVERY:-investigate manually}"
failed_pkgs+=("$pkg_name|$err|$rem|$rec")
unset _PKG_UNINSTALL_ERROR _PKG_UNINSTALL_REMAINING _PKG_UNINSTALL_RECOVERY
```

Each `pkg_uninstall` hook writes the report file on its failure path:

```zsh
# Pattern every hook uses on failure:
if [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]]; then
    printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
        "brew uninstall failed" \
        "$(command -v toolname 2>/dev/null || echo 'unknown')" \
        "run: brew uninstall toolname" \
        > "$_PKG_UNINSTALL_REPORT_FILE"
fi
return 1
```

---

## Files to Change

| File | Action |
|------|--------|
| `bin/dotfiles` | Upgrade `_dispatch_pkg_hook` (platform.zsh + report-file wiring); upgrade `uninstall_dotfiles` failure aggregation |
| `zsh/packages/core/00-sheldon.zsh` | Add `pkg_doctor`, `pkg_clean`, `pkg_uninstall` |
| `zsh/packages/core/tmux.zsh` | Add `pkg_doctor`, `pkg_clean`, `pkg_uninstall` |
| `zsh/packages/full/bat.zsh` | Add `pkg_doctor`, `pkg_clean`, `pkg_uninstall` |
| `zsh/packages/full/eza.zsh` | Add `pkg_doctor`, `pkg_clean`, `pkg_uninstall` |
| `zsh/packages/full/fd.zsh` | Add `pkg_doctor`, `pkg_clean`, `pkg_uninstall` |
| `zsh/packages/full/fzf.zsh` | Add `pkg_doctor`, `pkg_clean`, `pkg_uninstall` |
| `zsh/packages/full/jq.zsh` | Add `pkg_doctor`, `pkg_clean`, `pkg_uninstall` |
| `zsh/packages/full/ripgrep.zsh` | Add `pkg_doctor`, `pkg_clean`, `pkg_uninstall` |
| `zsh/packages/full/tealdeer.zsh` | Add `pkg_doctor`, `pkg_clean`, `pkg_uninstall` |
| `zsh/packages/full/vfox.zsh` | Add `pkg_doctor`, `pkg_clean`, `pkg_uninstall` |
| `zsh/packages/full/zoxide.zsh` | Add `pkg_doctor`, `pkg_clean`, `pkg_uninstall` |

## NOT Changing

- `zshrc`, `zshenv`, `zsh/lib/*.zsh`, `zsh/core/*.zsh`
- Any docs or config files

---

## Validation Gates

1. `bash -n bin/dotfiles` — clean
2. `zsh -n` every modified package file — all clean
3. `dotfiles doctor` — each package prints a `_log_result` line
4. `dotfiles clean` — each package with state reports it; silent for others
5. `dotfiles clean --force` — safe removal (test with vfox cache if present)
6. `dotfiles doctor` exit code == 0 if all healthy
7. `env DOTFILES_VERBOSE=false zsh -i -c exit` — no log output from our code

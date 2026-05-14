# Phase 4 Report: Per-Package Hooks

## Summary

Implemented `pkg_doctor`, `pkg_clean`, and `pkg_uninstall` for all 11 package files.
Also upgraded `_dispatch_pkg_hook` in `bin/dotfiles` with two fixes required for the
hooks to work correctly.

---

## Dispatcher Upgrades (`bin/dotfiles`)

### Fix 1: platform.zsh sourced in subshell

`_dispatch_pkg_hook` previously sourced only `log.sh` and `installer.zsh`. Since
`installer.zsh` does not source `platform.zsh`, `dotfiles_os` and `dotfiles_pkg_manager`
were undefined in every hook subshell. Added `platform.zsh` to the source chain.

### Fix 2: `_PKG_UNINSTALL_*` temp-file propagation

Used option (b) from the spec. The dispatcher:
1. Creates a temp file (`mktemp`) for `pkg_uninstall` calls only.
2. Exports `_PKG_UNINSTALL_REPORT_FILE` into the zsh subshell.
3. On non-zero rc, reads `KEY=VALUE` lines from the file into bash-scope vars.
4. Unlinks the file.

`uninstall_dotfiles` reads `_PKG_UNINSTALL_ERROR`, `_PKG_UNINSTALL_REMAINING`,
`_PKG_UNINSTALL_RECOVERY` after each dispatch and populates the failure-summary
table with real context. Backward-compat fallback: if a hook exits non-zero without
writing the report file, the aggregator shows `rc=N|see hook output above|investigate manually`.

---

## Per-Package Hook Summary

| Package | `pkg_doctor` reports | `pkg_clean` cleans | `pkg_uninstall` reverses |
|---------|----------------------|--------------------|--------------------------|
| sheldon | binary version, plugins.toml presence | lock file + `~/.local/share/sheldon/` plugin cache | rm config dir + cache; brew/rm-binary on Linux |
| tmux | binary version, `.tmux.conf` symlink, TPM dir | non-TPM plugin dirs + resurrect sessions | rm `.tmux.conf` symlink, `~/.tmux/plugins/`; brew/apt/dnf/etc. |
| bat | binary version (bat or batcat) | `bat --config-dir` theme cache | `bat cache --clear`; brew/apt; rm compat symlink on Linux |
| eza | binary version | nothing (no state) | brew/apt/dnf/etc. |
| fd | binary version (fd or fdfind) | nothing (no state) | brew/apt (fd-find); rm compat symlink on Linux |
| fzf | binary version | nothing (no state) | brew/apt/dnf/etc. |
| jq | binary version | nothing (no state) | brew/apt/dnf/etc. |
| ripgrep | binary version + config path | nothing (no state) | brew/apt/dnf/etc. |
| tealdeer | binary version + cache freshness | `~/.cache/tealdeer/` page cache | clear cache + rm; brew/apt/etc. |
| vfox | binary version, SDK manifest, plugin list | `~/.version-fox/cache/` + mise leftover hint/removal | `vfox remove --all`; rm `~/.version-fox/`; brew uninstall / apt remove + Fury repo cleanup |
| zoxide | binary version + db path | nothing (db.zo is user data) | brew/apt/etc.; db preserved with hint to remove manually |

---

## vfox special case: mise leftover hint

As specified, the hardcoded mise-leftover hint that Phase 3 dropped from `clean_dotfiles`
is now in `vfox.zsh`'s `pkg_clean`. Dry-run: reports the dirs. `--force`: removes them.

---

## Validation Gates

| Gate | Description | Result | Evidence |
|------|-------------|--------|---------|
| 1 | `bash -n bin/dotfiles` | PASS | exits 0, no output |
| 2 | `zsh -n` on all 11 package files | PASS | all 11 exit 0 |
| 3 | `dotfiles doctor` per-package lines | PASS | all 11 packages output a `_log_result` line |
| 4 | `dotfiles clean` per-package state | PASS | sheldon, tmux plugins, resurrect sessions reported |
| 5 | `dotfiles clean --force` removes safely | PASS | synthetic tealdeer cache created + removed cleanly |
| 6 | `dotfiles doctor` exit code = issue count | PASS | rc=1 (tealdeer cache absent is a real issue) |
| 7 | `DOTFILES_VERBOSE=false zsh -i -c exit` silent | PASS | no `_dotfiles_log` or `[DEBUG]`/`[INFO]` output |

---

## Deviations and Decisions

- **tealdeer `tldr --clear-cache` is insufficient**: returns rc=0 but does not remove
  subdirectories. Fixed: always run `tldr --clear-cache` then `rm -rf` the cache dir.
- **vfox `--version` flag**: `vfox version` fails; correct flag is `vfox --version`.
  Fixed in `pkg_doctor`.
- **zoxide database**: `~/.local/share/zoxide/db.zo` is accumulated user navigation
  history, not a cache. `pkg_clean` returns 0 silently. `pkg_uninstall` preserves it
  and prints a hint with the manual removal command.
- **tealdeer doctor issue=1 on this machine**: the tldr page cache has never been
  populated. This is an accurate diagnosis, not a false positive.

---

## Dead Helper Candidates

`verify_all`, `verify_symlinks`, and `verify_packages` were flagged in the Phase 3
plan as candidates for removal. A grep audit shows:

- `verify_all` is defined but called only from the now-removed `verify` command.
- `verify_symlinks` and `verify_packages` are called internally by `install_dotfiles`
  (via `verify_all`) and by nothing else user-facing.

These are safe to remove in Phase 5 as part of the convention cleanup, but are not
trivially safe to remove here without tracing all callers. Flagging for Phase 5.

---

*Generated: 2026-05-14*

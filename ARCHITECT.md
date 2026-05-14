# ARCHITECT.md — Architecture Reference

---

## Boot sequence

```
zsh -i
  └── zshenv          # exports DOTFILES_ROOT, DOTFILES_PROFILE, DOTFILES_VERBOSE, LANG, LC_ALL
        └── zshrc
              ├── validate DOTFILES_ROOT and DOTFILES_ROOT/zsh exist (exit on fail)
              ├── source zsh/core/*.zsh  (numeric order: 10 20 30 40 50 60)
              ├── source zsh/lib/platform.zsh
              ├── source zsh/lib/installer.zsh  (sources log.sh internally)
              └── for each package file in active profile dirs:
                    source <pkg>.zsh
                      └── init_package_template "$PKG_NAME"
                            ├── if installed → pkg_init, then pkg_post_install (install mode only)
                            └── if not installed and DOTFILES_INSTALL=true → full install flow
```

`zshenv` is sourced by all zsh instances (interactive and non-interactive).
`zshrc` is the interactive entry point and is under 45 lines.

### Core modules (`zsh/core/`)

Loaded on every shell start, before packages:

| File | Purpose |
|------|---------|
| `10-options.zsh` | `setopt` flags, `PATH` additions (`$DOTFILES_ROOT/bin`, `~/.local/bin`), `TERM` |
| `20-history.zsh` | History size, dedup, sharing settings |
| `30-completion.zsh` | `zstyle` completion config (compinit runs in `sheldon.zsh:pkg_init`) |
| `40-aliases.zsh` | Shell reload (`zshsrc`), editor (`zshedit`), navigation (`..`, `...`) |
| `50-theme.zsh` | Powerlevel10k theme load |
| `60-zcompile.zsh` | Async zsh bytecode compilation |

---

## Profile system

Profiles are declared in `zshrc` and mirrored in `bin/dotfiles:_iter_profile_packages`.

```zsh
case "${DOTFILES_PROFILE}" in
    core|minimal)
        _pkg_dirs=("$DOTFILES_ROOT/zsh/packages/core") ;;
    full|server)
        _pkg_dirs=("$DOTFILES_ROOT/zsh/packages/core"
                   "$DOTFILES_ROOT/zsh/packages/full") ;;
    *)  # unknown profile — falls back to core, prints warning
esac
```

`full` is cumulative: it loads `core/` then `full/`. There is no profile that
loads only `full/` packages.

### Legacy migration

`bin/dotfiles:set_defaults` runs a one-time migration on startup:

```bash
case "${DOTFILES_PROFILE:-}" in
    minimal) _migrated_profile="core" ;;
    server)  _migrated_profile="full" ;;
esac
```

If migration fires, the new name is written to `~/.zshenv` via `save_config`.
`zshrc` also accepts the legacy names for one release (same `case` pattern).

---

## Package contract

Every package file ends with `init_package_template "$PKG_NAME"`. The orchestrator
in `zsh/lib/installer.zsh` calls hooks in this order:

### Startup flow (automatic)

```
init_package_template
  │
  ├── _dotfiles_check_installed (PKG_CHECK_FUNC or command -v PKG_CMD)
  │
  ├── [installed]
  │     ├── pkg_init
  │     └── pkg_post_install  (only if DOTFILES_INSTALL=true)
  │
  └── [not installed + DOTFILES_INSTALL=true]
        ├── pkg_pre_install
        ├── pkg_install  (or _dotfiles_install_package if not defined)
        ├── pkg_post_install
        ├── re-verify installation
        └── pkg_init
```

When not installed and `DOTFILES_INSTALL=false` (normal shell start): prints a
warning and returns 0 — shell continues loading remaining packages.

### All 8 hooks

| Hook | Tier | Required | When called |
|------|------|----------|-------------|
| `pkg_pre_install` | startup | No | Before install. May mutate `PKG_NAME`, `PKG_CMD`. |
| `pkg_install` | startup | No | Install the binary. Absent → OS pkg manager fallback. |
| `pkg_install_fallback` | startup | No | Called by `_dotfiles_install_package` when pkg manager is `unknown`. |
| `pkg_post_install` | startup | No | Post-install sync (config, lock files, SDK provisioning). Also re-runs on `dotfiles install` for already-installed packages. |
| `pkg_init` | startup | No | Shell init (aliases, env vars, `eval` hooks). Runs every shell start. |
| `pkg_clean` | CLI | No | Declare and optionally remove cache/leftover state. Reads `${DOTFILES_CLEAN_FORCE:-}`. |
| `pkg_doctor` | CLI | No | Read-only health checks. Return N = number of issues. |
| `pkg_uninstall` | CLI | **Yes** | Reverse of `pkg_install`. Must be OS-aware. |

Return code `2` from a CLI hook means "hook not defined". `pkg_clean` and
`pkg_doctor` silently skip on `2`. `pkg_uninstall` treats `2` as a hard error.

---

## CLI hook dispatch

`bin/dotfiles` cannot source `.zsh` files directly (it is bash). It delegates
each hook invocation to a zsh subprocess:

```bash
# _dispatch_pkg_hook <pkg_file> <hook_name>
DOTFILES_ROOT="$DOTFILES_ROOT" \
DOTFILES_VERBOSE="${DOTFILES_VERBOSE:-false}" \
_PKG_UNINSTALL_REPORT_FILE="$report_file" \
zsh -c '
    source "$DOTFILES_ROOT/zsh/lib/log.sh"
    source "$DOTFILES_ROOT/zsh/lib/platform.zsh"
    source "$DOTFILES_ROOT/zsh/lib/installer.zsh"
    _dotfiles_invoke_package_hook "$1" "$2"
' _dispatch_pkg_hook "$pkg_file" "$hook_name"
```

Values are passed through the environment and positional args — never
string-interpolated into the `-c` body (prevents injection from paths with
spaces or quotes).

### `DOTFILES_HOOK_ONLY` mode

`_dotfiles_invoke_package_hook` sources the package file with
`DOTFILES_HOOK_ONLY=true`. When set, `init_package_template` returns immediately
at its first line — only the hook function definitions are loaded. The named
hook is then called directly.

### `pkg_uninstall` IPC

For `pkg_uninstall`, the dispatcher creates a temp file and exports its path as
`_PKG_UNINSTALL_REPORT_FILE`. On failure, the hook writes:

```
ERROR=<what went wrong>
REMAINING=<files/paths still on disk>
RECOVERY=<command to finish manually>
```

The dispatcher reads these back into bash-scope variables
(`_PKG_UNINSTALL_ERROR`, `_PKG_UNINSTALL_REMAINING`, `_PKG_UNINSTALL_RECOVERY`)
and includes them in the failure summary table printed by `uninstall_dotfiles`.

### Package iteration order

`_iter_profile_packages` emits package file paths in alphabetical order (shell
glob). `uninstall_dotfiles` reverses this with a counter loop so packages are
torn down in reverse install order.

---

## Full package template

Based on `zsh/packages/core/sheldon.zsh` — the canonical 8-hook implementation.

```zsh
#!/usr/bin/env zsh

PKG_NAME="toolname"
PKG_DESC="One-line description"

# Optional: override binary name used for install check
# PKG_CMD="toolname-bin"

# Optional: replace command -v check with a custom function
# PKG_CHECK_FUNC="_toolname_is_installed"
# _toolname_is_installed() { ... }

pkg_pre_install() {
    # Optional. Runs before install. May modify PKG_NAME / PKG_CMD.
    # Engine re-reads those variables after this returns.
    :
}

pkg_install() {
    # Optional. If absent, falls back to _dotfiles_install_package.
    local os pkg_mgr
    os="$(dotfiles_os)"
    pkg_mgr="$(dotfiles_pkg_manager)"

    case "$pkg_mgr" in
        brew)   brew install toolname ;;
        apt)    sudo apt-get install -y toolname ;;
        *)      pkg_install_fallback || return 1 ;;
    esac
}

pkg_install_fallback() {
    # Only called when dotfiles_pkg_manager returns "unknown".
    # Never pipe curl to bash directly.
    local sha256="<pin this>"
    _dotfiles_safe_run_installer \
        "https://example.com/install.sh" "$sha256"
}

pkg_post_install() {
    # Runs after install AND on re-install (DOTFILES_INSTALL=true) for
    # already-installed packages. Must be idempotent.
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/toolname"
    ensure_directory "$config_dir"
    copy_if_missing "${DOTFILES_ROOT}/config/toolname/config.toml" \
                    "${config_dir}/config.toml"
}

pkg_init() {
    # Runs every shell start. Must be fast (< 5ms).
    # Use a load flag for any eval-based init to prevent re-sourcing.
    [[ "${_DOTFILES_TOOLNAME_LOADED:-}" == "1" ]] && return 0

    eval "$(toolname init zsh)" || {
        _dotfiles_log_error "toolname init failed"
        return 1
    }

    alias t="toolname --flag"
    _DOTFILES_TOOLNAME_LOADED="1"   # NOT exported — must reset on exec zsh
    return 0
}

pkg_clean() {
    # Optional. Reads DOTFILES_CLEAN_FORCE. Dry-run unless == "--force".
    local cache_dir="$HOME/.cache/toolname"
    local force="${DOTFILES_CLEAN_FORCE:-}"

    [[ -d "$cache_dir" ]] || return 0
    _dotfiles_log_detail "toolname: cache at $cache_dir"

    if [[ "$force" == "--force" ]]; then
        rm -rf "$cache_dir"
        _dotfiles_log_detail "toolname: removed cache"
    fi
    return 0
}

pkg_doctor() {
    # Optional. Return N = number of issues found.
    local issues=0
    if command -v toolname &>/dev/null; then
        _dotfiles_log_result "toolname" "$(toolname --version 2>/dev/null | head -1)"
    else
        _dotfiles_log_result "toolname" "NOT FOUND"
        ((issues++))
    fi
    return $issues
}

pkg_uninstall() {
    # REQUIRED. Must reverse pkg_install exactly. Must be OS-aware.
    # On failure, write to $_PKG_UNINSTALL_REPORT_FILE before return 1.
    local pkg_mgr
    pkg_mgr="$(dotfiles_pkg_manager)"

    local cmd=""
    case "$pkg_mgr" in
        brew)   cmd="brew uninstall toolname" ;;
        apt)    cmd="sudo apt-get remove -y toolname" ;;
        *)
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && \
                printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                    "Unknown package manager" \
                    "$(command -v toolname 2>/dev/null || echo unknown)" \
                    "Remove toolname via your system package manager" \
                    > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1 ;;
    esac

    if ! eval "$cmd" 2>/dev/null; then
        [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && \
            printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "$cmd failed" \
                "$(command -v toolname 2>/dev/null || echo unknown)" \
                "run: $cmd" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
        return 1
    fi
    return 0
}

init_package_template "$PKG_NAME"
```

---

## Logging — two-tier model

See [CLAUDE.md](CLAUDE.md) for the helper reference table. The architectural
rationale:

- **Shell startup is silent by default.** `pkg_init` and startup-path code use
  only Tier 2 (verbose-only) helpers. A normal `zsh -i -c exit` produces no output.
- **CLI commands are always informative.** `doctor`, `clean`, `uninstall` use
  Tier 1 (always-print) helpers. Users see progress without needing `-v`.
- **`DOTFILES_VERBOSE=true`** enables Tier 2 in both contexts — full trace for
  debugging startup timing or install failures.

`log.sh` is POSIX sh so it can be sourced by bash (`bin/dotfiles`) without
a zsh subprocess. Colors are suppressed when stdout is not a TTY or `NO_COLOR`
is set.

---

## Safe installer helpers

Defined in `zsh/lib/installer.zsh`. Never pipe curl directly to bash.

### `_dotfiles_safe_run_installer <url> <sha256> [-- args]`

Downloads to a temp file, verifies SHA256, executes with `bash`. Temp file
is deleted on exit (success or failure).

### `_dotfiles_safe_sudo_run_installer <url> <sha256> [-- args]`

Same but executes with `sudo bash`. Used by `sheldon.zsh` on Linux.

### `_dotfiles_safe_git_clone <url> <ref> <expected_sha> <dest>`

- If `ref` is a 40-char hex SHA: partial clone (`--filter=blob:none`) then
  checkout. Faster for pinned commits.
- Otherwise: shallow clone (`--branch <ref> --depth 1`).
- Verifies the resulting `HEAD` matches `expected_sha`. Removes `dest` on mismatch.

### `_dotfiles_verify_sha256 <file> <expected>`

Uses `sha256sum` (Linux) or `shasum -a 256` (macOS). Aborts with a clear error
on mismatch or when neither tool is available.

---

## Verbose env-override mechanism

`save_config` writes `~/.zshenv` using the `${VAR:-value}` fallback pattern:

```bash
export DOTFILES_VERBOSE="${DOTFILES_VERBOSE:-false}"
```

This means if `DOTFILES_VERBOSE=true` is set in the environment before zsh
starts, that value wins over the saved default. `extract_config_value` in
`bin/dotfiles` detects this pattern (via string matching, no `eval`) and
resolves it correctly when reading config back.

---

## Sheldon weekly auto-refresh

In `zsh/packages/core/sheldon.zsh:pkg_init`:

```zsh
local lock_file="${XDG_DATA_HOME:-$HOME/.local/share}/sheldon/plugins.lock"
if [[ -n ${lock_file}(#qN.md+7) ]]; then
    ( "$sheldon_bin" lock --update &>/dev/null & ) 2>/dev/null
fi
```

The zsh glob qualifier `(#qN.md+7)` matches the file only if it is older than
7 days. The update runs detached in a subshell — zero impact on startup time.
The new lock takes effect on the next shell open.

The lock file path is `$XDG_DATA_HOME/sheldon/plugins.lock` (not
`$XDG_CONFIG_HOME`) because sheldon stores its lock under the data home.
`compinit` is also called here (not in `30-completion.zsh`) because
zsh-completions must be in `fpath` first, which sheldon provides.

---

## vfox manifest sync

`config/vfox/sdks` is symlinked to `~/.config/vfox/sdks`. Format: one
`plugin@version` per line, comments with `#`.

`pkg_post_install` in `zsh/packages/full/vfox.zsh` reads this file and for
each entry:

1. Adds the plugin if not already registered (`vfox add`).
2. Resolves `@latest` to the newest **stable** version using
   `_vfox_resolve_latest_stable` (filters lines matching `alpha|beta|rc|dev|pre|b[0-9]`
   from `vfox search` output).
3. Installs the resolved version (`vfox install`).
4. Sets it as global in a child zsh: `DOTFILES_INSTALL=false zsh -ic "vfox use -g ..."`.

`DOTFILES_INSTALL=false` in the child shell is critical — without it the child
sources `zshrc`, loads vfox's package file with `DOTFILES_INSTALL=true`, and
re-enters `pkg_post_install`, spawning another child zsh indefinitely.

`@lts` is not a vfox alias and is not handled — use a concrete version for LTS
pinning. `rust` is intentionally absent from the manifest; use `rustup` directly.

---

## Auto-sync on `dotfiles install`

`zsh/lib/installer.zsh:init_package_template` checks `DOTFILES_INSTALL`:

```zsh
if [[ "${DOTFILES_INSTALL:-false}" == "true" ]] && typeset -f pkg_post_install >/dev/null; then
    pkg_post_install || _dotfiles_log_warning "Post-install re-sync failed for ${package_name}"
fi
```

This branch runs even when the package is already installed. Every
`dotfiles install` therefore re-syncs: sheldon plugin lock, tmux TPM, vfox
SDK manifest, and any other state managed by `pkg_post_install`. Hooks must
be idempotent.

---

## Platform detection

`zsh/lib/platform.zsh` exposes three cached functions:

| Function | Returns | Cache variable |
|----------|---------|----------------|
| `dotfiles_os` | `macos`, `linux`, `freebsd`, `unknown` | `_DOTFILES_OS_CACHE` |
| `dotfiles_distro` | distro ID from `/etc/os-release`, or `unknown` | `_DOTFILES_DISTRO_CACHE` |
| `dotfiles_pkg_manager` | `brew`, `apt`, `dnf`, `yum`, `pacman`, `zypper`, `pkg`, `unknown` | `_DOTFILES_PKG_MGR_CACHE` |

Results are cached in module-level variables after first call. Safe to call
multiple times in a session.

---

## Architectural decisions

| Decision | Rationale |
|----------|-----------|
| Bash for CLI, zsh for packages | `bin/dotfiles` runs before zsh is configured and must work on bare Debian. Zsh-specific syntax (`typeset`, glob qualifiers) cannot be used there. |
| One file per package | Adding a tool requires exactly one new file and zero core changes. Removal is `rm <file>`. No manifest to keep in sync. |
| Optional startup hooks, required `pkg_uninstall` | Startup hooks are additive — a missing one degrades gracefully. `pkg_uninstall` is destructive; leaving it undefined would silently skip teardown, which is worse than failing loudly. |
| Cumulative profile model (not independent sets) | Reduces duplication and ensures `full` always has a working `core` base. A machine can upgrade from `core` to `full` without re-running core install steps. |
| No declarative manifest / no lock file | State lives in `~/.zshenv` (one var) and `config/vfox/sdks` (SDK versions). The package directory itself is the manifest. A separate lock file would add sync complexity for minimal benefit on a single-machine config. |

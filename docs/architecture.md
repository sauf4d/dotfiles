# Architecture

## Overview

The system has four layers. Each layer has a single, clear responsibility:

```
┌─────────────────────────────────────────────────────────────┐
│  bin/dotfiles      Bash CLI — symlinks, install, update     │
├─────────────────────────────────────────────────────────────┤
│  zshrc             Entry point — sources core/ and pkgs     │
├───────────────────────────┬─────────────────────────────────┤
│  zsh/core/                │  zsh/lib/                       │
│  Sequential shell config  │  Shared library functions       │
├───────────────────────────┴─────────────────────────────────┤
│  zsh/packages/<tier>/     One file per tool, profile-gated  │
└─────────────────────────────────────────────────────────────┘
```

---

## Directory Structure

Current directory structure:

```
.dotfiles/
├── bin/
│   └── dotfiles                    # Bash CLI: install, update, uninstall, verify, profile
│
├── config/                         # Tool configs → symlinked to ~/.config/<tool>/
│   ├── bat/                        # bat theme + config
│   ├── ripgrep/                    # ripgreprc default flags
│   ├── sheldon/
│   │   └── plugins.toml            # Sheldon plugin manager config
│   ├── skhd/                       # macOS hotkey daemon (not a managed package)
│   ├── tealdeer/                   # tldr cache config
│   └── yabai/                      # macOS tiling WM (not a managed package)
│
├── docs/
│   └── architecture.md             # System design + appendices (requirements, adding a package, troubleshooting)
│
├── zsh/                            # All zsh configuration
│   ├── core/                       # Always-loaded modules, run in numeric order
│   │   ├── 10-options.zsh          # Shell options (setopt)
│   │   ├── 20-history.zsh          # History settings + fzf history keybinding
│   │   ├── 30-completion.zsh       # zstyle declarations only (compinit runs in 00-sheldon.zsh)
│   │   ├── 40-aliases.zsh          # Shell shortcuts (cd, reload); tool aliases live in packages
│   │   ├── 50-theme.zsh            # Powerlevel10k instant prompt + theme load
│   │   └── 60-zcompile.zsh         # Background .zwc bytecode compilation
│   │
│   ├── lib/                        # Shared libraries — sourced before packages
│   │   ├── installer.zsh           # Package lifecycle engine + logging + utilities
│   │   └── platform.zsh            # OS/distro detection helpers
│   │
│   └── packages/                   # One .zsh file per tool, grouped by tier
│       ├── minimal/
│       │   ├── 00-sheldon.zsh      # Plugin manager — must load first (order prefix required)
│       │   └── tmux.zsh
│       └── server/
│           ├── bat.zsh
│           ├── eza.zsh
│           ├── fd.zsh
│           ├── fzf.zsh
│           ├── jq.zsh
│           ├── vfox.zsh
│           ├── ripgrep.zsh
│           ├── tealdeer.zsh
│           └── zoxide.zsh
│
├── p10k.zsh                        # Powerlevel10k config → ~/.p10k.zsh
├── tmux.conf                       # Tmux config → ~/.tmux.conf
├── zshrc                           # Shell entry point → ~/.zshrc
└── zshenv                          # Dotfiles env vars → ~/.zshenv
```

**Key design decisions:**
- All zsh logic lives under `zsh/`; root-level `zshrc` is a thin entry point.
- Packages are grouped in subdirectories by tier — no magic number prefixes needed.
- `zsh/lib/` has exactly two files, each with a single responsibility.

---

## Shell Startup Flow

```
~/.zshenv  →  zshenv
  └── Exports DOTFILES_ROOT, DOTFILES_PROFILE, DOTFILES_VERBOSE, LANG

~/.zshrc  →  zshrc
  │
  ├── 1. Source zsh/core/*.zsh  (alphabetical = numeric order)
  │       10-options.zsh     — setopt (extended_glob, auto_cd, etc.)
  │       20-history.zsh     — HISTFILE, HISTSIZE, fzf Ctrl-R binding
  │       30-completion.zsh  — zstyle declarations ONLY (no compinit call here)
  │       40-aliases.zsh     — shell shortcuts (cd, reload); tool aliases live in packages
  │       50-theme.zsh       — Powerlevel10k instant prompt + p10k load
  │       60-zcompile.zsh    — background .zwc bytecode compilation
  │
  ├── 2. Source zsh/lib/installer.zsh   — package lifecycle engine
  │       Source zsh/lib/platform.zsh   — OS/distro detection
  │
  └── 3. Load packages for active profile:
          minimal tier:  always loaded
          server tier:   loaded when DOTFILES_PROFILE = server
          │
          Each package file calls init_package_template, which either:
            (a) Tool installed     → run pkg_init
            (b) Tool missing       → print one-line warning, skip
            (c) DOTFILES_INSTALL=true → run full install flow (install + init)
```

**Key invariant**: Installation never happens on normal shell startup.
`DOTFILES_INSTALL=true` is the exclusive gate for all installation logic;
`DOTFILES_VERBOSE` controls only logging verbosity.

---

## Profile System

Profiles are **cumulative** — each tier includes all lower tiers:

| Profile   | Tiers loaded | Packages directory |
|-----------|-------------|-------------------|
| `minimal` | `minimal`   | `zsh/packages/minimal/` |
| `server`  | `minimal` + `server` | + `zsh/packages/server/` |

The profile is read from `$DOTFILES_PROFILE` at shell startup.
To switch: `dotfiles profile server` (persists to `~/.zshenv`), then `source ~/.zshrc`.

---

## Package System

### File Naming

```
zsh/packages/<tier>/<name>.zsh

tier — minimal | server
name — tool name, lowercase, hyphens allowed (e.g. fzf, ripgrep, vfox)
```

Files within a tier directory load in **alphabetical order**.

**Ordering contracts:**
- `minimal/00-sheldon.zsh` uses a numeric prefix to lock its load position before any
  other package in the tier. The plugin system depends on this — sheldon must source
  before anything that registers completions, hooks, or PATH modifications.
- **Rule**: If a package has a strict load-order requirement, prefix its filename with a
  two-digit number (`00-` for must-load-first, `99-` for must-load-last). Plain names
  follow natural alphabetical order.
- Non-ordered packages in `server/` use plain names — they have no cross-dependencies
  and alphabetical order is acceptable.

### Package Lifecycle API

```zsh
#!/usr/bin/env zsh

PKG_NAME="toolname"          # Used in all log messages and install prompts
PKG_DESC="Short description" # Shown when tool is not installed
PKG_CMD="toolname"           # Binary to check with `command -v` (defaults to PKG_NAME)
                             # Set to "" to use a custom check (see PKG_CHECK_FUNC)

# Custom existence check — use when the tool is not a standard binary
# Must be a function name that returns 0 if installed, 1 if not
PKG_CHECK_FUNC=""

# Optional: runs before installation
pkg_pre_install() { }

# Optional: custom installer — overrides the OS package manager
# Use for tools not in standard repos (curl installers, git clone, etc.)
pkg_install() { }

# Optional: custom fallback for unsupported Linux distros
# Called when the detected distro has no known package manager
pkg_install_fallback() { }

# Optional: runs after successful first installation
pkg_post_install() { }

# Optional: runs on every shell start when the tool IS installed
# Keep this fast — it runs synchronously on every shell open
pkg_init() { }

init_package_template "$PKG_NAME"
```

**Rules:**
- All hook functions are optional — omit them if not needed.
- `pkg_init` runs on every shell startup — keep it under 5 ms.
- `pkg_install` fully overrides the default package manager — use it for custom install scripts.
- `pkg_install_fallback` is the escape hatch for unknown Linux distros.
- Packages with `eval`-based init must guard with a `_DOTFILES_<TOOL>_LOADED` flag.

**Hook function scope**: Each package file's hook functions (`pkg_init`, `pkg_install`, etc.)
are defined as global shell functions. They are **not automatically unset** after
`init_package_template` returns. The next package file's hooks overwrite the previous
definitions — this works correctly only because package files process sequentially.
Do not define hook functions outside package files, and do not rely on hooks from
a previously loaded package.

### Package Lifecycle Flow

```
init_package_template "pkgname"
  │
  ├── Check if tool is installed:
  │     PKG_CHECK_FUNC defined → call it
  │     otherwise              → command -v PKG_CMD
  │
  ├── Tool IS installed:
  │     → run pkg_init  (every shell start)
  │     → done
  │
  └── Tool NOT installed:
        DOTFILES_INSTALL != true:
          → print: "[dotfiles] <name> not installed — run: dotfiles install"
          → done (non-blocking)
        DOTFILES_INSTALL = true:
          → run pkg_pre_install (if defined)
          → run pkg_install (if defined)
              else: call platform installer
                    if distro unknown: call pkg_install_fallback (if defined)
                    else: print actionable error, return 1
          → verify install (re-run check)
          → run pkg_post_install (if defined)
          → run pkg_init
          → done
```

### Standard Package Example

```zsh
#!/usr/bin/env zsh

PKG_NAME="bat"
PKG_DESC="A cat clone with syntax highlighting and Git integration"

pkg_post_install() {
    # Ubuntu/Debian ships bat as 'batcat' — create a compat symlink
    [[ "$(uname -s)" == "Linux" ]] && ! command -v batcat &>/dev/null && \
        create_symlink "$(command -v bat)" "/usr/local/bin/batcat"
}

pkg_init() {
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
}

init_package_template "$PKG_NAME"
```

### Custom Installer Example

A package may declare a `pkg_install` hook when its install steps differ per
platform (e.g. signed apt repository on Debian, Homebrew on macOS, upstream
curl installer elsewhere). Use the `dotfiles_os` and `dotfiles_pkg_manager`
helpers to branch:

```zsh
#!/usr/bin/env zsh

PKG_NAME="example"
PKG_DESC="Short description"

pkg_install() {
    local os="$(dotfiles_os)"
    local pkg_mgr="$(dotfiles_pkg_manager)"

    if [[ "$os" == "macos" ]] && [[ "$pkg_mgr" == "brew" ]]; then
        brew install "$PKG_NAME" || return 1
    elif [[ "$pkg_mgr" == "apt" ]]; then
        # Custom apt repo / signed keyring setup, then:
        sudo apt-get install -y "$PKG_NAME" || return 1
    else
        # Upstream installer fallback
        curl --proto '=https' --tlsv1.2 -fsSL https://example.com/install.sh | sh || return 1
    fi
}

pkg_init() {
    # Idempotency guard for any eval-based activation
    [[ "${_DOTFILES_EXAMPLE_LOADED:-}" == "1" ]] && return 0
    eval "$(example activate zsh)"
    export _DOTFILES_EXAMPLE_LOADED="1"
}

init_package_template "$PKG_NAME"
```

### Custom Distro Fallback Example

```zsh
#!/usr/bin/env zsh

PKG_NAME="fd"
PKG_DESC="A fast alternative to find"

pkg_install_fallback() {
    # Handles Alpine, NixOS, or any other unknown distro via prebuilt musl binary
    local version="10.1.0"
    local arch="$(uname -m)"
    local url="https://github.com/sharkdp/fd/releases/download/v${version}/fd-v${version}-${arch}-unknown-linux-musl.tar.gz"

    # Security: verify checksum before extracting
    local expected_sha="<sha256-of-the-tarball>"
    local tmpfile="$(mktemp)"
    curl -fsSL "$url" -o "$tmpfile"
    echo "${expected_sha}  ${tmpfile}" | sha256sum --check --quiet || {
        rm -f "$tmpfile"
        echo "[dotfiles] Checksum verification failed for fd" >&2
        return 1
    }
    tar -xz --strip-components=1 -C /usr/local/bin -f "$tmpfile" fd-*/fd
    rm -f "$tmpfile"
}

init_package_template "$PKG_NAME"
```

> **Security note**: Never use bare `curl | sh` or `curl | bash` in `pkg_install_fallback`.
> Always download to a temp file and verify a checksum before extracting or executing.
> For tools that provide signed releases, prefer GPG verification over SHA256.

---

## Shared Libraries (`zsh/lib/`)

### `installer.zsh`

Sourced in `zshrc` before any package files. Provides:

| Function | Purpose |
|----------|---------|
| `init_package_template` | Package lifecycle orchestrator (check → warn/install → init) |
| `is_package_installed cmd` | Returns 0 if `cmd` is in PATH and executable |
| `_dotfiles_install_package name` | Delegates to the detected OS package manager |
| `_dotfiles_log_info/debug/warning/error/success msg` | Leveled logging (`error` always shown; others only when `VERBOSE=true`) |
| `ensure_directory path` | `mkdir -p` with error suppression |
| `copy_if_missing src dst` | Copies only if destination does not exist |
| `create_symlink target link` | `ln -sf` wrapper; skips if link already exists |

> **Important**: `is_package_installed` uses `command -v`. It does **not** work for
> shell-function-based tools. Those must set `PKG_CHECK_FUNC`.

### `platform.zsh`

Sourced in `zshrc` before any package files. Provides:

| Function | Returns | Example |
|----------|---------|---------|
| `dotfiles_os` | `macos` \| `linux` \| `freebsd` \| `unknown` | `macos` |
| `dotfiles_distro` | Distro ID from `/etc/os-release` or `unknown` | `ubuntu` |
| `dotfiles_pkg_manager` | Package manager name or `unknown` | `brew` |

Used internally by `_dotfiles_install_package`. Package files can also call these
directly for platform-specific `pkg_post_install` logic.

---

## Plugin Management (Sheldon)

Zsh plugins are managed by [sheldon](https://sheldon.cli.rs).
Config lives at `config/sheldon/plugins.toml` (symlinked to `~/.config/sheldon/plugins.toml`).

Plugin load order:

| # | Plugin | Deferred? | Purpose |
|---|--------|-----------|---------|
| 1 | `zsh-defer` | No | Deferred loading utility |
| 2 | `fast-syntax-highlighting` | No | Command syntax highlighting |
| 3 | `zsh-completions` | **No** | Adds to `fpath` — must precede `compinit` |
| 4 | `fzf-tab` | Yes | fzf-powered tab completion UI |
| 5 | `zsh-autosuggestions` | Yes | Fish-style inline suggestions |
| 6 | `k` | Yes | Colorized directory listings |
| 7 | `ni` | Yes | Package manager detection |
| 8 | `powerlevel10k` | No | Prompt theme (loaded immediately) |

**`compinit` ordering**: `compinit` must run **after** `zsh-completions` adds its entries
to `fpath`. It is called in `00-sheldon.zsh`'s `pkg_init`, immediately after
`eval "$(sheldon source)"`. The `zsh/core/30-completion.zsh` file contains only
`zstyle` declarations — no `compinit` call.

**`.zcompdump` rebuild logic** (in `packages/minimal/00-sheldon.zsh`'s `pkg_init`):
```zsh
autoload -Uz compinit
# Rebuild the dump at most once per day; use cached otherwise
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
    compinit        # full rebuild
else
    compinit -C     # use cached dump, skip security check
fi
```
Do not remove this guard — rebuilding on every startup adds ~100ms.

---

## `bin/dotfiles` CLI Internals

The CLI is a Bash script. Each subcommand delegates to an internal function.

### `dotfiles install`

1. Sets `DOTFILES_VERBOSE=true` and sources `~/.zshrc` in a subshell
2. The package lifecycle runs for every package in the active profile
3. Any package not installed triggers the full install flow
4. Exits with 0 only if all packages initialize successfully

### `dotfiles update`

1. Checks `git status` — aborts with a warning if the working tree is dirty
2. Runs `git pull --ff-only origin $DOTFILES_BRANCH`
3. On success, runs `dotfiles install` to pick up new packages
4. On merge conflict or non-fast-forward: prints error and exits 1

### `dotfiles profile <name>`

1. Validates `<name>` is one of `minimal`, `server`
2. Updates `DOTFILES_PROFILE=<name>` in `~/.zshenv`:
   - If the line already exists: replaces it with `sed -i`
   - If it does not exist: appends it
3. Prints: `Profile set to <name>. Run: source ~/.zshrc`

### `dotfiles verify`

Runs three checks and reports each finding:

| Check | Pass condition |
|-------|----------------|
| Symlink exists | `~/.zshrc` is a symlink |
| Symlink target | Symlink points into `$DOTFILES_ROOT` |
| Target file exists | The file at the symlink destination exists |

Also checks each package in the active profile and reports which are not installed.

### `dotfiles uninstall`

1. Removes all symlinks created by this repo (checks that each symlink points into `$DOTFILES_ROOT` before removing)
2. Removes `DOTFILES_ROOT`, `DOTFILES_PROFILE`, `DOTFILES_VERBOSE` lines from `~/.zshenv`
3. Does **not** uninstall packages installed by `dotfiles install` — those are left for the user to remove manually

---

## Symlink Management

`bin/dotfiles` manages two symlink categories:

| Source | Target | Example |
|--------|--------|---------|
| `$DOTFILES_ROOT/<file>` | `$HOME/.<file>` | `zshrc` → `~/.zshrc` |
| `$DOTFILES_ROOT/config/<tool>/` | `$HOME/.config/<tool>/` | `config/bat/` → `~/.config/bat/` |

Files excluded from symlinking:

```
README.md   CHANGELOG.md   CLAUDE.md
docs/       scripts/       bin/
.git/       .gitignore     *.zwc
```

**Conflict handling**: If a target path already exists and is not a symlink pointing to
this repo — the CLI removes it and creates the new symlink. The `verify` command checks
for broken symlinks after the fact.

---

## Cross-Platform Notes

| Feature | macOS | Linux |
|---------|-------|-------|
| Package manager | Homebrew | apt / dnf / pacman / zypper |
| zsh availability | System-provided (5.9+) | Must install (`apt install zsh`) |
| `bat` binary name | `bat` | `bat` or `batcat` (handled in `pkg_post_install`) |
| Version manager install | Package manager (e.g. `brew install vfox`) | Signed apt repo or upstream curl installer |
| yabai / skhd | Config files only | Not applicable |
| Unknown distro | n/a (brew covers all) | `pkg_install_fallback` (FR-7) |

---

## Debugging and Verification

```zsh
# Measure shell startup time (3-run average, discard first)
for i in 1 2 3; do time zsh -i -c exit; done

# See full install/init log for all packages
DOTFILES_VERBOSE=true zsh -i -c exit

# Check symlink state
dotfiles verify

# See which packages have warnings (not installed)
zsh -i -c exit 2>&1 | grep '\[dotfiles\]'

# Force zcompdump rebuild (run after adding new completions)
rm -f ~/.zcompdump && exec zsh
```

---

## Appendix A: System Requirements

### Project Goals

A cross-platform, profile-based zsh configuration system that:

- Starts fast — lazy loading keeps shell startup under 200ms
- Works identically on macOS and common Linux distros
- Scales from a minimal server setup to a full development environment
- Warns clearly when a managed tool is missing, without blocking startup
- Is easy to extend with new tools without touching any core file

### Non-Goals

- GUI / desktop environment configuration (yabai/skhd configs are included as
  static files only, not managed as packages)
- Fish or Bash shell support — zsh only
- Package version pinning or lockfiles
- Remote secrets or credential management

---

### Functional Requirements

#### FR-1: Profile System

The system must support two cumulative profiles:

| Profile   | Tier | User-facing tools |
|-----------|------|-------------------|
| `minimal` | `m`  | tmux |
| `server`  | `s`  | minimal + bat, fzf, eza, fd, jq, ripgrep, tealdeer, zoxide, vfox |

> **Note**: `sheldon` (zsh plugin manager) is a **core infrastructure dependency**, not a
> user-facing tool. It is installed as part of the bootstrap process and loaded before any
> profile package. It does not appear in the tier table because it is always required.

- Each profile includes all tools from lower tiers (cumulative, not exclusive)
- The active profile is set via `DOTFILES_PROFILE` environment variable
- Profile switches must persist across shell restarts — the CLI must update `DOTFILES_PROFILE`
  in `~/.zshenv` so the new profile is active on the next shell open
- Switching profiles must not require re-installation — only `source ~/.zshrc`

#### FR-2: Package System

Each tool must be defined as a self-contained package file under `zsh/packages/<tier>/`.

A package file must be able to:
- Declare a custom installer (`pkg_install`) when the tool is not in standard repos
- Declare post-install setup steps (`pkg_post_install`)
- Declare runtime initialization (`pkg_init`) that runs on every shell start
- Define a custom existence check for tools that are not standard binaries

**Installation behavior:**
- Installation only runs when `DOTFILES_INSTALL=true` (set by `dotfiles install`); `DOTFILES_VERBOSE` controls logging only and does not gate installation
- On normal shell startup, if a managed package is **not installed**, the system must print
  a one-line warning so the user knows what to run:
  ```
  [dotfiles] bat not installed — run: dotfiles install
  ```
- The warning must not block startup or print a stack trace

#### FR-3: Fast Shell Startup

Shell startup must remain under 200 ms on a typical machine.

- Packages with non-trivial `pkg_init` logic must guard against duplicate
  initialization (idempotency flag) so re-sourcing `~/.zshrc` is a no-op.
- Tools with slow startup may be lazy-loaded by intercepting first invocation
  via a shell wrapper that defers real initialization until needed.
- Tools that ship as fast-starting compiled binaries do not need lazy loading.

#### FR-4: Symlink Management

The `bin/dotfiles` CLI must manage symlinks from the dotfiles repo into `$HOME`:

- Root-level config files → `$HOME/.<filename>` (e.g. `zshrc` → `~/.zshrc`)
- `config/` subtree → `$HOME/.config/<tool>/` (e.g. `config/bat/` → `~/.config/bat/`)
- If a target already exists (symlink or plain file): remove it and replace with the repo symlink
- The `verify` command must report all broken, missing, or conflicting links

#### FR-5: Cross-Platform Package Installation

The package installer must auto-detect the OS and use the correct package manager:

| Platform | Package Manager | Detection |
|----------|-----------------|-----------|
| macOS | Homebrew (`brew`) | `uname -s == Darwin` |
| Ubuntu / Debian | `apt` | `ID=ubuntu\|debian` or `ID_LIKE` contains `debian` |
| Fedora / RHEL / Rocky / Alma | `dnf`, then `yum` | `ID=fedora\|centos\|rhel\|rocky\|alma` or `ID_LIKE` contains `rhel\|fedora` |
| Arch / Manjaro | `pacman` | `ID=arch\|manjaro\|endeavouros` or `ID_LIKE` contains `arch` |
| openSUSE | `zypper` | `ID=opensuse\|suse` or `ID_LIKE` contains `suse` |
| FreeBSD | `pkg` | `uname -s == FreeBSD` |
| **Other / unknown** | Custom fallback | see below |

Detection must check **both** `ID` and `ID_LIKE` from `/etc/os-release`. `ID_LIKE` is a
space-separated list of parent distros and must be matched as a substring.
This covers derivatives like Raspberry Pi OS (`ID=raspbian`, `ID_LIKE=debian`),
Linux Mint (`ID=linuxmint`, `ID_LIKE=ubuntu`), and Pop!_OS (`ID=pop`, `ID_LIKE=ubuntu`).

**Unknown distro handling** — when no package manager is matched:
1. Attempt `pkg_install_fallback()` if the package file defines it
2. If no fallback is defined, print a clear actionable error:
   ```
   [dotfiles] Cannot auto-install <tool> on <distro>. Install manually, then re-run.
   ```
3. Never silently skip — the user must know installation did not complete

Package files can define a fallback for unknown distros:

```zsh
pkg_install_fallback() {
    # Prefer verifying checksums over blind curl | sh
    local version="10.1.0"
    local archive="fd-v${version}-$(uname -m)-unknown-linux-musl.tar.gz"
    local url="https://github.com/sharkdp/fd/releases/download/v${version}/${archive}"
    curl -fsSL "$url" | tar -xz --strip-components=1 -C /usr/local/bin fd-*/fd
}
```

#### FR-6: CLI (`bin/dotfiles`)

The `bin/dotfiles` command must support these subcommands:

| Command | Description |
|---------|-------------|
| `dotfiles install` | Install packages for the current profile |
| `dotfiles update` | Pull latest from git (`--ff-only`), re-run install |
| `dotfiles uninstall` | Remove all managed symlinks and reset `~/.zshenv` entries |
| `dotfiles profile <name>` | Switch active profile and persist to `~/.zshenv` |
| `dotfiles verify` | Report broken/missing symlinks and uninstalled packages |

**`dotfiles update` behavior on local changes:**
- Uses `git pull --ff-only` — fast-forward only, no merge commits
- If local changes exist (`git status` is dirty): print a warning and abort
  ```
  [dotfiles] Local changes detected. Commit or stash them before updating.
  ```
- Never auto-stashes or auto-resets — user owns their local changes

---

### Non-Functional Requirements

#### NFR-1: Startup Performance

- Shell startup must complete in **< 200ms** on a 2020+ laptop with SSD
  (reference: M1 MacBook Pro or equivalent Intel/AMD machine with 8GB+ RAM)
- Measured with: `time zsh -i -c exit` (3-run average, discard first)
- Heavy tools must not block startup (use lazy loading where needed)
- `compinit` must run only once per day (cached via `~/.zcompdump`)

#### NFR-2: Portability

- All zsh code must be compatible with **zsh 5.8+**
- No reliance on GNU-specific flags — use POSIX-compatible alternatives where possible
- macOS and Linux behavior must be functionally equivalent for all `m` and `s` tier packages

#### NFR-3: Idempotency

- Running `dotfiles install` multiple times must produce the same result
- Re-sourcing `~/.zshrc` must not produce errors or duplicate environment state
- Package init functions must be safe to call more than once:
  - `export PATH=...` prepends are acceptable only if guarded against duplicates
  - `eval` initialization must not re-run if the tool is already loaded
  - If a tool is already initialized (real binary in PATH), `pkg_init` must not re-wrap it
- Packages with non-trivial `pkg_init` logic require an idempotency guard:
  check a `_DOTFILES_<TOOL>_LOADED` flag at the top of `pkg_init` and return
  early if set, then export it after initialization completes. This makes
  re-sourcing `~/.zshrc` a no-op.

#### NFR-4: Failure Isolation

- A failing package must not prevent other packages from loading
- Errors during `pkg_init` must be caught and logged; the next package must still load
- During install mode (`DOTFILES_VERBOSE=true`), full error context must be shown
- During normal startup, only the one-line warning (FR-2) is shown — no stack traces

#### NFR-5: Extensibility

- Adding a new package requires creating **exactly one file** in `zsh/packages/<tier>/`
- No core file (`zshrc`, `zsh/lib/installer.zsh`, `zsh/core/*.zsh`) needs modification
- Package files may only depend on functions from `zsh/lib/installer.zsh`,
  and `zsh/lib/platform.zsh`

---

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DOTFILES_ROOT` | `~/.dotfiles` | Absolute path to the dotfiles repo |
| `DOTFILES_PROFILE` | `minimal` | Active profile: `minimal` or `server` |
| `DOTFILES_VERBOSE` | `false` | Verbose logging only — does not gate installation |
| `DOTFILES_INSTALL` | `false` | Run the install flow when set to `true` (set internally by `dotfiles install`) |
| `DOTFILES_BRANCH` | `main` | Git branch used by `dotfiles update` |

---

### Constraints

- `zshrc` (entry point) must remain **< 40 lines** — logic lives in `zsh/`
- Package files must be self-contained, depending only on the three `zsh/lib/` files
- No global shell state mutation outside of standard `export` and `alias` calls
- `bin/dotfiles` is **Bash**; all files under `zsh/` are **zsh**
- Lazy loader logic must live **inside the package file's `pkg_init()`**, not in separate files

---

## Appendix B: Adding a Package

A package is a single `.zsh` file in `zsh/packages/<tier>/`. No other file needs to change.

### Step 1 — Choose the right tier

| Tier | Directory | When to use |
|------|-----------|-------------|
| `minimal` | `zsh/packages/minimal/` | Tools needed even on a bare server |
| `server` | `zsh/packages/server/` | Productivity tools for any dev/ops machine |

Profiles are cumulative: `server` includes `minimal`.

### Step 2 — Create the package file

```
zsh/packages/<tier>/<toolname>.zsh
```

Filename rules: lowercase, hyphens allowed, no number prefix needed.

**Exception**: If your package must load before or after another package in the same
tier, prefix with a two-digit number: `00-sheldon.zsh` guarantees first load.

### Step 3 — Fill in the template

```zsh
#!/usr/bin/env zsh

PKG_NAME="toolname"          # Used in log messages and install prompts
PKG_DESC="Short description" # Shown when the tool is not installed
# PKG_CMD="toolname"         # Binary to check (defaults to PKG_NAME)
# PKG_CHECK_FUNC="_toolname_is_installed"  # Use for non-binary tools

# Optional: custom existence check (needed when the tool is not a binary)
# _toolname_is_installed() { [[ -d "$HOME/.toolname" ]]; }

# Optional: runs before the package manager
# pkg_pre_install() { }

# Optional: overrides the OS package manager entirely
# pkg_install() {
#     curl -fsSL https://example.com/install.sh | bash
# }

# Optional: fallback for unknown Linux distros
# pkg_install_fallback() {
#     local url="https://github.com/org/tool/releases/download/v1.0/tool-linux.tar.gz"
#     local tmpfile; tmpfile=$(mktemp)
#     curl -fsSL "$url" -o "$tmpfile"
#     # ALWAYS verify checksum before extracting
#     echo "abc123...  $tmpfile" | sha256sum --check --quiet || { rm -f "$tmpfile"; return 1; }
#     tar -xz -C /usr/local/bin -f "$tmpfile" tool
#     rm -f "$tmpfile"
# }

# Optional: runs after successful first installation
# pkg_post_install() { }

# Optional: runs on every shell start when the tool IS installed
pkg_init() {
    export TOOLNAME_OPTION="value"
    alias t="toolname"
}

init_package_template "$PKG_NAME"
```

### Step 4 — Test it

```zsh
# Verify it loads without errors
zsh -i -c 'type toolname' 2>/dev/null

# Simulate install mode
DOTFILES_VERBOSE=true zsh -c '
  source ~/.dotfiles/zsh/lib/platform.zsh
  source ~/.dotfiles/zsh/lib/installer.zsh
  source ~/.dotfiles/zsh/packages/<tier>/toolname.zsh
'

# Check startup time impact (should stay under 200ms)
for i in 1 2 3; do time zsh -i -c exit; done
```

### Rules

- **All hook functions are optional** — only define what you need
- **`pkg_init` is synchronous** — keep it under 5ms
- **`PKG_CMD=""`** — set this when the tool is not a binary; pair with `PKG_CHECK_FUNC`
- **Never use `curl | sh`** — always download to a temp file and verify a checksum first

### Idempotency example (for tools with `eval` init)

```zsh
pkg_init() {
    # Guard: don't re-initialize if already loaded (e.g. source ~/.zshrc)
    [[ "${_DOTFILES_TOOL_LOADED:-}" == "1" ]] && return 0

    eval "$(tool activate zsh)"

    export _DOTFILES_TOOL_LOADED="1"
}
```

---

## Appendix C: Troubleshooting

### Startup is slow (> 200ms)

Measure with:
```zsh
for i in 1 2 3; do time zsh -i -c exit; done
```

Common causes:

| Symptom | Fix |
|---------|-----|
| Heavy tool runs at startup | Move initialization into `pkg_init` and guard with `_DOTFILES_<TOOL>_LOADED` |
| `compinit` rebuilds every time | The `~/.zcompdump` guard in `00-sheldon.zsh` rebuilds at most once per day; if it still rebuilds, check that `~/.zcompdump` is writable |
| Slow git status in prompt | `POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY=4096` limits dirty-check to repos < 4096 files; increase if needed |

### Tab completion not working

```zsh
# Force a full compinit rebuild
rm -f ~/.zcompdump && exec zsh
```

If that doesn't help, verify `zsh-completions` is loading before `compinit`:
```zsh
# Should show fpath includes zsh-completions
echo $fpath | tr ' ' '\n' | grep completions
```

The `compinit` call is in `zsh/packages/minimal/00-sheldon.zsh` and runs **after**
`eval "$(sheldon source)"`. If completion is broken after adding a new shell plugin,
check that the plugin adds to `fpath` before `compinit` runs.

### A command is not found after shell starts

Check if the package is installed:
```zsh
dotfiles verify
```

Check what type the command is (wrapper vs real binary):
```zsh
type vfox    # → "vfox is /path/to/vfox" means binary is installed
vfox --version
```

If the package shows as installed but `pkg_init` failed silently:
```zsh
# See all init output
DOTFILES_VERBOSE=true zsh -i -c exit 2>&1 | head -50
```

### A version-managed tool (node, python, …) is missing

The version manager activates inside `pkg_init`, but the tools it provides
must be installed separately. If `node`, `python`, or another managed tool is
missing on your `$PATH`:

1. Confirm the version manager itself is installed and active.
2. Install the tool defaults defined in the version manager's config file.
3. List available tools and pin one if no default is configured.

Refer to your version manager's documentation for the exact subcommands.

### Symlinks are broken

```zsh
dotfiles verify
# or check manually:
ls -la ~/.zshrc ~/.tmux.conf ~/.p10k.zsh
```

To recreate all symlinks:
```zsh
dotfiles link
```

### Profile not switching

```zsh
dotfiles profile server
source ~/.zshrc
echo $DOTFILES_PROFILE  # should be "server"
```

If the profile reverts after restarting zsh, check that `~/.zshenv` has the right value:
```zsh
grep DOTFILES_PROFILE ~/.zshenv
```

### `dotfiles install` fails on Linux

Check the detected package manager:
```zsh
zsh -c 'source ~/.dotfiles/zsh/lib/platform.zsh && dotfiles_pkg_manager'
```

For unknown distros, add a `pkg_install_fallback()` hook in the failing package file.
See [Appendix B: Adding a Package](#appendix-b-adding-a-package) for the fallback pattern.

### `.zwc` compiled files are stale

The background compiler (`zsh/core/60-zcompile.zsh`) runs at most once per 24h.
To force an immediate rebuild:
```zsh
rm -f ~/.cache/zsh/compile.stamp
exec zsh
```

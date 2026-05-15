# dotfiles

A cross-platform, profile-based zsh configuration system for macOS and common Linux
distributions. Shell startup stays under 200ms by deferring heavy work via sheldon and
using idempotency guards to skip already-active initialization.

---

## Install

### macOS / Linux

One-liner — clones the repo, symlinks configs, and installs missing packages:

```bash
curl -fsSL https://tinyurl.com/get-dotfiles | bash
```

Or clone and run directly:

```bash
git clone https://github.com/ved0el/dotfiles.git ~/.dotfiles
~/.dotfiles/bin/dotfiles install
```

When the one-liner finishes it prints a NEXT STEPS block — open a new terminal
or run `exec zsh` from your current one.

### Windows

Windows uses a separate, minimal entry point: a `Makefile` that handles
**symlinks only**. Package installation is up to you (use `scoop`, `winget`,
or installers of your choice).

Prereqs (one-time):
- **Git for Windows** — provides `git`, `bash`, and `make`. Install via
  `scoop install git` or the official installer.
- **Developer Mode on** — Settings → Privacy & security → For developers.
  Lets non-admin shells create native symlinks; without it, `make link` fails
  with a clear hint.

Then:

```powershell
git clone https://github.com/ved0el/dotfiles.git $HOME\.dotfiles
cd $HOME\.dotfiles
make link        # create / refresh symlinks
make verify      # report OK / MISSING / STALE / CONFLICT
make unlink      # remove only the symlinks we created
```

Install the tools you actually want yourself, e.g.:

```powershell
scoop install bat fd ripgrep fzf zoxide eza jq sheldon vfox
```

The Makefile auto-discovers entries in `config/*` and skips macOS-only
daemons (`skhd`, `yabai`). `config/claude/*` is symlinked file-by-file into
`~/.claude/` to match the bash CLI's behavior.

---

## Profiles

Profiles are cumulative: `full` includes everything in `core`.

| Profile | Tools |
|---------|-------|
| `core`  | sheldon (plugin manager), tmux |
| `full`  | everything in core + bat, eza, fd, fzf, jq, ripgrep, vfox, zoxide |

The active profile is stored in `~/.zshenv` and read by every zsh instance.

Valid profile names are derived from the filesystem — any directory under
`zsh/packages/<name>/` is a valid profile. Add a new one with
`mkdir zsh/packages/dev && touch zsh/packages/dev/foo.zsh`; no code changes
needed.

Switch profiles:

```bash
dotfiles config set profile full
exec zsh
```

Legacy names `minimal` (→ `core`) and `server` (→ `full`) are accepted and
auto-migrated on next save.

---

## CLI reference

Run `dotfiles` with no arguments in an interactive terminal to open the menu —
8 numbered options (install, sync, status, config, doctor, clean, uninstall,
quit). Picking `config` opens a sub-screen with toggle actions for `verbose`,
profile switches, and `$EDITOR ~/.zshenv`. Each option shows the resulting
value before you press (`verbose true → false`).

| Command | Short | Description |
|---------|-------|-------------|
| `install` | `i` | Symlink configs + install packages. Does not pull from git. On a fresh machine, clones the repo first. |
| `update [--stash]` | `u` | `git pull --rebase`. Aborts on dirty tree unless `--stash` is passed. |
| `sync [--stash]` | `s` | `update` then `install` in one step. |
| `status` | `st` | Snapshot: profile, git state, symlink count, package count. Supports `--json`. |
| `config <action>` | — | `get <key>` / `set <key> <val>` / `list` / `edit` / `path` / `keys`. Run `dotfiles config help` for details. |
| `doctor` | `d` | Read-only health check (badge grid + per-package detail). Exit code = number of issues. |
| `clean [--force]` | `c` | Report orphaned symlinks (dry-run). Pass `--force` to remove. |
| `link` | — | Create or refresh symlinks only. |
| `packages` | — | Install packages for the active profile only. |
| `profile <name>` | — | Shorthand for `config set profile <name>`. |
| `uninstall` | — | Remove all symlinks, packages, and the repo directory. Interactive prompt unless stdin is non-TTY. |
| `version` | — | Print version info. |
| `help` | `-h` | Print usage. |

Global flags (may appear before *or* after the subcommand):

| Flag | Description |
|------|-------------|
| `-v`, `--verbose` | Enable verbose output (timestamped, scope-tagged debug lines). |
| `-q`, `--quiet` | Suppress non-error output. Errors and warnings still print. |
| `--json` | Machine-readable JSON output for `status` and `config list`. |
| `--no-reload` | Skip `exec zsh` at the end of `install` / `update` / `sync`. |
| `--no-banner` | Skip the dotfiles banner (handy for scripts/CI). |
| `-h`, `--help` | Show usage. |

---

## Environment variables

These live in `~/.zshenv` and are written by `dotfiles install` / `dotfiles profile`.
An env-passed value always wins over the saved default — the file uses
`${VAR:-saved_value}` syntax so shell-level overrides work without editing the file.

| Variable | Default | Purpose |
|----------|---------|---------|
| `DOTFILES_ROOT` | `~/.dotfiles` | Path to this repo. |
| `DOTFILES_PROFILE` | `core` | Active profile (`core` or `full`). |
| `DOTFILES_VERBOSE` | `false` | Verbose shell startup + CLI details when `true`. |

Override for a single run without saving:

```bash
DOTFILES_VERBOSE=true dotfiles doctor
DOTFILES_PROFILE=full dotfiles install
```

---

## Adding a tool

Create one file: `zsh/packages/<tier>/<toolname>.zsh`. The file declares hook
functions and calls `init_package_template "$PKG_NAME"` at the end. No other file
needs to change.

```zsh
PKG_NAME="mytool"
PKG_DESC="What it does"

pkg_init() {
    alias mt="mytool --flag"
}

init_package_template "$PKG_NAME"
```

See [ARCHITECT.md](ARCHITECT.md) for the full 8-hook contract and a complete annotated
example.

---

## Troubleshooting

Run `dotfiles doctor` first. It checks required tools, repo state, symlink integrity,
mise leftovers, and per-package health.

| Symptom | Fix |
|---------|-----|
| Required tool missing (`git`, `curl`, `zsh` not in PATH) | Install via system package manager, then `dotfiles install`. |
| Orphaned symlinks | `dotfiles clean` (dry-run shows what), then `dotfiles clean --force`. |
| `mise` leftovers (`~/.local/share/mise`, `~/.config/mise`) | `dotfiles clean --force` — vfox's `pkg_clean` hook removes them. |

---

See [CLAUDE.md](CLAUDE.md) for contributor and AI-agent guidance.
See [ARCHITECT.md](ARCHITECT.md) for architecture and package contract details.

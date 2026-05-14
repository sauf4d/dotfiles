# dotfiles

A cross-platform, profile-based zsh configuration system for macOS and common Linux
distributions. Shell startup stays under 200ms by deferring heavy work via sheldon and
using idempotency guards to skip already-active initialization.

---

## Install

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/ved0el/dotfiles/main/bin/dotfiles \
  -o /tmp/dotfiles-install.sh
bash /tmp/dotfiles-install.sh
```

Or clone and run directly:

```bash
git clone https://github.com/ved0el/dotfiles.git ~/.dotfiles
~/.dotfiles/bin/dotfiles install
```

After install, reload: `exec zsh`

---

## Profiles

Profiles are cumulative: `full` includes everything in `core`.

| Profile | Tools |
|---------|-------|
| `core`  | sheldon (plugin manager), tmux |
| `full`  | everything in core + bat, eza, fd, fzf, jq, ripgrep, tealdeer, vfox, zoxide |

The active profile is stored in `~/.zshenv` and read by every zsh instance.

Switch profiles:

```bash
dotfiles profile full
exec zsh
```

Legacy names `minimal` (→ `core`) and `server` (→ `full`) are accepted and
auto-migrated on next `dotfiles install`.

---

## CLI reference

Run `dotfiles` with no arguments in an interactive terminal to open the menu.

| Command | Short | Description |
|---------|-------|-------------|
| `install` | `-i` | Symlink configs + install packages. Does not pull from git. On a fresh machine, clones the repo first. |
| `update [--stash]` | `-u` | `git pull --rebase`. Aborts on dirty tree unless `--stash` is passed. |
| `sync [--stash]` | `-s` | `update` then `install` in one step. |
| `link` | — | Create or refresh symlinks only. |
| `packages` | — | Install packages for the active profile only. |
| `profile <name>` | — | Change active profile (`core` or `full`). Writes to `~/.zshenv`. |
| `clean [--force]` | `-c` | Report orphaned symlinks pointing into the repo (dry-run). Pass `--force` to remove. |
| `doctor` | `-d` | Read-only health check. Exit code = number of issues found. |
| `uninstall` | — | Remove all symlinks, packages, and the repo directory. Interactive prompt unless stdin is non-TTY. |
| `version` | — | Print version info. |
| `help` | `-h` | Print usage. |

Global options (may be placed before any command):

| Flag | Description |
|------|-------------|
| `-v`, `--verbose` | Enable verbose output for this invocation only. |
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

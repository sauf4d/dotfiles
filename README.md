# Dotfiles – Fast, profile-based setup

Clean, cross-platform dotfiles with profile-based installs and a simple, extensible package system.

## Install

```bash
# Interactive (recommended)
bash <(curl -fsSL https://tinyurl.com/get-dotfiles)

# Non-interactive
curl -fsSL https://tinyurl.com/get-dotfiles | DOTFILES_PROFILE=server bash
```

## Profiles

Profiles are cumulative — each includes everything below it.

| Profile | Tools |
|---------|-------|
| `minimal` | sheldon, tmux |
| `server` | minimal + bat, eza, fd, fzf, jq, ripgrep, tealdeer, zoxide, vfox |

Switch profile anytime:

```bash
dotfiles profile server
```

## Project structure

```
~/.dotfiles/
├── zsh/
│   ├── core/           # Always-loaded modules (options, history, completion, aliases, theme, zcompile)
│   ├── lib/            # Shared libraries (platform, installer)
│   └── packages/
│       ├── minimal/    # sheldon, tmux
│       └── server/     # bat, eza, fd, fzf, jq, ripgrep, tealdeer, zoxide, vfox
├── bin/
│   └── dotfiles        # CLI (bash)
├── config/             # App configs (sheldon, bat, tealdeer, ripgrep, yabai, skhd)
├── docs/               # Architecture, requirements, guides
├── zshrc               # Shell entry point (~40 lines)
├── zshenv              # Env var template (not symlinked — CLI manages ~/.zshenv)
└── tmux.conf
```

## Package system

Each tool is a single self-contained `.zsh` file in `zsh/packages/<tier>/`. No other file changes when adding a package.

```zsh
#!/usr/bin/env zsh

PKG_NAME="mytool"
PKG_DESC="Short description"

pkg_install() {
    brew install mytool   # Optional: override OS package manager
}

pkg_init() {
    export MYTOOL_OPTS="--fast"
    alias mt="mytool"
}

init_package_template "$PKG_NAME"
```

See [`docs/architecture.md#appendix-b-adding-a-package`](docs/architecture.md#appendix-b-adding-a-package) for the full lifecycle reference.

## CLI commands

```bash
dotfiles                  # interactive menu
dotfiles install          # install all packages for current profile
dotfiles link             # create/recreate symlinks
dotfiles verify           # check symlinks + report missing packages
dotfiles profile server   # switch profile (persists across sessions)
dotfiles update           # pull latest changes
dotfiles uninstall        # remove symlinks and config
```

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DOTFILES_ROOT` | `~/.dotfiles` | Repository location |
| `DOTFILES_PROFILE` | `minimal` | Active profile |
| `DOTFILES_VERBOSE` | `false` | Enable verbose output |

## Troubleshooting

See [`docs/architecture.md#appendix-c-troubleshooting`](docs/architecture.md#appendix-c-troubleshooting) for common issues.

Quick checks:

```bash
# Shell startup time
for i in 1 2 3; do time zsh -i -c exit; done

# Check what's missing
dotfiles verify

# Force completion rebuild
rm -f ~/.zcompdump && exec zsh
```

## Windows

Windows uses a small `Makefile` to sync `config/<tool>/` into `~/.config/<tool>/`
(and `config/claude/<file>` into `~/.claude/<file>`). `bin/dotfiles` is for
macOS/Linux only — the `Makefile` hard-fails on those platforms.

Runs from **PowerShell, cmd, or Git Bash** — recipes are forced through Git
Bash regardless of host shell, so all three behave identically.

One-time setup:

1. Enable **Developer Mode** (Settings → Privacy & security → For developers).
   Lets `ln -s` create real Windows symlinks without admin.
2. Install Git for Windows and GNU Make via Scoop:
   ```powershell
   scoop install make git
   ```
   (Git for Windows ships the bash recipes need; the Makefile auto-discovers
   it via `git --exec-path`.)

Daily use:

```bash
make            # list targets
make link       # create / refresh all config symlinks (idempotent)
make verify     # report OK / MISSING / STALE / CONFLICT for every expected link
make unlink     # remove every symlink we created (only touches symlinks)
```

`link` first probes whether real symlinks can be created in this shell and
bails with `cannot link` if they can't (e.g. Developer Mode is disabled).
It also refuses to clobber a real file at the target — prints `SKIP` so you
can rename or delete it manually first.

## Documentation

- [Architecture](docs/architecture.md) — system design, lifecycle, internals
- [Appendix A: Requirements](docs/architecture.md#appendix-a-system-requirements) — functional and non-functional spec
- [Appendix B: Adding a package](docs/architecture.md#appendix-b-adding-a-package) — extension guide
- [Appendix C: Troubleshooting](docs/architecture.md#appendix-c-troubleshooting) — common issues

## Contributing

Pull requests welcome. Please:

1. Open an issue first for non-trivial changes.
2. Add or update tests where applicable.
3. Run `dotfiles verify` and confirm `time zsh -i -c exit` stays under 200 ms.

## License

Released under the MIT License.

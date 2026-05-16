# dotfiles

One shell config that travels across macOS, Linux, and Windows. Each
machine installs only the tools it actually needs. One command sets up
a fresh box; one command keeps existing boxes in sync.

- **Tools managed by mise** — same versions on every machine via
  per-tier shards under `config/mise/conf.d/`.
- **Configs synced via symlinks** — edit a file in the repo, every
  machine that pulls the commit picks it up immediately.
- **Per-machine overrides** — pick a profile, exclude tools you don't
  want, add tools you do — without forking the repo.
- **Shell startup < 200ms** — heavy work deferred via sheldon's `zsh-defer`
  + mise's lazy PATH activation.

---

## Install

### macOS / Linux

```bash
curl -fsSL https://tinyurl.com/get-dotfiles | bash
```

That's it. Bootstraps git/zsh/curl if missing → clones the repo → runs
the install (using sensible defaults silently) → switches your default
shell to zsh.

**Want to be asked instead** — pass `--menu` (UC-18, opt-in picker):

```bash
curl -fsSL https://tinyurl.com/get-dotfiles | bash -s -- --menu
```

**Skip defaults and pick exactly** with flags:

```bash
# Full dev workstation, default tools
curl -fsSL https://tinyurl.com/get-dotfiles | bash -s -- --profile=develop

# Thin server, no language SDKs
curl -fsSL https://tinyurl.com/get-dotfiles | bash -s -- --profile=server

# Custom: develop profile minus a tool, plus extras
curl -fsSL https://tinyurl.com/get-dotfiles | bash -s -- \
  --profile=develop --exclude=jq --extra=htop,starship
```

Or clone manually and run:

```bash
git clone https://github.com/ved0el/dotfiles.git ~/.dotfiles
~/.dotfiles/bin/dotfiles install --profile=develop
```

### Windows

```powershell
iwr -useb https://tinyurl.com/get-dotfiles-win | iex
```

Bootstraps scoop → installs git/mise → clones the repo → runs
`bin\dotfiles.ps1 install` (which creates native pwsh symlinks and
`mise install` for tools) → injects a marker-delimited block into
`$PROFILE` so new pwsh shells auto-load the dotfiles.

Same tools, same versions as the Mac/Linux machines; uses PowerShell as
the daily shell.

Requires:
- **PowerShell 7+** — install via `winget install Microsoft.PowerShell`
  if you're on Windows PowerShell 5.1.
- **Developer Mode on** — Settings → Privacy & security → For developers
  → Developer Mode. Lets non-admin shells create native symlinks; the
  bootstrap probes and warns if disabled.
- **fzf keybindings** (optional) — `Install-Module PSFzf -Scope CurrentUser -Force`.
  Standalone `fzf` works without it; only the Ctrl-T / Ctrl-R hooks need PSFzf.

Or clone manually:

```powershell
git clone https://github.com/ved0el/dotfiles.git $HOME\.dotfiles
$HOME\.dotfiles\bin\dotfiles.ps1 install
```

---

## Profiles

Profiles are a **strict superset chain** — each tier includes everything from
the tier below. Pick the most thorough one your machine needs.

| Profile | Shell-init packages | Mise tools (synced shards) | Best for |
|---|---|---|---|
| `core` | sheldon, mise | none — opt-in via `99-machine.toml` | Minimal bootstrap |
| `server` | core + (server-tier zsh init) | core + `00-server.toml` (bat, fd, fzf, jq, ripgrep, zoxide) | Thin VPS / SSH host |
| `develop` | core + server + `mise-tools.zsh` (CLI tool aliases) | core + `00-server.toml` + `10-develop.toml` (node, go, python, bun, pnpm, yarn, biome) | Full dev workstation |

Per-machine extras (tmux, eza, anything outside the synced shards) go
into `~/.config/mise/conf.d/99-machine.toml` — write it via
`dotfiles config set extra <tool>`, not by hand.

See what's active:

```bash
dotfiles profile list      # table with → pointing at the active profile
```

Switch:

```bash
dotfiles config set profile develop   # or server, or core
dotfiles install                       # apply
```

Legacy names (`minimal`, `full`, `dev`) auto-migrate to (`core`,
`develop`, `develop`) on next install.

### Per-machine tool overrides

Don't want everything in your profile? Don't want to fork the repo?
Use overrides — they live in `~/.zshenv` (per-machine, not synced):

```bash
dotfiles config set exclude eza,bat        # drop these from the install
dotfiles config set extra htop,starship    # add these on top
dotfiles install
```

The repo stays unchanged; your machine just installs the difference.

---

## CLI reference

Run `dotfiles` with no arguments in an interactive terminal to open the
menu. Or use subcommands directly:

| Command | Short | Description |
|---|---|---|
| `install [--profile=…] [--exclude=…] [--extra=…]` | `i` | Install/refresh everything: symlinks, mise tools, shell integration. Idempotent — safe to re-run. |
| `sync [--stash]` | `s` | `git pull --ff-only` + `install`. The everyday "give me what's new" command. |
| `update [--stash]` | `u` | Just `git pull --rebase`, no install. |
| `status` | `st` | Snapshot: profile, overrides, git state, symlink count, tool count. Supports `--json`. |
| `config get/set/list/edit/path/keys` | — | Manage values in `~/.zshenv` managed block. `dotfiles config help` for details. |
| `doctor` | `d` | Read-only health check. Reports tool sources (mise vs system) and exit code = number of issues. |
| `clean [--force]` | `c` | Find orphaned symlinks (dry-run by default; `--force` to apply). |
| `claude-clean [--force]` | — | Strip session-volatile keys from `config/claude/settings.json` so `git status` stays clean. |
| `link` | — | Create/refresh symlinks only (no package work). |
| `packages` | — | Install packages for the current profile only. |
| `uninstall [--purge]` | — | Remove symlinks, mise tools, managed `~/.zshenv` block, repo dir. `--purge` also removes user data (zoxide db, etc.). |
| `version` | — | Print version + source URL. |
| `help` | `-h` | Show this help. |

Global flags (may appear before or after the subcommand):

| Flag | Description |
|---|---|
| `-v`, `--verbose` | Verbose output (timestamped, scope-tagged debug). |
| `-q`, `--quiet` | Suppress non-error output. |
| `--json` | Machine-readable JSON output for `status` and `config list`. |
| `--no-reload` | Skip `exec zsh` at the end of `install`/`update`/`sync`. |
| `--no-banner` | Skip the dotfiles banner (handy for scripts/CI). |

---

## Sync across machines

Three steps after editing the repo on machine A:

```bash
# Machine A — push your change
cd ~/.dotfiles
git add config/mise/conf.d/10-develop.toml zsh/packages/develop/starship.zsh
git commit -m "feat: add starship"
git push

# Machine B — pull and apply
dotfiles sync   # = git pull --ff-only && dotfiles install
```

Pure config-file edits (e.g. tweaking `config/bat/config`) take effect
immediately after `git pull` — no install needed, because the file IS
the symlink target.

If you forget to sync, new shells will nudge you when the last fetch is
more than 7 days old: `[dotfiles] last synced 14 days ago — run \`dotfiles sync\``.

---

## Add a new tool

Three cases:

**Case A — just a binary you'll call directly** (htop, dust, dog):

1. Edit the right shard — `config/mise/conf.d/00-server.toml` if every
   server+develop machine should get it, or `10-develop.toml` for
   develop-only tools. Add `htop = "latest"`.
2. `dotfiles install`.
3. Commit + push.

**Case B — binary + shell integration** (starship, atuin, direnv):

1. Add the entry to `config/mise/conf.d/10-develop.toml` (or the
   appropriate tier).
2. Create `zsh/packages/develop/starship.zsh`:
   ```zsh
   command -v starship &>/dev/null && eval "$(starship init zsh)"
   ```
3. (Windows parity) Create `pwsh/packages/develop/Starship.ps1`:
   ```powershell
   if (Get-Command starship -EA SilentlyContinue) {
       Invoke-Expression (&starship init powershell | Out-String)
   }
   ```
4. `dotfiles install`. Commit + push.

**Case C — tool needs custom install/uninstall logic mise can't express**
(rare): write a full lifecycle package. See
[docs/ARCHITECT.md](docs/ARCHITECT.md) "Package contract" + [CLAUDE.md](CLAUDE.md)
for the 8-hook contract.

---

## Per-machine config tweaks

Want a different bat theme on your laptop vs server? Prefer env vars:

```bash
dotfiles config set env BAT_THEME OneHalfLight
```

This writes `export BAT_THEME=OneHalfLight` into the dotfiles-managed
block of `~/.zshenv`. The repo's `config/bat/config` stays untouched and
keeps syncing across machines; this one machine's bat now uses the
override. Same pattern works for any tool that respects env vars.

For tools without env-var overrides, drop a sibling file like
`~/.config/<tool>/local.conf` and source it from the main config.

---

## Troubleshooting

Run `dotfiles doctor` first. It checks required tools, repo state,
symlinks, mise installs, and per-tool source (mise vs system).

| Symptom | Fix |
|---|---|
| Required tool missing (`git`, `curl`, `zsh`) | Install via system package manager, then `dotfiles install`. |
| Orphaned symlinks | `dotfiles clean` (dry-run), then `dotfiles clean --force`. |
| `mise` leftover after uninstalling vfox | `dotfiles clean --force` — mise's `pkg_clean` removes them. |
| "wrong fzf wins on PATH" | `dotfiles doctor` shows tool source; if apt/brew copies are interfering, uninstall them (`sudo apt remove fzf`) and re-run `dotfiles install`. |
| Half-finished install (network died, Ctrl+C) | Just re-run `dotfiles install`. Idempotent by design. |
| Need a clean reset | `dotfiles clean --force && dotfiles install`. |
| Pristine wipe | `dotfiles uninstall` (interactive prompt). Pass `--purge` to also remove user data (zoxide db, etc.). |

---

## Contributing — pre-commit hook

The repo ships a guard at `.githooks/pre-commit` that blocks accidentally
committing `config/claude/settings.json` (it churns on every `/model`,
`/effort`, permission approval, etc.). Enable once per clone:

```bash
git -C ~/.dotfiles config core.hooksPath .githooks
```

Bypass for an intentional commit:

```bash
DOTFILES_ALLOW_SETTINGS_DRIFT=1 git commit -m "real settings change"
# or
git commit --no-verify -m "…"
```

If you intentionally want to commit settings, run `dotfiles claude-clean
--force` first to strip session-volatile keys, leaving only meaningful
config (plugins, marketplaces, permissions, statusline).

---

## Docs

- [docs/USECASES.md](docs/USECASES.md) — the 18 use cases the system
  must support. The contract.
- [docs/ARCHITECT.md](docs/ARCHITECT.md) — architecture, decision
  rationale, implementation status.
- [CLAUDE.md](CLAUDE.md) — developer / AI-agent conventions.

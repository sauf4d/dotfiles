# USECASES.md — what the dotfiles system must do

This is the **contract**. Every architecture and code decision must serve at
least one use case here. If a feature doesn't map to a use case, it should
not exist. If a use case isn't supported, the architecture is incomplete.

Use cases are grouped by lifecycle phase. Each lists who does what and what
the system does in response. None of this assumes specific implementation —
that's the architecture's job to figure out.

## The four user goals (north star)

1. **One config, many machines** — macOS, Linux (Ubuntu/Debian/Fedora/Arch),
   Windows. Same dotfiles repo. Differences expressed as configuration, not
   forks.
2. **Each machine installs only what it needs** — a thin VPS doesn't drag in
   node/go/python. A workstation gets the lot. A specific machine can
   opt out of individual tools.
3. **One-line install on a fresh machine** — paste a single command into a
   clean shell; everything required to use the dotfiles is set up.
4. **Sync is cheap and obvious** — change something on machine A, machine B
   picks it up with one explicit command. No surprise auto-updates.

---

## Phase 1 — first install (bare machine → working dotfiles)

### UC-1: Fresh dev workstation (macOS or Linux)

**Who/when**: New laptop arrives, or `rm -rf ~/.dotfiles` recovery.
**They want**: Everything they normally use, default versions.
**They do**:
```bash
curl -fsSL https://tinyurl.com/get-dotfiles | bash
```
**They get**: Repo cloned to `~/.dotfiles`, configs symlinked, all default
tools installed (zsh, tmux, mise, plus mise-managed CLI tools and SDKs).
Default shell switched to zsh. A NEXT STEPS block prints; next shell is
ready.

### UC-2: Fresh thin server (Debian/Ubuntu VPS)

**Who/when**: New VPS for a single service, dev tools would be bloat.
**They want**: Shell + tmux + a few CLI utilities. No language SDKs.
**They do**:
```bash
curl -fsSL https://tinyurl.com/get-dotfiles | bash -s -- --profile=server
```
**They get**: Same repo + symlinks as UC-1, but the SDK group (node/go/
python/bun) is skipped. Install completes in roughly half the time and
uses a fraction of the disk.

### UC-3: Fresh Windows machine

**Who/when**: Adding a Windows box to the fleet.
**They want**: Same tools, same configs, same versions as the Mac/Linux
machines — but in PowerShell, since Windows can't run zsh natively.
**They do**: open PowerShell and run:
```powershell
iwr -useb https://tinyurl.com/get-dotfiles-win | iex
```
**They get** (in order):
1. **scoop** bootstrapped if missing (Windows-side equivalent of brew/apt).
2. **`scoop install git mise`** — git for cloning, mise as the package
   manager. (Optional: `scoop install pwsh` if user is still on Windows
   PowerShell 5.1 and needs PowerShell 7+.)
3. Repo cloned to `$HOME\.dotfiles`.
4. **`mise install`** reads `config/mise/conf.d/*.toml` and pulls all
   tools — the github: backend ships native Windows binaries for every
   tool in the manifest.
5. **`make link`** runs in Git Bash (installed alongside git), symlinks
   `config/*` into `$env:APPDATA`-style locations. Requires Developer
   Mode on, or admin; the make target probes and reports.
6. **`$PROFILE` block injected** — sources `pwsh/packages/<profile>/*.ps1`
   to wire up shell integration (aliases, env vars, evals).
**Net result**: same tools at the same versions, same configs, same key
bindings — only the shell language differs.

> **Windows shell-integration constraint** (one note worth knowing):
> zsh files in `zsh/packages/` don't run on Windows. A parallel
> `pwsh/packages/<profile>/*.ps1` tree provides the PowerShell version of
> the same aliases and inits (eza alias, zoxide init, bat MANPAGER, etc.).
> One tool integration that's awkward: **fzf**'s shell hook on pwsh
> requires the PSFzf module — installed via `Install-Module PSFzf` from
> the same `00-mise.ps1` post-install step. Everything else (bat/eza/fd/
> jq/ripgrep/zoxide) is just alias + env var + `Invoke-Expression
> (<tool> init powershell)` and works identically to zsh.

### UC-4: Pick a custom set at install time

**Who/when**: First install but they don't want the default tool list.
**They want**: Override the default install set, e.g. "give me the dev
profile but drop eza and add htop."
**They do**:
```bash
curl -fsSL https://tinyurl.com/get-dotfiles | bash -s -- --profile=develop --exclude=eza --extra=htop
```
Or after install: `dotfiles config set exclude eza` and rerun
`dotfiles install`.
**They get**: Exactly the listed tools, no more, no less.

### UC-18: Choose options interactively (opt-in menu)

**Who/when**: First install on a fresh machine and they want to be walked
through profile/extras/excludes instead of typing flags. Or later, when
they want to change profile/overrides without remembering exact `config
set` syntax.
**They want**: Be asked, not asked-every-time. The menu is OPT-IN — daily
`dotfiles install` runs are silent and use saved config.
**They do** — flag form on the bootstrap:
```bash
curl -fsSL https://tinyurl.com/get-dotfiles | bash -s -- --menu
```
Or on a checked-out repo:
```bash
dotfiles install --menu
```
**They get**: After repo clone, an interactive picker appears:
```
  DOTFILES SETUP — pick what to install

  Profile   (current: dev)
    1)   core
    2) * dev
    3)   server

  Extra tools   (comma-separated, optional)
  Exclude tools (comma-separated, optional)

    [ENTER] confirm   [d] defaults   [q] cancel
```
Choices persist to `~/.zshenv` so subsequent runs use them without re-asking.
**Behind the scenes**: Menu fires only when `--menu` flag is passed OR
`DOTFILES_MENU=true` is set (persistable via `dotfiles config set menu true`).
Default behavior: silent install using saved config. Skipped automatically
in CI / non-TTY / `--quiet`.

> The menu was previously default-on; that proved noisy for daily use. Now
> it's an explicit opt-in so re-running install doesn't re-prompt every time.
>
> Flag form (`--profile=develop --exclude=eza --extra=htop`) is ALWAYS
> respected when present and skips the menu regardless.

---

## Phase 2 — daily customization (already installed)

### UC-5: Add a tool I want

**Who/when**: Decides they need `htop` after install.
**They want**: One-line add, propagates to other machines via the repo.
**They do**: edit `config/mise/conf.d/*.toml`, add `htop = "latest"`, then
`dotfiles install`.
**They get**: htop installed. Commit + push the change; other machines
pick it up via UC-9.

### UC-6: Add a tool that needs shell integration (alias, eval)

**Who/when**: Wants `starship` prompt — needs `eval $(starship init zsh)`
on Unix and `Invoke-Expression (&starship init powershell | Out-String)`
on Windows.
**They want**: Same one-liner add, hooks set up on every shell.
**They do**:
1. Edit `config/mise/conf.d/*.toml`, add `starship = "latest"`.
2. Add `zsh/packages/<group>/starship.zsh` — just a `command -v starship
   && eval $(starship init zsh)`. No lifecycle hooks needed.
3. Add the pwsh mirror `pwsh/packages/<group>/starship.ps1` — same idea
   but with `Get-Command starship -EA SilentlyContinue` and the pwsh init.
**They get**: New shells (zsh OR pwsh) get the integration. Other
machines pick it up via UC-9. Skip step 3 if you don't run this machine
on Windows.

> The two shell-integration files are a real trade-off: cross-shell
> means cross-file. Most tools only need 1–3 lines per shell, so the
> per-tool cost is low. The alternative — translating zsh integrations
> to pwsh at install time — would be magic and would break for non-trivial
> snippets. Two short files beats one fragile translator.

### UC-7: Skip a default tool on this machine only

**Who/when**: On a specific machine, they don't want `eza` polluting
their `ls` alias.
**They want**: Local override, doesn't affect other machines.
**They do**: `dotfiles config set exclude eza,bat` (or `extra htop,starship`
to add tools). This writes to the dotfiles-managed block in `~/.zshenv`
(the same place `DOTFILES_PROFILE` already lives). Then `dotfiles install`.
**They get**: eza uninstalled here; other machines unaffected — `~/.zshenv`
is per-machine, not in the repo. The marker-delimited managed block
preserves any user content around it.

> On Windows, the same vars live in the dotfiles-managed block of `$PROFILE`
> (and are read by `bin/dotfiles.ps1` / `make link`). Same syntax via
> `dotfiles config set …`.

### UC-8: Pin a tool to a specific version

**Who/when**: Reproducibility need — every machine must run node 22.0.0.
**They want**: Edit one place, all machines align.
**They do**: in `config/mise/conf.d/*.toml`, change `node = "latest"` to
`node = "22.0.0"`. Commit. Run `dotfiles install` on each machine (or
let UC-9 handle it).
**They get**: All machines converge on the pinned version.

### UC-16: Machine-specific config override

**Who/when**: Want a different bat theme on a server (dark) vs laptop
(light), or a smaller fzf height on a low-res VPS console.
**They want**: Base config travels via repo unchanged; one knob differs
on this machine only.
**They do**: prefer the tool's own env-var override and set it via
`dotfiles config set env BAT_THEME OneHalfLight` — this writes to the
managed block in `~/.zshenv` (same mechanism as `DOTFILES_PROFILE`,
machine-local, not in the repo). For tools without an env override,
drop a sibling file `~/.config/<tool>/local.<ext>` and source it from
the main config file (per-tool depending on what the tool supports).
**They get**: Base config in repo unchanged. This machine's override
wins. Other machines are unaffected.

> Rule of thumb: prefer env vars over config-file forks. Env vars are
> additive and don't break sync. File overrides are last resort for
> tools that don't expose an env knob.

---

## Phase 3 — sync across machines

### UC-9: Pull other machine's changes

**Who/when**: Edited the repo on machine A, now sitting at machine B.
**They want**: Apply A's changes to B in one command.
**They do**: `dotfiles sync` (= `git pull --ff-only && dotfiles install`).
**They get**: Repo updated, new tools installed, removed tools left alone
(uninstall is explicit), configs propagated via symlinks. Idempotent —
safe to rerun.

### UC-10: Be reminded to sync

**Who/when**: Hasn't synced in two weeks; teammate added a tool.
**They want**: Not surprised by missing tools, but not forced into
auto-update either.
**They get**: On shell startup, if `git fetch-head` is stale (> 7 days),
a one-line nudge: `[dotfiles] last synced 14 days ago — run \`dotfiles sync\``.
Non-blocking, no network call at shell startup.

### UC-11: Diverged config — see what's different

**Who/when**: They made local changes (`vi ~/.config/bat/config`) and
forgot to commit; meanwhile pulled changes from origin.
**They want**: A clear view of what's local-only vs. what's in the repo.
**They do**: `dotfiles status` (or `dotfiles status --json` for tooling).
**They get**: A table of: managed configs (synced via dotfiles), local
overrides (machine-only), and uncommitted repo changes. No mystery state.

---

## Phase 4 — operate and maintain

### UC-12: Verify everything is healthy

**Who/when**: After install, after sync, when something feels off.
**They want**: One command, clear pass/fail per concern.
**They do**: `dotfiles doctor`.
**They get**: A badge grid + per-tool detail. Reports: required tools
present, repo state clean, symlinks intact, mise tools installed,
profile valid. **Each tool also reports its source** — `mise` vs
`apt`/`brew`/`scoop` vs `user-installed`. First diagnostic when
something acts weird ("why is my fzf v0.30 when the repo says latest?"
→ doctor shows it's the apt copy winning on PATH, not mise's). Exit
code = number of issues.

### UC-13: Remove a tool

**Who/when**: Decided `bun` isn't worth keeping.
**They want**: Clean removal — binary, config, shell integration.
**They do**: remove `bun = "latest"` from `config/mise/conf.d/*.toml`,
commit, run `dotfiles install` (mise removes the orphaned tool) and
`dotfiles clean --force` (sweeps any leftover symlinks).
**They get**: Tool gone. No dead aliases, no stale config dirs.

### UC-14: Switch profile on an existing machine

**Who/when**: VPS that was server-only now needs dev tools temporarily.
**They want**: Promote in place — no reinstall from scratch.
**They do**: `dotfiles config set profile develop && dotfiles install`.
**They get**: The dev group's tools install on top of what was already
there. Reverse (`profile server`) leaves develop tools in place until they
run `dotfiles install --reconcile` (explicit prune).

### UC-15: Full uninstall

**Who/when**: Decommissioning a machine, or starting clean.
**They want**: Everything removed — binaries, symlinks, repo,
modifications to `~/.zshenv`.
**They do**: `dotfiles uninstall`.
**They get**: Interactive prompt confirming scope. All managed symlinks
removed, mise tools uninstalled, repo directory deleted, managed
`~/.zshenv` block stripped. User data (zoxide db, zsh history,
notebooks) preserved unless `--purge` is passed.

### UC-17: Recovery from half-installed state

**Who/when**: `dotfiles install` died mid-run (network drop, Ctrl+C,
a tool version got yanked upstream). Or upgrade left mise in a
partial state.
**They want**: Converge back to declared state without manual
`rm -rf` archaeology.
**They do**: re-run `dotfiles install` (idempotent — picks up where
it left off). If that doesn't clear it, `dotfiles doctor` to
diagnose. For a hard reset: `dotfiles clean --force && dotfiles install`.
**They get**: System converges to whatever the repo + machine-local
overrides declare. No state guesswork.
**Behind the scenes**: Every lifecycle hook is idempotent by contract
(CLAUDE.md pitfall #5). Marker-delimited blocks make `~/.zshenv`
rewrites safe to replay. `mise install --yes` skips already-installed-
and-current tools. The package-template engine treats already-installed
packages as "still good — just re-run init."

> This isn't a recovery feature — it's the consequence of every install
> step being a no-op when the state already matches. Re-running install
> is the recovery mechanism. We commit to this guarantee, not just hope.

---

## Out of scope (explicitly NOT use cases)

- **Auto-update on shell startup** — too surprising, hits network on every
  shell. UC-10 nudge instead.
- **Two-way sync** between machines — git is the source of truth. Changes
  flow through commits.
- **Plugin manager for the dotfiles repo itself** — packages are files in
  the repo, not modules from external sources.
- **GUI configuration** — everything is a TOML or shell file. No
  app/web UI.
- **Per-project dotfiles** — this repo is the user's *global* config.
  Per-project tool versions live in that project's `.mise.toml`.
- **zsh on Windows** — Windows uses PowerShell as the daily shell. We
  ship a parallel pwsh shell-integration tree for the same tools, but
  zsh on Windows (via Cygwin/MSYS2/WSL) is the user's own choice and
  not a supported install target.
- **Cross-shell auto-translation** — we do NOT try to translate zsh
  integration snippets into pwsh on the fly. Each tool that needs shell
  hooks ships one short zsh file + one short pwsh file. See UC-6.

---

## Acceptance summary

| Goal | Use cases that prove it |
|---|---|
| One config, many platforms | UC-1, UC-2, UC-3, UC-9, UC-16 |
| Install only what you need | UC-2, UC-4, UC-7, UC-13, UC-14 |
| One-line install (friendly even when piped blind) | UC-1, UC-2, UC-3, UC-4, UC-18 |
| Easy sync + safe recovery | UC-9, UC-10, UC-11, UC-12, UC-17 |

Any architecture that doesn't make all 18 use cases natural is wrong.

# ARCHITECT.md — target architecture

This document is the **architectural contract**. It describes the system as
designed against the 18 use cases in [USECASES.md](USECASES.md). The
[Implementation status](#implementation-status) section at the end shows
which parts of this design are shipped vs. planned.

If you're contributing or reading code, also read [CLAUDE.md](../CLAUDE.md)
for the developer-facing conventions.

---

## 1. Goals

The architecture exists to deliver four things:

1. **One config, many platforms** — macOS, Linux, Windows treated as peers.
2. **Each machine installs only what it needs** — granular per-tool selection,
   not just coarse profiles.
3. **One-line install on a fresh machine** — single curl/iwr command sets up
   everything required.
4. **Sync is cheap and obvious** — `dotfiles sync` propagates repo changes;
   no surprise auto-updates.

Every architectural decision below is justified by mapping back to one or
more use cases. If a piece doesn't serve a use case, it's wrong.

---

## 2. Repo at a glance

```
~/.dotfiles/
├── bin/
│   ├── dotfiles            Bash CLI — Unix entrypoint for install/sync/doctor
│   └── dotfiles.ps1        PowerShell CLI — Windows entrypoint (planned)
├── Makefile                Windows symlink target — minimal, Git-Bash-driven
├── config/
│   ├── mise/config.toml    SINGLE source of truth for which tools are installed
│   ├── bat/                Each tool's user config — symlinked to ~/.config/<tool>/
│   ├── ripgrep/
│   ├── sheldon/
│   └── …
├── zsh/
│   ├── core/               Always-loaded zsh init (options, history, completion)
│   ├── lib/                Shared helpers (log.sh, ui.sh, installer.zsh, platform.zsh)
│   └── packages/           Tool packages and shell-integration files (Unix)
│       ├── core/           sheldon, tmux — lifecycle packages with full hooks
│       └── full/           00-mise.zsh + 01-mise-tools.zsh consolidated init
├── pwsh/                   Mirror of zsh/ for PowerShell (planned)
│   ├── profile/
│   └── packages/
├── docs/
│   ├── USECASES.md         The 18 use cases the architecture must support
│   └── ARCHITECT.md        This file
├── CLAUDE.md               Developer/agent conventions
└── README.md               User-facing quick start
```

Entry points by OS:

| OS | One-liner | Driver | Symlinks | Tool installs |
|---|---|---|---|---|
| macOS / Linux | `curl … \| bash` | `bin/dotfiles` (bash) | `bin/dotfiles link` | mise reads `config/mise/config.toml` |
| Windows | `iwr … \| iex` (planned) | `bin/dotfiles.ps1` / `make link` | `make link` (Git-Bash) | mise reads same `config/mise/config.toml` |

---

## 3. The two install mechanisms — and the line between them

Two things happen during `dotfiles install`. They have different owners.

### a. Tool binaries → owned by mise

`config/mise/config.toml` lists every binary the user wants. The dotfiles
installer's only job is to **install mise itself** and then run
`mise install --yes`. mise's backends (github releases for CLI tools, native
plugins for SDKs) handle per-OS binary fetching uniformly.

Why this matters: adding a tool is a one-line toml edit. No new shell file,
no new OS-conditional install branch. Every machine on every platform gets
the same version because the toml is the single source of truth.

### b. Lifecycle packages → owned by the 8-hook contract

A small set of tools need install/uninstall/health logic the package manager
can't express: **sheldon** (zsh plugin manager, bootstrap-only), **tmux**
(system library deps), **mise** itself (the install backbone). These live in
`zsh/packages/<profile>/*.zsh` and call `init_package_template "$PKG_NAME"`
to opt into the 8 lifecycle hooks (see [CLAUDE.md](../CLAUDE.md) for the
hook table).

Everything else — tool aliases, env vars, shell evals — lives in
shell-integration files that **do not** call `init_package_template`. They
just contain `command -v <tool> && eval …`-style snippets, gated so missing
tools no-op gracefully.

### The rule

| Need | Where it lives |
|---|---|
| "Install this binary" | `config/mise/config.toml` entry |
| "Set an alias / env var / run an eval" | `zsh/packages/<profile>/<tool>.zsh` and `pwsh/packages/<profile>/<tool>.ps1` (no template) |
| "Install/uninstall/health logic that mise can't express" | Package file calling `init_package_template` |

---

## 4. Profile + override model

The system uses one **active profile** plus two **override env vars**.

### Active profile

`DOTFILES_PROFILE` (stored in `~/.zshenv` managed block) selects a directory
under `zsh/packages/`. Profiles are filesystem-derived: any directory there
is a valid profile name. Profiles are cumulative — `core/` always loads
first, then the named profile loads on top.

Planned profile naming:

| Profile | Contains | Use case |
|---|---|---|
| `core` | sheldon, tmux, mise (bootstrap stack) | Always loaded |
| `server` | (empty — just core) | UC-2: thin VPS |
| `dev` | `00-mise.zsh` + `01-mise-tools.zsh` | UC-1: full workstation |

Today this is `core` and `full`. Migrating to `core / server / dev` is a
rename + content split.

### Override env vars

Stored in `~/.zshenv` managed block, written by `dotfiles config set`:

| Var | Purpose | Example |
|---|---|---|
| `DOTFILES_PROFILE` | Pick the active profile | `dev` |
| `DOTFILES_EXCLUDE` | Tools to drop from the profile (comma-sep) | `eza,bat` |
| `DOTFILES_EXTRA` | Tools to add on top (comma-sep) | `htop,starship` |
| `DOTFILES_VERBOSE` | Verbose logging on/off | `true` |

`dotfiles install` reads these and computes the effective install set —
this is how UC-7 ("skip a tool on this machine only") works without any
gitignored config file or per-machine repo fork.

---

## 5. Cross-platform strategy

Three platforms, two concerns, one rule per concern.

### Shell language

| Platform | Daily shell | Shell-init files |
|---|---|---|
| macOS / Linux | zsh | `zsh/packages/<profile>/*.zsh` |
| Windows | PowerShell 7+ | `pwsh/packages/<profile>/*.ps1` |

The two trees mirror each other. A tool that needs shell hooks ships one
short zsh file AND one short pwsh file (UC-6). We do not auto-translate —
that's magic that breaks on non-trivial snippets.

Cost: per-tool, the two files are usually 1-3 lines each. Net: small
duplication, predictable behavior.

### Tool binaries

mise installs the same versions on every OS via its github backend (single-
binary releases). `config/mise/config.toml` is the single source of truth
shared by all three platforms. No per-OS install branches in user-facing
code.

### Symlinks

Same `config/<tool>/` directories get symlinked into the OS-appropriate
location (`~/.config/<tool>/` on Unix; `$env:APPDATA\<tool>\` or
`~/.config/<tool>/` on Windows depending on what the tool expects).

---

## 6. Config sync model

Two-layer model:

### Layer 1 — repo configs (shared across all machines)

Every directory under `config/` gets symlinked into the appropriate
location at install time. Edit a file in the repo → symlinked file changes
instantly on every machine that pulled the commit. No re-install needed
for pure config edits (UC-16's "edit and go" property).

### Layer 2 — machine-local overrides (~/.zshenv, never in repo)

Per-machine selection, environment overrides, and tool selection
(`DOTFILES_PROFILE`, `DOTFILES_EXCLUDE`, `DOTFILES_EXTRA`, plus arbitrary
`export FOO=bar` lines for env-var-style tool config) live in `~/.zshenv`
inside a marker-delimited managed block:

```
# DOTFILES MANAGED BEGIN
export DOTFILES_PROFILE="dev"
export DOTFILES_EXCLUDE="eza"
export BAT_THEME="OneHalfLight"
# DOTFILES MANAGED END
```

`dotfiles config set <key> <value>` edits only the managed block —
preserves any user content above/below. The managed block is what makes
`dotfiles install` rerunnable without trashing the user's other zshenv
exports (UC-17 idempotency).

---

## 7. The interactive install menu (UC-18)

When `dotfiles install` (or the bootstrap one-liner) runs WITHOUT
`--profile=…` flags AND a TTY is available, an interactive menu appears
post-clone. Three rows: profile picker, "add tools" input, "exclude tools"
input. Two buttons: `install` and `defaults & install`.

Key implementation note: the bootstrap script uses `</dev/tty` so the menu
works even under `curl … | bash` (stdin is the pipe; the menu reads
keyboard via the controlling TTY).

When piped non-interactively (CI, headless install), defaults are applied
silently with a warning.

Flags always override: `--profile=dev --exclude=eza --extra=htop` skips the
menu entirely.

---

## 8. Recovery and idempotency (UC-17)

Recovery isn't a feature — it's an architectural invariant. Every step
of `dotfiles install` is a no-op when the state already matches:

- Lifecycle hooks (`pkg_post_install` etc.) MUST be idempotent (enforced
  by the hook contract in [CLAUDE.md](../CLAUDE.md)).
- `mise install --yes` skips already-installed-and-current tools.
- `~/.zshenv` managed-block writes are diff-and-replace, not append.
- Symlink creation removes existing links before recreating.

The user-facing consequence: **re-running `dotfiles install` is the
recovery mechanism**. No separate "repair" command. No half-states to
inspect manually. If something looks wrong, run it again.

For hard reset: `dotfiles clean --force && dotfiles install`.

---

## 9. Boot sequence (what happens when a shell starts)

### zsh (Unix)

1. `~/.zshenv` exports `DOTFILES_ROOT`, `DOTFILES_PROFILE`, overrides.
2. `~/.zshrc` (symlinked to repo) sources `zsh/core/*.zsh` (options,
   history, completion, theme).
3. `zsh/lib/platform.zsh` + `zsh/lib/installer.zsh` load (helpers).
4. Profile loop: source `zsh/packages/core/*.zsh`, then
   `zsh/packages/$DOTFILES_PROFILE/*.zsh` alphabetically.
5. Each file either calls `init_package_template` (lifecycle package — runs
   the install/init flow) or just executes its top-level shell code
   (shell-integration file).

Total target budget: < 200ms on a warm machine. Heavy work is deferred via
sheldon's `zsh-defer`.

### pwsh (Windows)

1. `$PROFILE` (symlinked to repo or generated by installer) reads override
   env vars.
2. Source `pwsh/packages/core/*.ps1` then `pwsh/packages/$DOTFILES_PROFILE/*.ps1`.
3. Same file-type split: lifecycle packages or shell-integration files.

---

## 10. Sync model (UC-9, UC-10)

Two-step explicit sync. No auto-update.

```bash
dotfiles sync   # = git pull --ff-only && dotfiles install
```

**Stale-sync nudge** (UC-10): on shell startup, if `.git/FETCH_HEAD` is
older than 7 days, print one non-blocking line: `[dotfiles] last synced
14 days ago — run \`dotfiles sync\``. No network call at shell startup.

Pure config-file edits (`config/bat/config` etc.) take effect immediately
after `git pull` because the file IS the symlink target — no re-install
needed for config-only changes. Tool additions/removals require
`dotfiles install` to materialize via mise.

---

## 11. Doctor — what gets reported (UC-12)

`dotfiles doctor` exits 0 if healthy, N if N issues. Always reports:

- Required tools present (git, curl, zsh, mise).
- Repo state (clean, ahead/behind, last-fetch age).
- Symlink integrity (every `config/<tool>/` has a working link target).
- Active profile + override summary.
- **Per-tool source provenance** — for each managed tool, where the binary
  on PATH came from: `mise` / `apt` / `brew` / `scoop` / `user`. First
  diagnostic when "wrong tool wins on PATH" happens.

Output: 256-color badge grid for the summary, per-tool detail below.

---

## 12. Logging — two-tier model (kept from prior architecture)

Unchanged from previous architecture. See [CLAUDE.md](../CLAUDE.md)
"Two-tier logging model" section.

- **Tier 1** (always-print): step / detail / result / summary / warning
  / error. Used by CLI commands (clean, doctor, install).
- **Tier 2** (verbose-only): debug / info / dim / success. Used by
  package hooks and shell startup. Silent unless `DOTFILES_VERBOSE=true`.

---

## 13. Architectural decisions

| Decision | Rationale |
|---|---|
| **mise as the unified tool installer** | One install path on every OS, version pinning across machines, eliminates 7+ duplicated apt/brew branches per tool. |
| **Bash for the CLI, zsh for daily shell, pwsh for Windows daily shell** | Bash runs before zsh is configured (bootstrap constraint). zsh has the ergonomics for daily use. pwsh is the Windows-native equivalent. |
| **Per-tool shell files (zsh + pwsh)** instead of one omnibus | Each tool's hooks stay co-located, easy to add/remove without ceremony. Two short files per tool is the smaller evil vs. cross-shell magic. |
| **Override vars in `~/.zshenv`** (not a gitignored toml) | One mechanism for all machine-local config. Same place existing vars live. Marker-block writes are already proven. |
| **Interactive menu when flags absent + TTY available** | Non-tech users don't always know the flag form. `</dev/tty` lets the menu work under `curl \| bash`. |
| **No auto-sync on shell startup** | Surprises break sessions. Stale nudge is the friendly middle ground. |
| **Idempotency as architecture, not a feature** | Recovery from any state via re-running install. No separate "repair" code. |
| **Windows = mise + Makefile + pwsh tree** (not symlinks-only) | mise's cross-platform binaries make this affordable. Promotes Windows from second-class to peer. |
| **No cross-shell translator** | Translating zsh snippets to pwsh on the fly is magic that breaks. Two short files per tool, written once. |

---

## 14. Engineering invariants (NFRs)

Non-functional requirements that constrain HOW the architecture delivers
the use cases. A PR that violates any of these should be rejected even if
it adds a feature, because it's eroding the foundation everything else
stands on.

### User experience

**NFR-1: Two-tier output contract.**
- **What**: Normal CLI output is enough for the user to know what happened
  and what to do next. Adding `--verbose` (or `DOTFILES_VERBOSE=true`)
  surfaces additional debug detail useful for troubleshooting.
- **Why**: Friendly default for daily use; full visibility on demand.
- **How**: Tier-1 log helpers (`_dotfiles_log_step/detail/result/summary/
  warning/error/hint`) are the only ones used by CLI commands; Tier-2
  helpers (`_dotfiles_log_debug/info/dim/success`) gate on
  `DOTFILES_VERBOSE` and are reserved for hooks and shell startup. See
  [CLAUDE.md](../CLAUDE.md) "Two-tier logging model".

**NFR-2: Shell startup is fast and silent.**
- **What**: A new shell opens in under 200ms on a warm machine and prints
  no output on success. `DOTFILES_VERBOSE=true` (or `dotfiles config set
  verbose true`) flips this to print per-package init detail for
  debugging slow startup or missing tools.
- **Why**: A noisy shell breaks scripts, makes terminal output unreadable,
  and a slow shell breaks flow.
- **How**: All `pkg_init` hooks use Tier-2 logging only. Heavy work
  (plugin install, mise tool sync) is gated behind `DOTFILES_INSTALL=true`
  and runs in `dotfiles install`, never on shell open. Plugin loading
  uses sheldon's `zsh-defer` for non-critical sources.

### Reliability

**NFR-A: Shell startup MUST complete even if a tool failed.**
- **What**: A failed mise install, an unreachable binary, a yanked
  upstream version — none of these may prevent zsh/pwsh from opening to
  a usable prompt.
- **Why**: A broken tool should degrade gracefully, not lock the user out
  of their shell. The shell is the recovery surface.
- **How**: Every `pkg_init` gates on `command -v <tool> &>/dev/null`
  before running tool-dependent code. Missing tools are reported as
  warnings, never as fatal errors. `init_package_template` catches
  `pkg_init` failures and logs them without aborting the chain.

**NFR-C: Idempotency is a contract, not best-effort.**
- **What**: Every install operation MUST be safe to re-run against any
  prior state — including partially-applied state from a previous
  interrupted run. `dotfiles install` always converges to "what the
  config declares."
- **Why**: UC-17 (recovery) depends on this. The absence of a separate
  "repair" command depends on this. Re-running install IS the recovery
  mechanism.
- **How**: `pkg_post_install` is documented as MUST-be-idempotent.
  `mise install --yes` short-circuits already-installed-and-current
  tools. `~/.zshenv` writes are marker-delimited diff-and-replace, not
  append. Symlink creation removes existing links before recreating.

### Operational

**NFR-B: Daily operation requires no network.**
- **What**: Shell startup, `dotfiles status`, `dotfiles doctor`,
  `dotfiles config`, and any `dotfiles config set …` operation must
  complete fully offline. ONLY `install`, `sync`, and `update` may make
  network calls.
- **Why**: Plane, train, airgapped server, flaky wifi, deliberate
  isolation. The dotfiles can't be a single point of failure for the
  user being able to use their shell.
- **How**: No code paths in shell startup or read-only commands may
  invoke `curl`, `git fetch`, `mise install`, or similar. Stale-sync
  nudge (UC-10) reads only `.git/FETCH_HEAD` mtime — local file stat,
  no network. Code review: any new `curl`/`wget`/`git fetch` in
  non-install paths is a defect.

**NFR-D: Profile renames keep legacy aliases for at least one major version.**
- **What**: Renaming a profile (e.g. `full` → `dev`) MUST accept the old
  name as a transparent alias for at least one release cycle. Machines
  pulling the update don't break on `git pull` — they keep working with
  the old name, with a warning suggesting they update.
- **Why**: The repo is consumed by N machines that pull on different
  schedules. Breaking one of them silently because the profile they
  reference no longer exists is a self-inflicted incident.
- **How**: `bin/dotfiles` profile resolution maps `minimal → core` and
  `server → full` today; same pattern applies forward. Legacy aliases
  log a one-shot warning then proceed. Removal of an alias requires a
  major version bump and a release note.

### Code quality

**NFR-3: Each language follows its own naming conventions.**
- **What**: Bash/zsh code uses `snake_case` functions, `lowercase_with_
  underscores` files. PowerShell code uses `Verb-Noun` PascalCase
  functions (approved verbs only), `$camelCase` locals, `$PascalCase`
  module-scoped vars. POSIX sh follows bash conventions. See
  [CLAUDE.md](../CLAUDE.md) "Naming conventions" for the full table.
- **Why**: Each language has decades of community-built tooling
  (linters, IDE features, completion) that expect its native conventions.
  Cross-language consistency (e.g. forcing `snake_case` in pwsh) breaks
  those tools and signals "I don't know this language" to readers.
- **How**: Linters per language where available (`shellcheck` for
  bash/sh, `PSScriptAnalyzer` for pwsh). Code review checks naming
  against the table in CLAUDE.md.

---

## 15. Implementation status

| Area | State | Notes |
|---|---|---|
| Bash CLI (`bin/dotfiles`) | ✓ Shipped | install/sync/status/config/doctor/clean/uninstall/link/packages/menu |
| `core/full` profiles | ✓ Shipped | Filesystem-derived; cumulative |
| mise as installer | ✓ Shipped | `00-mise.zsh` package + `config/mise/config.toml` manifest |
| Consolidated shell-init (`01-mise-tools.zsh`) | ✓ Shipped | 7 CLI tools' aliases/env in one file |
| Symlink engine | ✓ Shipped | `link_directory_files` walks `config/*` |
| `~/.zshenv` marker-block config | ✓ Shipped | `dotfiles config set <key> <value>` |
| Two-tier logging | ✓ Shipped | `zsh/lib/log.sh` |
| Doctor (basic) | ✓ Shipped | Per-package; provenance reporting in `pkg_doctor` |
| Makefile Windows symlinks | ✓ Shipped | `make link/unlink/verify` |
| `core / server / dev` profile rename + split | ✓ Shipped | `full/` → `dev/`; empty `server/` directory; legacy `full` alias warns + migrates |
| `DOTFILES_EXCLUDE` / `DOTFILES_EXTRA` overrides | ✓ Shipped | `dotfiles config set exclude/extra <csv>`; mise applies per-tool at install time |
| Interactive install menu (UC-18) | ✓ Shipped | `dotfiles install` (no flags) on a TTY → profile/extra/exclude picker; `</dev/tty` works under `curl \| bash` |
| Doctor provenance reporting (UC-12) | ✓ Shipped | `pkg_doctor` walks `mise current` and labels each tool's source (mise/brew/apt/dnf/user/unknown) |
| Stale-sync nudge (UC-10) | ✓ Shipped | `zsh/core/70-sync-nudge.zsh` — local stat on `.git/FETCH_HEAD`, no network |
| Windows pwsh tree (`pwsh/packages/`) | ✓ Shipped | `pwsh/lib/Log.ps1` + `Platform.ps1`; `pwsh/profile/Initialize-Dotfiles.ps1`; `pwsh/packages/dev/00-Mise.ps1` + `01-MiseTools.ps1` |
| Windows one-liner (`iwr … \| iex`) | ✓ Shipped | `bin/bootstrap.ps1` — bootstraps scoop, git, mise; clones repo; hands off to `dotfiles.ps1 install` |
| `bin/dotfiles.ps1` | ✓ Shipped | install/sync/update/status/config/doctor/link/unlink parity with bash CLI |

**Migration order recommendation**: profile rename → override vars →
interactive menu → doctor provenance → pwsh tree → Windows one-liner.
Each step is independently useful; the order minimizes rework.

---

See [USECASES.md](USECASES.md) for the 18 use cases this architecture must
deliver. See [CLAUDE.md](../CLAUDE.md) for developer/agent conventions.

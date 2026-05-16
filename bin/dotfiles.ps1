#!/usr/bin/env pwsh
# =============================================================================
# bin/dotfiles.ps1 — Windows-native CLI (mirror of bin/dotfiles bash CLI).
#
# Subcommands (parity goals, not full feature parity):
#   install    Symlink configs + install mise tools
#   sync       git pull --ff-only then install
#   update     git pull --rebase (no install)
#   status     Snapshot of profile, git state, symlinks
#   config     get/set/list/edit/keys for $PROFILE managed block
#   doctor     Read-only health check
#   link       Create/refresh symlinks (native pwsh New-Item -ItemType SymbolicLink)
#   unlink     Remove managed symlinks
#   help       Show usage
#
# Symlinks are created natively in pwsh — no Makefile, no Git Bash, no `make`
# dependency. Tool install is mise. $PROFILE injection writes a marker-
# delimited block so user content above/below is preserved.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Position=0)] [string]$Command,
    [Parameter(Position=1, ValueFromRemainingArguments=$true)] [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

# Force UTF-8 console encoding so emoji/box-drawing in log helpers render
# correctly in Windows Terminal. `chcp 65001` is the load-bearing one — it
# changes the active console code page that Windows Terminal reads. The
# .NET assignments cover the pipeline encoding for completeness. Idempotent.
try {
    if ($IsWindows -or $env:OS -eq 'Windows_NT') { chcp 65001 > $null 2>&1 }
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding            = [System.Text.Encoding]::UTF8
} catch { }

# ── Resolve repo root + load libs ────────────────────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DotfilesRoot = if ($env:DOTFILES_ROOT) { $env:DOTFILES_ROOT } else { Split-Path -Parent $ScriptDir }
$env:DOTFILES_ROOT = $DotfilesRoot

$LibDir = Join-Path $DotfilesRoot 'pwsh\lib'
if (Test-Path $LibDir) {
    foreach ($f in Get-ChildItem -Path $LibDir -Filter '*.ps1' -File) { . $f.FullName }
} else {
    function Write-DotfilesStep    { param($m) Write-Host "→ $m" }
    function Write-DotfilesDetail  { param($m) Write-Host "  • $m" }
    function Write-DotfilesResult  { param($l,$v) Write-Host "  ${l}: $v" }
    function Write-DotfilesSummary { param($m) Write-Host "✓ $m" }
    function Write-DotfilesWarning { param($m) [Console]::Error.WriteLine("⚠  $m") }
    function Write-DotfilesError   { param($m) [Console]::Error.WriteLine("✗ $m") }
    function Write-DotfilesHint    { param($m) [Console]::Error.WriteLine("  hint: $m") }
}

# ── Globals ──────────────────────────────────────────────────────────────────
$ConfigFile = if ($PROFILE.CurrentUserAllHosts) { $PROFILE.CurrentUserAllHosts } else { $PROFILE }
$ManagedBegin = '# DOTFILES MANAGED BEGIN — do not edit between markers; use `dotfiles config set`'
$ManagedEnd   = '# DOTFILES MANAGED END'
$ValidProfiles = @('core', 'server', 'dev')

# config/* dirs to NOT dir-symlink. Each name listed here is either special-
# cased (file-by-file symlinks elsewhere) or platform-specific and skipped on
# Windows:
#   claude → per-file into ~/.claude/, not a dir symlink
#   mise   → only the conf.d/*.toml shards get linked; ~/.config/mise/config.toml
#            must stay machine-local because `mise use -g` writes there
#   skhd, yabai → macOS-only daemons
$ExcludeConfigDirs = @('claude', 'mise', 'skhd', 'yabai')

# ── Helpers ──────────────────────────────────────────────────────────────────
function Get-ConfigValue {
    param([string]$Key)
    if (-not (Test-Path $ConfigFile)) { return '' }
    $pattern = "^\s*\`$env:$Key\s*=\s*['""](.*)['""]"
    $line = (Get-Content $ConfigFile -EA SilentlyContinue | Select-String -Pattern $pattern | Select-Object -Last 1)
    if ($line -and $line.Matches.Count -gt 0) { return $line.Matches[0].Groups[1].Value }
    return ''
}

function Write-MiseOverrides {
    # Generate a per-machine mise overlay from DOTFILES_EXCLUDE / DOTFILES_EXTRA.
    # Lives at ~/.config/mise/conf.d/99-machine.toml — the `99-` prefix puts it
    # AFTER the shared shards (00-common.toml, 10-langs.toml, …) in alphabetical
    # load order, so machine settings override shared. The file is NOT a symlink
    # to the repo; each machine has its own.
    $confDir = Join-Path $HOME '.config\mise\conf.d'
    $overrideFile = Join-Path $confDir '99-machine.toml'

    $exParts = if ($env:DOTFILES_EXCLUDE) {
        $env:DOTFILES_EXCLUDE -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    } else { @() }
    $extraParts = if ($env:DOTFILES_EXTRA) {
        $env:DOTFILES_EXTRA -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    } else { @() }

    if ($exParts.Count -eq 0 -and $extraParts.Count -eq 0) {
        if (Test-Path -LiteralPath $overrideFile) {
            Remove-Item -LiteralPath $overrideFile -Force -ErrorAction SilentlyContinue
        }
        return
    }

    if (-not (Test-Path -LiteralPath $confDir)) {
        New-Item -ItemType Directory -Path $confDir -Force | Out-Null
    }

    $lines = @(
        '# Generated by dotfiles install — do not edit by hand.'
        '# Edit via: dotfiles config set exclude <comma-list>'
        '#           dotfiles config set extra   <comma-list>'
        ''
    )
    if ($exParts.Count -gt 0) {
        $quoted = ($exParts | ForEach-Object { '"' + $_ + '"' }) -join ', '
        $lines += '[settings]'
        $lines += "disable_tools = [$quoted]"
        $lines += ''
    }
    if ($extraParts.Count -gt 0) {
        $lines += '[tools]'
        foreach ($t in $extraParts) {
            $lines += '"' + $t + '" = "latest"'
        }
    }
    Set-Content -LiteralPath $overrideFile -Value ($lines -join "`r`n")
}

function Save-DotfilesConfig {
    # Writes the marker block to $ConfigFile, preserving any user content
    # outside the markers. Strips ALL existing managed blocks first, then
    # appends one fresh block — self-heals duplicates that previous bugs
    # accumulated. The strip regex tolerates CRLF line endings (the `^…$`
    # multiline form did not, which is how duplicates piled up).
    $profile_value = if ($env:DOTFILES_PROFILE) { $env:DOTFILES_PROFILE } else { 'core' }
    $verbose_value = if ($env:DOTFILES_VERBOSE) { $env:DOTFILES_VERBOSE } else { 'false' }
    $exclude_value = if ($env:DOTFILES_EXCLUDE) { $env:DOTFILES_EXCLUDE } else { '' }
    $extra_value   = if ($env:DOTFILES_EXTRA)   { $env:DOTFILES_EXTRA }   else { '' }

    $block = @(
        $ManagedBegin
        "`$env:DOTFILES_ROOT    = '$DotfilesRoot'"
        "`$env:DOTFILES_PROFILE = '$profile_value'"
        "`$env:DOTFILES_VERBOSE = '$verbose_value'"
        "`$env:DOTFILES_EXCLUDE = '$exclude_value'"
        "`$env:DOTFILES_EXTRA   = '$extra_value'"
        ". '$DotfilesRoot\pwsh\profile\Initialize-Dotfiles.ps1'"
        $ManagedEnd
    ) -join "`r`n"

    $dir = Split-Path -Parent $ConfigFile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if (Test-Path $ConfigFile) {
        $content = Get-Content $ConfigFile -Raw
        # Strip every managed block (and any whitespace immediately after).
        # Using (?s) only — no multiline ^/$ anchors that fight CRLF endings.
        $stripped = [regex]::Replace(
            $content,
            '(?s)# DOTFILES MANAGED BEGIN.*?# DOTFILES MANAGED END\s*',
            ''
        )
        $stripped = $stripped.TrimEnd()
        if ($stripped) {
            Set-Content -Path $ConfigFile -Value ($stripped + "`r`n`r`n" + $block + "`r`n") -NoNewline
        } else {
            Set-Content -Path $ConfigFile -Value ($block + "`r`n") -NoNewline
        }
    } else {
        Set-Content -Path $ConfigFile -Value ($block + "`r`n") -NoNewline
    }

    # Keep the mise overlay in sync with EXCLUDE/EXTRA.
    Write-MiseOverrides
}

function Test-DotfilesFirstInstall {
    # First install = $PROFILE doesn't yet contain our managed block.
    if (-not (Test-Path $ConfigFile)) { return $true }
    $content = Get-Content $ConfigFile -Raw -ErrorAction SilentlyContinue
    return -not ($content -match '^# DOTFILES MANAGED BEGIN')
}

# ── Subcommands ──────────────────────────────────────────────────────────────
function Invoke-Install {
    Write-DotfilesStep "Installing dotfiles (profile=$($env:DOTFILES_PROFILE ?? 'core'))"
    $env:DOTFILES_INSTALL = 'true'

    # 0. Apply Windows-only defaults on FIRST install — exclude tools that fail
    # under mise's default registry on Windows and add aqua: backends for them.
    # Skipped if user already has a managed block (i.e. they've installed before
    # and may have chosen their own exclude/extra values).
    if ((Test-DotfilesFirstInstall) -and ($IsWindows -or $env:OS -eq 'Windows_NT')) {
        if (-not $env:DOTFILES_EXCLUDE) { $env:DOTFILES_EXCLUDE = 'eza' }
        if (-not $env:DOTFILES_EXTRA)   { $env:DOTFILES_EXTRA   = 'aqua:eza-community/eza' }
    }

    # 1. Symlinks — native pwsh, no Makefile dependency.
    $rc = Invoke-Link
    if ($rc -ne 0) {
        Write-DotfilesWarning "link reported $rc issue(s) — see output above"
    }

    # 1b. Pre-create ~/.config/mise/config.toml as a non-symlink placeholder.
    # mise's `use -g` writes go here. Without this file, mise falls back to
    # writing into the alphabetically-first conf.d/*.toml — which IS a symlink
    # to the repo — and silently leaks per-machine tools into the synced manifest.
    $miseLocal = Join-Path $HOME '.config\mise\config.toml'
    if (-not (Test-Path -LiteralPath $miseLocal)) {
        $miseDir = Split-Path -Parent $miseLocal
        if (-not (Test-Path -LiteralPath $miseDir)) {
            New-Item -ItemType Directory -Path $miseDir -Force | Out-Null
        }
        @(
            '# Machine-local mise config — NOT synced via dotfiles.'
            '# Written by `mise use -g <tool>` and similar interactive commands.'
            '# Shared declarations live in ~/.config/mise/conf.d/*.toml (symlinks to the repo).'
        ) -join "`n" | Set-Content -LiteralPath $miseLocal -Encoding utf8 -NoNewline
    }

    # 2. Drop the mise overlay so DOTFILES_EXCLUDE/EXTRA take effect on install.
    Write-MiseOverrides

    # 3. Mise + tool install — dot-source the package to fire its init.
    . (Join-Path $DotfilesRoot 'pwsh\packages\dev\00-Mise.ps1')

    # 4. Write the $PROFILE managed block (also regenerates the mise overlay).
    Save-DotfilesConfig
    Write-DotfilesSummary 'Dotfiles installed — open a new pwsh tab or run `. $PROFILE`'
    $env:DOTFILES_INSTALL = $null
    return 0
}

function Invoke-Sync {
    Write-DotfilesStep 'git pull --ff-only'
    & git -C $DotfilesRoot pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Write-DotfilesError "git pull failed (exit $LASTEXITCODE)"
        return 1
    }
    return (Invoke-Install)
}

function Invoke-Update {
    & git -C $DotfilesRoot pull --rebase
    return $LASTEXITCODE
}

function Invoke-Status {
    Write-DotfilesStep 'Status'
    Write-DotfilesResult 'profile' ($env:DOTFILES_PROFILE ?? 'core')
    Write-DotfilesResult 'verbose' ($env:DOTFILES_VERBOSE ?? 'false')
    Write-DotfilesResult 'exclude' ($env:DOTFILES_EXCLUDE ?? '(none)')
    Write-DotfilesResult 'extra'   ($env:DOTFILES_EXTRA   ?? '(none)')
    Write-DotfilesResult 'root'    $DotfilesRoot
    if (Test-Path (Join-Path $DotfilesRoot '.git')) {
        $branch = (& git -C $DotfilesRoot symbolic-ref --short HEAD 2>$null)
        $sha    = (& git -C $DotfilesRoot rev-parse --short HEAD 2>$null)
        $dirty  = (& git -C $DotfilesRoot status --porcelain 2>$null | Measure-Object -Line).Lines
        Write-DotfilesResult 'branch' "$branch ($sha)$( if ($dirty -gt 0) { ' (dirty)' } )"
    }
    return 0
}

function Invoke-ConfigCommand {
    # Param name MUST NOT be `$Args` — that name collides with PowerShell's
    # automatic $args variable, and the parameter binder silently drops the
    # value passed via `-Args …`. Symptom: every subcommand fell through to
    # the default `list` action because $Args inside was always empty.
    param([string[]]$ConfigArgs)
    $action = if ($ConfigArgs.Count -gt 0) { $ConfigArgs[0] } else { 'list' }
    switch ($action) {
        'list'    {
            Write-DotfilesResult 'profile' (Get-ConfigValue DOTFILES_PROFILE)
            Write-DotfilesResult 'verbose' (Get-ConfigValue DOTFILES_VERBOSE)
            Write-DotfilesResult 'exclude' (Get-ConfigValue DOTFILES_EXCLUDE)
            Write-DotfilesResult 'extra'   (Get-ConfigValue DOTFILES_EXTRA)
            Write-DotfilesResult 'file'    $ConfigFile
        }
        'get'     {
            if ($ConfigArgs.Count -lt 2) { Write-DotfilesError 'Usage: dotfiles config get <key>'; return 1 }
            Write-Output (Get-ConfigValue ("DOTFILES_" + $ConfigArgs[1].ToUpper()))
        }
        'set'     {
            if ($ConfigArgs.Count -lt 2) { Write-DotfilesError 'Usage: dotfiles config set <key> <value>'; return 1 }
            $key = $ConfigArgs[1].ToLower()
            $value = if ($ConfigArgs.Count -ge 3) { $ConfigArgs[2] } else { '' }
            switch ($key) {
                'profile' {
                    if ($value -notin $ValidProfiles) {
                        Write-DotfilesError "Unknown profile '$value' (valid: $($ValidProfiles -join ', '))"; return 1
                    }
                    $env:DOTFILES_PROFILE = $value
                }
                'verbose' {
                    if ($value -notin @('true','false')) {
                        Write-DotfilesError "verbose must be 'true' or 'false'"; return 1
                    }
                    $env:DOTFILES_VERBOSE = $value
                }
                'exclude' { $env:DOTFILES_EXCLUDE = $value }
                'extra'   { $env:DOTFILES_EXTRA   = $value }
                default   { Write-DotfilesError "Unknown key: $key"; return 1 }
            }
            Save-DotfilesConfig
            Write-DotfilesSummary "$key = $value"
        }
        'edit'    { & $env:EDITOR $ConfigFile }
        'path'    { Write-Output $ConfigFile }
        'keys'    { 'profile','verbose','exclude','extra' | ForEach-Object { Write-Output $_ } }
        default   { Write-DotfilesError "Unknown action: $action"; return 1 }
    }
    return 0
}

function Invoke-ClaudeClean {
    # Strip session-volatile keys from the synced config/claude/settings.json
    # so `git status` stops showing churn from /model, /effort, UI toggles, etc.
    # Mirrors bin/dotfiles claude_clean(). Dry-run by default; --force applies.
    # Requires jq (shipped via mise on every profile that needs it).
    param([switch]$Force)

    $target = Join-Path $DotfilesRoot 'config\claude\settings.json'
    Write-DotfilesStep 'Claude clean'

    if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
        Write-DotfilesError 'jq required but not installed'
        Write-DotfilesHint  'install via: dotfiles install  (jq ships with the dev profile)'
        return 1
    }
    if (-not (Test-Path -LiteralPath $target)) {
        Write-DotfilesError "settings.json not found: $target"
        return 1
    }

    # Keep this list in sync with bin/dotfiles claude_clean().
    $noise = @(
        'model','effortLevel','awaySummaryEnabled','preferredNotifChannel',
        'inputNeededNotifEnabled','skipAutoPermissionPrompt',
        'feedbackSurveyState','lastOnboardingVersion','subscriptionNoticeCount',
        'firstStartTime'
    )

    # Treat only currently-present keys as drift (so "already clean" is silent).
    $removed = @()
    foreach ($k in $noise) {
        & jq -e "has(`"$k`")" $target *> $null
        if ($LASTEXITCODE -eq 0) { $removed += $k }
    }
    if ($removed.Count -eq 0) {
        Write-DotfilesSummary 'Already clean — no volatile keys present.'
        return 0
    }

    # One jq invocation deletes all noise keys at once.
    $delArgs = ($noise | ForEach-Object { ".$_" }) -join ', '
    $filter  = "del($delArgs)"

    $jqLines = & jq $filter $target
    if ($LASTEXITCODE -ne 0) {
        Write-DotfilesError 'jq filter failed'
        return 1
    }

    if ($Force) {
        # Re-join with LF + UTF-8 no-BOM so the output byte-matches the bash
        # CLI run via Git Bash (jq writes LF + trailing newline). Avoids
        # round-trip line-ending churn in `git diff`.
        $tmp = [System.IO.Path]::GetTempFileName()
        $jqText = ($jqLines -join "`n") + "`n"
        [System.IO.File]::WriteAllText($tmp, $jqText, [System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $tmp -Destination $target -Force
        Write-DotfilesStep "Stripped $($removed.Count) volatile key(s):"
        foreach ($k in $removed) { Write-DotfilesDetail $k }
        Write-DotfilesSummary "Wrote $target"
    } else {
        Write-DotfilesStep "Would strip $($removed.Count) volatile key(s) (dry-run):"
        foreach ($k in $removed) { Write-DotfilesDetail $k }
        Write-DotfilesDetail 'Pass --force to apply.'
    }
    return 0
}

function Invoke-Doctor {
    $issues = 0
    Write-DotfilesStep 'Checking required tools'
    foreach ($t in @('git','make','mise')) {
        if (Get-Command $t -ErrorAction SilentlyContinue) {
            Write-DotfilesResult $t (Get-Command $t).Source
        } else {
            Write-DotfilesWarning "$t not found"; $issues++
        }
    }
    Write-DotfilesStep 'Checking symlinks'
    $issues += (Invoke-Verify)
    if (Test-Path (Join-Path $DotfilesRoot 'pwsh\packages\dev\00-Mise.ps1')) {
        . (Join-Path $DotfilesRoot 'pwsh\packages\dev\00-Mise.ps1')
        $issues += (Test-DotfilesMiseHealth)
    }
    if ($issues -eq 0) {
        Write-DotfilesSummary 'Healthy — 0 issues'
    } else {
        Write-DotfilesWarning "Found $issues issue(s)"
    }
    return $issues
}

# ── Symlink helpers (native pwsh — replaces make link/unlink/verify) ────────

function Test-NativeSymlinkSupport {
    # Probe by creating a real symlink — Developer Mode or admin required on
    # Windows for non-admin native symlinks. Returns $true if supported.
    $probe = Join-Path $env:TEMP "_dotfiles_symlink_probe_$([guid]::NewGuid().Guid)"
    try {
        New-Item -ItemType SymbolicLink -Path $probe -Value $env:TEMP -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

function New-DotfilesSymlink {
    # Create or refresh a single symlink. Idempotent: removes an existing
    # symlink before recreating; refuses to overwrite a real file/dir.
    param([Parameter(Mandatory)][string]$LinkPath,
          [Parameter(Mandatory)][string]$TargetPath)
    if (Test-Path -LiteralPath $LinkPath) {
        $item = Get-Item -LiteralPath $LinkPath -Force
        if ($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction') {
            Remove-Item -LiteralPath $LinkPath -Force -ErrorAction SilentlyContinue
        } else {
            Write-DotfilesWarning "SKIP $LinkPath exists and is not a symlink"
            return $false
        }
    }
    $parent = Split-Path -Parent $LinkPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    try {
        New-Item -ItemType SymbolicLink -Path $LinkPath -Value $TargetPath -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-DotfilesWarning "Failed to link $LinkPath -> $TargetPath ($($_.Exception.Message))"
        return $false
    }
}

function Get-DotfilesLinkPairs {
    # Yield [pscustomobject]@{Name; Source; Link} for every managed symlink.
    # config/* (minus exclude list) → ~/.config/* (dir symlinks)
    # config/claude/* (files only)  → ~/.claude/*   (per-file symlinks)
    $configDir = Join-Path $DotfilesRoot 'config'
    $homeDir = $HOME
    foreach ($pkg in Get-ChildItem -Path $configDir -Directory -ErrorAction SilentlyContinue) {
        if ($ExcludeConfigDirs -contains $pkg.Name) { continue }
        [pscustomobject]@{
            Name   = "~/.config/$($pkg.Name)"
            Source = $pkg.FullName
            Link   = Join-Path (Join-Path $homeDir '.config') $pkg.Name
        }
    }
    $claudeSrc = Join-Path $configDir 'claude'
    if (Test-Path -LiteralPath $claudeSrc) {
        foreach ($f in Get-ChildItem -Path $claudeSrc -File -ErrorAction SilentlyContinue) {
            [pscustomobject]@{
                Name   = "~/.claude/$($f.Name)"
                Source = $f.FullName
                Link   = Join-Path (Join-Path $homeDir '.claude') $f.Name
            }
        }
    }
    # mise: only link the conf.d shards. ~/.config/mise/config.toml is left
    # alone so `mise use -g` writes stay machine-local.
    $miseConfD = Join-Path $configDir 'mise\conf.d'
    if (Test-Path -LiteralPath $miseConfD) {
        $miseConfDTarget = Join-Path $homeDir '.config\mise\conf.d'
        foreach ($f in Get-ChildItem -Path $miseConfD -File -Filter '*.toml' -ErrorAction SilentlyContinue) {
            [pscustomobject]@{
                Name   = "~/.config/mise/conf.d/$($f.Name)"
                Source = $f.FullName
                Link   = Join-Path $miseConfDTarget $f.Name
            }
        }
    }
}

function Invoke-Link {
    if (-not (Test-NativeSymlinkSupport)) {
        Write-DotfilesError 'Cannot create native symlinks'
        Write-DotfilesHint  'Enable Developer Mode: Settings → Privacy & security → For developers'
        return 1
    }

    # One-time migration: older installs dir-symlinked the whole ~/.config/mise
    # to the repo. The new layout needs it as a real dir so per-file shard
    # symlinks can land inside. Only unlink if it points at THIS repo's
    # config/mise — never touch a foreign symlink.
    $miseDir = Join-Path $HOME '.config\mise'
    if (Test-Path -LiteralPath $miseDir) {
        $miseItem = Get-Item -LiteralPath $miseDir -Force
        if ($miseItem.LinkType -in @('SymbolicLink','Junction')) {
            $expected = [System.IO.Path]::GetFullPath((Join-Path $DotfilesRoot 'config\mise'))
            $actual = $miseItem.Target
            if ($actual -and [System.IO.Path]::IsPathRooted($actual)) {
                $actual = [System.IO.Path]::GetFullPath($actual)
            }
            if ($actual -ieq $expected) {
                Remove-Item -LiteralPath $miseDir -Force
                Write-DotfilesStep 'Migrated: replaced legacy ~/.config/mise dir-symlink with real dir'
            }
        }
    }

    $linked = 0; $skipped = 0
    foreach ($p in Get-DotfilesLinkPairs) {
        if (New-DotfilesSymlink -LinkPath $p.Link -TargetPath $p.Source) {
            Write-DotfilesDetail "link $($p.Name)"
            $linked++
        } else {
            $skipped++
        }
    }
    Write-DotfilesSummary "Linked $linked, skipped $skipped"
    return $skipped
}

function Invoke-Unlink {
    $removed = 0
    foreach ($p in Get-DotfilesLinkPairs) {
        if (Test-Path -LiteralPath $p.Link) {
            $item = Get-Item -LiteralPath $p.Link -Force
            if ($item.LinkType -eq 'SymbolicLink' -or $item.LinkType -eq 'Junction') {
                Remove-Item -LiteralPath $p.Link -Force -ErrorAction SilentlyContinue
                Write-DotfilesDetail "rm $($p.Name)"
                $removed++
            }
        }
    }
    Write-DotfilesSummary "Removed $removed symlink(s)"
    return 0
}

function Invoke-Verify {
    # Report OK / MISSING / STALE / CONFLICT per managed link.
    # Returns the count of non-OK entries (for doctor's issue tally).
    $issues = 0
    foreach ($p in Get-DotfilesLinkPairs) {
        if (-not (Test-Path -LiteralPath $p.Link)) {
            Write-DotfilesDetail "MISSING   $($p.Name)"
            $issues++
            continue
        }
        $item = Get-Item -LiteralPath $p.Link -Force
        if ($item.LinkType -notin @('SymbolicLink', 'Junction')) {
            Write-DotfilesDetail "CONFLICT  $($p.Name) (not a symlink)"
            $issues++
            continue
        }
        # Resolve-Path on a Windows symlink returns the link path itself, not
        # the target. Use $item.Target (the stored target) and normalize both
        # sides to compare correctly.
        $linkTarget = $item.Target
        if ($linkTarget -and -not [System.IO.Path]::IsPathRooted($linkTarget)) {
            $linkTarget = Join-Path (Split-Path -Parent $p.Link) $linkTarget
        }
        $resolvedTarget   = if ($linkTarget) { [System.IO.Path]::GetFullPath($linkTarget) } else { '' }
        $resolvedExpected = [System.IO.Path]::GetFullPath($p.Source)
        if ($resolvedTarget -ieq $resolvedExpected) {
            Write-DotfilesDetail "OK        $($p.Name)"
        } else {
            Write-DotfilesDetail "STALE     $($p.Name) -> $($item.Target)"
            $issues++
        }
    }
    return $issues
}

function Show-Usage {
    # Avoid here-strings — they're fragile on Windows when line endings get
    # converted by git, and any `<` inside trips PowerShell's parser when
    # the here-string fails to open. An array+join is bulletproof.
    @(
        'USAGE'
        '    dotfiles COMMAND [args]'
        ''
        'COMMANDS'
        '    install        Symlink configs + install mise tools'
        '    sync           git pull --ff-only + install'
        '    update         git pull --rebase (no install)'
        '    status         Snapshot of profile, overrides, git state'
        '    config ACTION  get/set/list/edit/path/keys'
        '    claude-clean   Strip session-volatile keys from claude settings.json'
        '    doctor         Read-only health check'
        '    link           Create/refresh symlinks'
        '    unlink         Remove managed symlinks'
        '    help, -h       Show this help'
        ''
        'EXAMPLES'
        '    dotfiles install'
        '    dotfiles config set profile dev'
        '    dotfiles config set exclude eza,bat'
        '    dotfiles claude-clean --force'
        '    dotfiles sync'
        '    dotfiles doctor'
        ''
        'See docs/USECASES.md for full scenarios.'
    ) | ForEach-Object { Write-Host $_ }
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
$exit = switch ($Command) {
    ''         { Show-Usage; 0 }
    'install'  { Invoke-Install }
    'sync'     { Invoke-Sync }
    'update'   { Invoke-Update }
    'status'   { Invoke-Status }
    'config'   { Invoke-ConfigCommand -ConfigArgs $Rest }
    'claude-clean' {
        $force = ($Rest.Count -gt 0 -and $Rest[0] -eq '--force')
        Invoke-ClaudeClean -Force:$force
    }
    'doctor'   { Invoke-Doctor }
    'link'     { Invoke-Link }
    'unlink'   { Invoke-Unlink }
    {$_ -in 'help','-h','--help'} { Show-Usage; 0 }
    default    { Write-DotfilesError "Unknown command: $Command"; Show-Usage; 1 }
}
exit $exit

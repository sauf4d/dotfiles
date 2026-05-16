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

# config/* dirs to NOT symlink. claude is special-cased (per-file into
# ~/.claude/, not a dir symlink); skhd + yabai are macOS-only daemons.
$ExcludeConfigDirs = @('claude', 'skhd', 'yabai')

# ── Helpers ──────────────────────────────────────────────────────────────────
function Get-ConfigValue {
    param([string]$Key)
    if (-not (Test-Path $ConfigFile)) { return '' }
    $pattern = "^\s*\`$env:$Key\s*=\s*['""](.*)['""]"
    $line = (Get-Content $ConfigFile -EA SilentlyContinue | Select-String -Pattern $pattern | Select-Object -Last 1)
    if ($line -and $line.Matches.Count -gt 0) { return $line.Matches[0].Groups[1].Value }
    return ''
}

function Save-DotfilesConfig {
    # Writes the marker block to $ConfigFile, preserving any user content
    # above/below the markers (matches the bash CLI's save_config behavior).
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
        if ($content -match "(?ms)^# DOTFILES MANAGED BEGIN.*?# DOTFILES MANAGED END$") {
            $content = $content -replace "(?ms)^# DOTFILES MANAGED BEGIN.*?# DOTFILES MANAGED END$", $block
        } else {
            $content = $content.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
        }
        Set-Content -Path $ConfigFile -Value $content -NoNewline
    } else {
        Set-Content -Path $ConfigFile -Value ($block + "`r`n")
    }
}

# ── Subcommands ──────────────────────────────────────────────────────────────
function Invoke-Install {
    Write-DotfilesStep "Installing dotfiles (profile=$($env:DOTFILES_PROFILE ?? 'core'))"
    $env:DOTFILES_INSTALL = 'true'

    # 1. Symlinks — native pwsh, no Makefile dependency.
    $rc = Invoke-Link
    if ($rc -ne 0) {
        Write-DotfilesWarning "link reported $rc issue(s) — see output above"
    }

    # 2. Mise + tool install — dot-source the package to fire its init.
    . (Join-Path $DotfilesRoot 'pwsh\packages\dev\00-Mise.ps1')

    # 3. Write the $PROFILE managed block.
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
    param([string[]]$Args)
    $action = if ($Args.Count -gt 0) { $Args[0] } else { 'list' }
    switch ($action) {
        'list'    {
            Write-DotfilesResult 'profile' (Get-ConfigValue DOTFILES_PROFILE)
            Write-DotfilesResult 'verbose' (Get-ConfigValue DOTFILES_VERBOSE)
            Write-DotfilesResult 'exclude' (Get-ConfigValue DOTFILES_EXCLUDE)
            Write-DotfilesResult 'extra'   (Get-ConfigValue DOTFILES_EXTRA)
            Write-DotfilesResult 'file'    $ConfigFile
        }
        'get'     {
            if ($Args.Count -lt 2) { Write-DotfilesError 'Usage: dotfiles config get <key>'; return 1 }
            Write-Output (Get-ConfigValue ("DOTFILES_" + $Args[1].ToUpper()))
        }
        'set'     {
            if ($Args.Count -lt 2) { Write-DotfilesError 'Usage: dotfiles config set <key> <value>'; return 1 }
            $key = $Args[1].ToLower()
            $value = if ($Args.Count -ge 3) { $Args[2] } else { '' }
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
}

function Invoke-Link {
    if (-not (Test-NativeSymlinkSupport)) {
        Write-DotfilesError 'Cannot create native symlinks'
        Write-DotfilesHint  'Enable Developer Mode: Settings → Privacy & security → For developers'
        return 1
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
        $target = (Resolve-Path -LiteralPath $p.Link -ErrorAction SilentlyContinue).Path
        $expected = (Resolve-Path -LiteralPath $p.Source -ErrorAction SilentlyContinue).Path
        if ($target -eq $expected) {
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
        '    doctor         Read-only health check'
        '    link           Create/refresh symlinks'
        '    unlink         Remove managed symlinks'
        '    help, -h       Show this help'
        ''
        'EXAMPLES'
        '    dotfiles install'
        '    dotfiles config set profile dev'
        '    dotfiles config set exclude eza,bat'
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
    'config'   { Invoke-ConfigCommand -Args $Rest }
    'doctor'   { Invoke-Doctor }
    'link'     { Invoke-Link }
    'unlink'   { Invoke-Unlink }
    {$_ -in 'help','-h','--help'} { Show-Usage; 0 }
    default    { Write-DotfilesError "Unknown command: $Command"; Show-Usage; 1 }
}
exit $exit

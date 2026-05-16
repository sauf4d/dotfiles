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
#   link       Create/refresh symlinks (delegates to make link via Git Bash)
#   unlink     Remove managed symlinks (delegates to make unlink)
#   help       Show usage
#
# Symlink operations shell out to `make link/unlink/verify` so we reuse the
# tested Makefile logic. Tool install is mise. $PROFILE injection writes a
# marker-delimited block so user content above/below is preserved.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Position=0)] [string]$Command,
    [Parameter(Position=1, ValueFromRemainingArguments=$true)] [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

# Force UTF-8 console encoding so emoji/box-drawing in log helpers render
# correctly in Windows Terminal (pwsh defaults to ANSI otherwise). Idempotent.
try {
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

    # 1. Symlinks via Makefile + Git Bash.
    if (Get-Command make -ErrorAction SilentlyContinue) {
        Write-DotfilesStep 'Linking configs via Makefile'
        & make -C $DotfilesRoot link
        if ($LASTEXITCODE -ne 0) {
            Write-DotfilesWarning "make link returned $LASTEXITCODE — symlinks may be incomplete"
        }
    } else {
        Write-DotfilesError 'make not found — install Git for Windows: scoop install git'
        return 1
    }

    # 2. Mise + tool install — dot-source the package to fire its init.
    $env:DOTFILES_INSTALL = 'true'
    . (Join-Path $DotfilesRoot 'pwsh\packages\dev\00-Mise.ps1')

    # 3. Write the $PROFILE managed block.
    Save-DotfilesConfig
    Write-DotfilesSummary "Dotfiles installed — open a new pwsh tab or run `. `$PROFILE`"
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
    Write-DotfilesStep 'Checking symlinks (make verify)'
    if (Get-Command make -ErrorAction SilentlyContinue) {
        & make -C $DotfilesRoot verify
        if ($LASTEXITCODE -ne 0) { $issues++ }
    }
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

function Invoke-Link   { & make -C $DotfilesRoot link;   return $LASTEXITCODE }
function Invoke-Unlink { & make -C $DotfilesRoot unlink; return $LASTEXITCODE }

function Show-Usage {
    @"
USAGE
    dotfiles <command> [args]

COMMANDS
    install        Symlink configs + install mise tools
    sync           git pull --ff-only + install
    update         git pull --rebase (no install)
    status         Snapshot of profile, overrides, git state
    config <act>   get/set/list/edit/path/keys
    doctor         Read-only health check
    link           Create/refresh symlinks (via make link)
    unlink         Remove managed symlinks
    help, -h       Show this help

EXAMPLES
    dotfiles install
    dotfiles config set profile dev
    dotfiles config set exclude eza,bat
    dotfiles sync
    dotfiles doctor

See docs/USECASES.md for full scenarios. The Windows pwsh CLI is a
parity port of bin/dotfiles (bash); see README.md for cross-platform
install instructions.
"@
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

# =============================================================================
# pwsh/profile/Initialize-Dotfiles.ps1 — PowerShell mirror of ~/.zshrc.
#
# Sourced from $PROFILE via a marker-delimited block written by
# `dotfiles.ps1 install`. Loads shared libraries, then walks the cumulative
# package dirs for the active profile (core ⊆ server ⊆ develop) in alpha order.
#
# Boot order:
#   1. Resolve $env:DOTFILES_ROOT and $env:DOTFILES_PROFILE (with fallbacks).
#   2. Source pwsh/lib/Log.ps1 and pwsh/lib/Platform.ps1.
#   3. For each package dir, dot-source every .ps1 file in alphabetical order.
#
# Files that mutate shell state must dot-source (`. <file>`) — calling
# them as `& <file>` would run in a child scope and lose their assignments.
# This loader uses `. ` (dot-source) for all package files.
# =============================================================================

# ── UTF-8 console encoding ──────────────────────────────────────────────────
# Without this, pwsh emits ANSI-encoded bytes for non-ASCII glyphs (emoji,
# box-drawing) and Windows Terminal renders them as `?`. `chcp 65001` changes
# the actual console code page; the .NET assignments cover pipeline encoding.
try {
    if ($IsWindows -or $env:OS -eq 'Windows_NT') { chcp 65001 > $null 2>&1 }
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding            = [System.Text.Encoding]::UTF8
} catch { }

# ── Bootstrap defaults ───────────────────────────────────────────────────────
if (-not $env:DOTFILES_ROOT) {
    $home_dir = if ($IsWindows) { $env:USERPROFILE } else { $env:HOME }
    $env:DOTFILES_ROOT = Join-Path $home_dir '.dotfiles'
}
if (-not $env:DOTFILES_PROFILE) {
    $env:DOTFILES_PROFILE = 'core'
}

# Validate
if (-not (Test-Path $env:DOTFILES_ROOT)) {
    [Console]::Error.WriteLine("ERROR: DOTFILES_ROOT not found: $env:DOTFILES_ROOT")
    return
}
if (-not (Test-Path (Join-Path $env:DOTFILES_ROOT 'pwsh'))) {
    [Console]::Error.WriteLine("ERROR: $env:DOTFILES_ROOT/pwsh not found — run dotfiles install")
    return
}

# Legacy aliases (mirrors bin/dotfiles set_defaults).
$_legacyAliases = @{ minimal = 'core'; full = 'develop'; dev = 'develop' }
if ($_legacyAliases.ContainsKey($env:DOTFILES_PROFILE)) {
    $_oldProfile = $env:DOTFILES_PROFILE
    $env:DOTFILES_PROFILE = $_legacyAliases[$_oldProfile]
    [Console]::Error.WriteLine("⚠  DOTFILES_PROFILE '$_oldProfile' migrated to '$($env:DOTFILES_PROFILE)'")
}

# ── Load shared libraries ────────────────────────────────────────────────────
$_libDir = Join-Path $env:DOTFILES_ROOT 'pwsh\lib'
if (Test-Path $_libDir) {
    foreach ($_f in Get-ChildItem -Path $_libDir -Filter '*.ps1' -File | Sort-Object Name) {
        . $_f.FullName
    }
}

# ── Load packages cumulatively (each profile is a strict superset) ──────────
# core    → core/
# server  → core/ + server/
# develop → core/ + server/ + develop/
$_pkgsRoot = Join-Path $env:DOTFILES_ROOT 'pwsh\packages'
switch ($env:DOTFILES_PROFILE) {
    'core'    { $_pkgDirs = @((Join-Path $_pkgsRoot 'core')) }
    'server'  { $_pkgDirs = @((Join-Path $_pkgsRoot 'core'),
                               (Join-Path $_pkgsRoot 'server')) }
    'develop' { $_pkgDirs = @((Join-Path $_pkgsRoot 'core'),
                               (Join-Path $_pkgsRoot 'server'),
                               (Join-Path $_pkgsRoot 'develop')) }
    default   {
        [Console]::Error.WriteLine("[dotfiles] Unknown profile '$env:DOTFILES_PROFILE' — defaulting to core")
        $_pkgDirs = @((Join-Path $_pkgsRoot 'core'))
    }
}

foreach ($_dir in $_pkgDirs) {
    if (-not (Test-Path $_dir)) { continue }
    foreach ($_pkgFile in Get-ChildItem -Path $_dir -Filter '*.ps1' -File | Sort-Object Name) {
        . $_pkgFile.FullName
    }
}

# ── Stale-sync nudge (UC-10) ─────────────────────────────────────────────────
# Pure local stat — no network. Matches zsh/core/70-sync-nudge.zsh.
if (-not (_IsQuiet) -and [Environment]::UserInteractive) {
    $_fetchHead = Join-Path $env:DOTFILES_ROOT '.git\FETCH_HEAD'
    if (Test-Path $_fetchHead) {
        $_ageDays = (New-TimeSpan -Start (Get-Item $_fetchHead).LastWriteTime -End (Get-Date)).TotalDays
        if ($_ageDays -ge 7) {
            [Console]::Error.WriteLine("[dotfiles] last synced $([int]$_ageDays) days ago — run ``dotfiles sync``")
        }
    }
}

Remove-Variable -Name _libDir, _pkgDirs, _pkgsRoot, _dir, _pkgFile, _f, _fetchHead, _ageDays, _legacyAliases, _oldProfile -ErrorAction SilentlyContinue

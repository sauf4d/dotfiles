# =============================================================================
# bin/bootstrap.ps1 — Windows one-liner installer.
#
# Hosted at https://tinyurl.com/get-dotfiles-win (or equivalent shortlink).
# Invoked as:
#
#     iwr -useb https://tinyurl.com/get-dotfiles-win | iex
#
# Responsibilities (in order):
#   1. Verify pwsh 7+ (hard requirement — many idioms use 7+ features).
#   2. Bootstrap scoop if missing.
#   3. scoop install git + mise (and pwsh if user is on 5.1).
#   4. Clone the dotfiles repo to $env:USERPROFILE\.dotfiles.
#   5. Hand off to bin\dotfiles.ps1 install.
#
# Designed to be re-runnable: every step is a no-op when its precondition
# already holds (idempotency, NFR-C).
# =============================================================================

$ErrorActionPreference = 'Stop'

# Force UTF-8 console encoding so emoji/box-drawing characters render in
# Windows Terminal. pwsh defaults to ANSI on Windows which turns them into '?'.
# `chcp 65001` is the load-bearing one — it changes the console code page
# that Windows Terminal reads. The two .NET assignments cover stdout pipeline
# encoding for completeness.
try {
    if ($IsWindows -or $env:OS -eq 'Windows_NT') { chcp 65001 > $null 2>&1 }
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding            = [System.Text.Encoding]::UTF8
} catch { }

function _say  { param($m) Write-Host "→ $m" -ForegroundColor Cyan }
function _ok   { param($m) Write-Host "✓ $m" -ForegroundColor Green }
function _warn { param($m) Write-Host "⚠  $m" -ForegroundColor Yellow }
function _err  { param($m) Write-Host "✗ $m" -ForegroundColor Red; exit 1 }

# ── 1. pwsh version check ────────────────────────────────────────────────────
if ($PSVersionTable.PSVersion.Major -lt 7) {
    _warn "PowerShell $($PSVersionTable.PSVersion) detected — pwsh 7+ required."
    _say  "Install with: winget install Microsoft.PowerShell"
    _say  "Or via scoop after bootstrapping scoop: scoop install pwsh"
    _err  "Re-run this script from pwsh 7+."
}

# ── 2. scoop ─────────────────────────────────────────────────────────────────
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    _say 'Bootstrapping scoop'
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        _err 'scoop install failed — see https://scoop.sh for manual steps'
    }
    _ok 'scoop installed'
} else {
    _ok 'scoop present'
}

# ── 3. git + mise ────────────────────────────────────────────────────────────
foreach ($tool in @('git', 'mise')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        _say "scoop install $tool"
        scoop install $tool
        if ($LASTEXITCODE -ne 0) { _err "$tool install failed (exit $LASTEXITCODE)" }
    } else {
        _ok "$tool present"
    }
}

# Developer Mode hint for symlinks (don't auto-enable — that's a system setting
# under the user's control, and it requires admin/PowerShell elevation).
_say "Symlink probe — Developer Mode must be on for non-admin native symlinks"
$probe = New-Item -ItemType SymbolicLink -Path "$env:TEMP\_dotfiles_probe" `
    -Value "$env:TEMP" -Force -ErrorAction SilentlyContinue
if ($probe) {
    Remove-Item $probe.FullName -Force -ErrorAction SilentlyContinue
    _ok 'Native symlinks available'
} else {
    _warn 'Native symlinks unavailable. Enable Developer Mode:'
    _warn '  Settings → Privacy & security → For developers → Developer Mode'
    _warn 'Continuing — make link will report broken links if not enabled.'
}

# ── 4. clone repo ────────────────────────────────────────────────────────────
$RepoUrl  = if ($env:DOTFILES_REPO) { $env:DOTFILES_REPO } else { 'https://github.com/ved0el/dotfiles.git' }
$RepoDir  = if ($env:DOTFILES_ROOT) { $env:DOTFILES_ROOT } else { Join-Path $env:USERPROFILE '.dotfiles' }
$env:DOTFILES_ROOT = $RepoDir

if (Test-Path (Join-Path $RepoDir '.git')) {
    _ok "Repo already exists at $RepoDir — pulling latest"
    & git -C $RepoDir pull --ff-only
} else {
    _say "Cloning $RepoUrl → $RepoDir"
    & git clone $RepoUrl $RepoDir
    if ($LASTEXITCODE -ne 0) { _err 'git clone failed' }
}

# ── 5. hand off to dotfiles.ps1 install ─────────────────────────────────────
_say 'Running dotfiles install'
& (Join-Path $RepoDir 'bin\dotfiles.ps1') install
if ($LASTEXITCODE -ne 0) {
    _err "dotfiles install returned $LASTEXITCODE — see output above"
}

_ok 'Bootstrap complete'
Write-Host ''
Write-Host '  NEXT STEPS' -ForegroundColor Cyan
Write-Host '    1. Open a new pwsh tab (or run: . $PROFILE)'
Write-Host '    2. Verify with: dotfiles status'
Write-Host '    3. For fzf keybindings: Install-Module PSFzf -Scope CurrentUser -Force'
Write-Host ''

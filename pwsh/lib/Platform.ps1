# =============================================================================
# pwsh/lib/Platform.ps1 — OS + package manager detection (mirror of
# zsh/lib/platform.zsh). All functions are idempotent; results cache in
# script scope after first call.
# =============================================================================

$script:DotfilesOsCache = $null
$script:DotfilesPkgMgrCache = $null

function Get-DotfilesOs {
    if ($script:DotfilesOsCache) { return $script:DotfilesOsCache }
    $script:DotfilesOsCache = if ($IsWindows) { 'windows' }
        elseif ($IsMacOS)   { 'macos' }
        elseif ($IsLinux)   { 'linux' }
        else                { 'unknown' }
    return $script:DotfilesOsCache
}

function Get-DotfilesPkgManager {
    if ($script:DotfilesPkgMgrCache) { return $script:DotfilesPkgMgrCache }
    $script:DotfilesPkgMgrCache = switch (Get-DotfilesOs) {
        'windows' {
            if (Get-Command scoop  -ErrorAction SilentlyContinue) { 'scoop' }
            elseif (Get-Command winget -ErrorAction SilentlyContinue) { 'winget' }
            else { 'unknown' }
        }
        'macos' {
            if (Get-Command brew -ErrorAction SilentlyContinue) { 'brew' } else { 'unknown' }
        }
        'linux' {
            if (Get-Command apt    -ErrorAction SilentlyContinue) { 'apt' }
            elseif (Get-Command dnf -ErrorAction SilentlyContinue) { 'dnf' }
            elseif (Get-Command pacman -ErrorAction SilentlyContinue) { 'pacman' }
            else { 'unknown' }
        }
        default { 'unknown' }
    }
    return $script:DotfilesPkgMgrCache
}

# Resolve the dotfiles repo root. Prefers $env:DOTFILES_ROOT; falls back to
# the canonical location under $HOME (Linux/macOS) or $env:USERPROFILE
# (Windows).
function Get-DotfilesRoot {
    if ($env:DOTFILES_ROOT) { return $env:DOTFILES_ROOT }
    $home_dir = if ($IsWindows) { $env:USERPROFILE } else { $env:HOME }
    return (Join-Path $home_dir '.dotfiles')
}

# Resolve the per-machine config file (PowerShell's analog to ~/.zshenv).
# Uses $PROFILE.CurrentUserAllHosts so plain `pwsh` and pwsh-as-script both
# pick up the values.
function Get-DotfilesConfigFile {
    if ($PROFILE -and $PROFILE.CurrentUserAllHosts) {
        return $PROFILE.CurrentUserAllHosts
    }
    return $PROFILE
}

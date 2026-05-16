# =============================================================================
# pwsh/packages/develop/MiseTools.ps1 — mirror of zsh/packages/develop/mise-tools.zsh.
#
# Consolidated shell integration for mise-managed CLI tools (bat, eza, fd,
# fzf, jq, ripgrep, zoxide). Each block is gated on Get-Command so a tool
# missing from PATH silently no-ops instead of erroring.
#
# Doctor reporting for these tools is handled by core/Mise.ps1's
# Test-DotfilesMiseHealth, which walks `mise current` and reports source.
#
# This file does NOT call Initialize-Package — it's shell config, not a
# lifecycle package.
# =============================================================================

# ── bat ──────────────────────────────────────────────────────────────────────
if ((Get-Command bat -ErrorAction SilentlyContinue) -and -not $env:MANPAGER) {
    $env:MANPAGER = "sh -c 'col -bx | bat -l man -p'"
}

# ── eza ──────────────────────────────────────────────────────────────────────
if (Get-Command eza -ErrorAction SilentlyContinue) {
    function global:ls   { eza --group-directories-first --icons=auto @args }
    function global:la   { eza --group-directories-first --icons=auto -a @args }
    function global:ll   { eza --group-directories-first --icons=auto -l --git --time-style=relative @args }
    function global:lla  { eza --group-directories-first --icons=auto -la --git --time-style=relative @args }
    function global:lt   { eza --group-directories-first --icons=auto --tree @args }
    function global:lt2  { eza --group-directories-first --icons=auto --tree --level=2 @args }
    function global:lt3  { eza --group-directories-first --icons=auto --tree --level=3 @args }
    function global:lta  { eza --group-directories-first --icons=auto --tree -a @args }
    function global:lm   { eza --group-directories-first --icons=auto -l --sort=modified --reverse --time-style=relative @args }
    function global:lz   { eza --group-directories-first --icons=auto -l --sort=size --reverse @args }
}

# ── fd ───────────────────────────────────────────────────────────────────────
if (Get-Command fd -ErrorAction SilentlyContinue) {
    $env:FD_OPTIONS = '--follow --hidden'
}

# ── ripgrep ──────────────────────────────────────────────────────────────────
if (Get-Command rg -ErrorAction SilentlyContinue) {
    $env:RIPGREP_CONFIG_PATH = Join-Path ($env:XDG_CONFIG_HOME ?? "$env:USERPROFILE\.config") 'ripgrep\ripgreprc'
}

# ── fzf (uses PSFzf module on pwsh; module must be installed separately) ────
if (Get-Command fzf -ErrorAction SilentlyContinue) {
    $env:FZF_DEFAULT_COMMAND  = 'fd --type f'
    $env:FZF_DEFAULT_OPTS     = "--height 75% --multi --reverse --margin=0,1 " +
                                "--bind ctrl-f:page-down,ctrl-b:page-up,ctrl-/:toggle-preview " +
                                "--bind pgdn:preview-page-down,pgup:preview-page-up " +
                                "--marker='✚' --pointer='▶' --prompt='❯ ' --no-separator --scrollbar='█'"
    $env:FZF_CTRL_R_OPTS      = '--no-preview'
    $env:FZF_CTRL_T_COMMAND   = "rg --files --hidden --follow --glob '!.git/*'"
    $env:FZF_CTRL_T_OPTS      = "--preview 'bat --line-range :100 {}'"
    $env:FZF_ALT_C_COMMAND    = 'fd --type d'
    if (Get-Command eza -ErrorAction SilentlyContinue) {
        $env:FZF_ALT_C_OPTS = "--preview 'eza --tree --level 2 --group-directories-first {}'"
    }

    # Keybindings via PSFzf if the user has installed it (one-time:
    # `Install-Module PSFzf -Scope CurrentUser -Force`). Skip silently
    # otherwise — fzf still works as a standalone command.
    if (Get-Module -ListAvailable -Name PSFzf) {
        Import-Module PSFzf -ErrorAction SilentlyContinue
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' -EA SilentlyContinue
    }
}

# ── zoxide ───────────────────────────────────────────────────────────────────
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    $env:_ZO_DOCTOR = '0'
    Invoke-Expression (& zoxide init powershell | Out-String)
    Set-Alias -Name cd -Value z -Option AllScope -Scope Global -ErrorAction SilentlyContinue
    Set-Alias -Name cdi -Value zi -Option AllScope -Scope Global -ErrorAction SilentlyContinue
}

# jq has no shell integration — pure binary. Presence reported by 00-Mise.ps1's
# Test-DotfilesMiseHealth via `mise current`.

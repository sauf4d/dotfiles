#!/usr/bin/env zsh

# 01-mise-tools — consolidated shell integration for mise-managed CLI tools.
#
# These tools (bat, eza, fd, fzf, jq, rg, zoxide) used to each have their own
# package file in the 8-hook contract. After moving install/uninstall to
# mise's manifest, the only thing left per tool was 1-3 aliases or env vars
# plus boilerplate doctor stubs. That's shell config, not package lifecycle —
# so it lives here in one place.
#
# Each block is gated on `command -v <tool>` so a tool missing from PATH
# (e.g. on a `core` profile, or before `mise install` has run) silently
# no-ops instead of erroring.
#
# Doctor reporting for these tools is handled by 00-mise.zsh's pkg_doctor,
# which calls `mise current` to list everything mise manages with versions.
#
# Load order: 00-mise.zsh activates mise (PATH gets all tool shims), then
# this file runs, then any tool-specific shell hooks fire. Don't rename.

# ── bat ────────────────────────────────────────────────────────────────────
# Use bat as the man page pager unless the user already chose one.
if command -v bat &>/dev/null && [[ -z "${MANPAGER:-}" ]]; then
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

# ── eza ────────────────────────────────────────────────────────────────────
if command -v eza &>/dev/null; then
    typeset _e="eza --group-directories-first --icons=auto"
    alias ls="$_e"
    alias la="$_e -a"
    alias ll="$_e -l --git --time-style=relative"
    alias lla="$_e -la --git --time-style=relative"
    alias lt="$_e --tree"
    alias lt2="$_e --tree --level=2"
    alias lt3="$_e --tree --level=3"
    alias lta="$_e --tree -a"
    alias lm="$_e -l --sort=modified --reverse --time-style=relative"
    alias lz="$_e -l --sort=size --reverse"
    unset _e
fi

# ── fd ─────────────────────────────────────────────────────────────────────
# --follow: cross symlinks. --hidden: include dotfiles (exclusions live in
# config/fd/ignore so they stay version-controlled out of this env var).
command -v fd &>/dev/null && export FD_OPTIONS="--follow --hidden"

# ── ripgrep ────────────────────────────────────────────────────────────────
command -v rg &>/dev/null && \
    export RIPGREP_CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/ripgreprc"

# ── fzf (must come before zoxide so _ZO_FZF_OPTS picks up FZF env defaults) ─
if command -v fzf &>/dev/null; then
    export FZF_DEFAULT_COMMAND="fd --type f"
    export FZF_DEFAULT_OPTS="--height 75% --multi --reverse --margin=0,1 \
        --bind ctrl-f:page-down,ctrl-b:page-up,ctrl-/:toggle-preview \
        --bind pgdn:preview-page-down,pgup:preview-page-up \
        --marker='✚' --pointer='▶' --prompt='❯ ' --no-separator --scrollbar='█' \
        --color bg+:#262626,fg+:#dadada,hl:#f09479,hl+:#f09479 \
        --color border:#303030,info:#cfcfb0,header:#80a0ff,spinner:#36c692 \
        --color prompt:#87afff,pointer:#ff5189,marker:#f09479"
    # Ctrl+R — history fuzzy search, no preview (commands are self-describing)
    export FZF_CTRL_R_OPTS="--no-preview"
    # Ctrl+T — file search; bat theme/color come from ~/.config/bat/config
    export FZF_CTRL_T_COMMAND="rg --files --hidden --follow --glob '!.git/*'"
    export FZF_CTRL_T_OPTS="--preview 'bat --line-range :100 {}'"
    # Alt+C — directory jump with eza tree preview when eza is also present
    export FZF_ALT_C_COMMAND="fd --type d"
    if command -v eza &>/dev/null; then
        export FZF_ALT_C_OPTS="--preview 'eza --tree --level 2 --group-directories-first {}'"
    fi

    # Wire up keybindings AFTER env vars so bindings inherit them.
    eval "$(fzf --zsh)"

    # macOS: Option+C sends ç instead of the ESC-c sequence fzf expects.
    [[ "$(uname)" == "Darwin" ]] && bindkey 'ç' fzf-cd-widget 2>/dev/null
fi

# ── zoxide ─────────────────────────────────────────────────────────────────
if command -v zoxide &>/dev/null; then
    # Suppress doctor warning — sheldon's zsh-defer loads plugins after our
    # init, which trips zoxide's order check. Functionality is unaffected.
    export _ZO_DOCTOR=0

    eval "$(zoxide init zsh)"

    alias cd="z"
    alias cdi="zi"

    if command -v eza &>/dev/null; then
        export _ZO_FZF_OPTS="--preview 'eza -al --tree --level 1 --group-directories-first \
            --header --no-user --no-time --no-filesize --no-permissions {2..}' \
            --preview-window right,50% --height 35% --reverse --ansi --with-nth 2.."
    fi
fi

# jq has no shell integration — it's a pure binary. mise installs it; presence
# is reported by `mise current` in 00-mise.zsh's pkg_doctor.

# Note: this file intentionally does NOT call init_package_template. It's
# shell config, not a package — no install/doctor/uninstall lifecycle.

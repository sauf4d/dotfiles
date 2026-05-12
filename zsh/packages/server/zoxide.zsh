#!/usr/bin/env zsh

PKG_NAME="zoxide"
PKG_DESC="A smarter cd command"

pkg_init() {
    # Suppress doctor warning — sheldon's zsh-defer loads plugins after our
    # init, which trips zoxide's order check. Functionality is unaffected.
    export _ZO_DOCTOR=0

    eval "$(zoxide init zsh)" || {
        _dotfiles_log_error "Failed to initialize zoxide"
        return 1
    }

    # Verify initialization
    typeset -f __zoxide_z >/dev/null || {
        _dotfiles_log_error "zoxide initialization incomplete"
        return 1
    }

    # z/zi aliases for navigation
    alias cd="z"
    alias cdi="zi"

    # fzf preview options for zoxide interactive mode (if eza is available)
    if command -v eza &>/dev/null; then
        export _ZO_FZF_OPTS="--preview 'eza -al --tree --level 1 --group-directories-first \
            --header --no-user --no-time --no-filesize --no-permissions {2..}' \
            --preview-window right,50% --height 35% --reverse --ansi --with-nth 2.."
    fi
}

init_package_template "$PKG_NAME"

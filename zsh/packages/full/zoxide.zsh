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

pkg_doctor() {
    local issues=0
    if command -v zoxide &>/dev/null; then
        local ver
        ver="$(zoxide --version 2>/dev/null | head -1)"
        _dotfiles_log_result "zoxide" "${ver:-installed}"
    else
        _dotfiles_log_result "zoxide" "NOT FOUND"
        ((issues++))
        return $issues
    fi

    local db_path="${_ZO_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zoxide}/db.zo"
    if [[ -f "$db_path" ]]; then
        _dotfiles_log_dim "database: $db_path"
    else
        _dotfiles_log_dim "database: not yet created (populates on first use)"
    fi

    return $issues
}

pkg_clean() {
    # zoxide database (~/.local/share/zoxide/db.zo) is accumulated navigation
    # history — it is user data, not a cache. Do not remove it.
    return 0
}

pkg_uninstall() {
    local pkg_mgr
    pkg_mgr="$(dotfiles_pkg_manager)"

    local uninstall_cmd=""
    case "$pkg_mgr" in
        brew)   uninstall_cmd="brew uninstall zoxide" ;;
        apt)    uninstall_cmd="sudo apt remove -y zoxide" ;;
        dnf)    uninstall_cmd="sudo dnf remove -y zoxide" ;;
        yum)    uninstall_cmd="sudo yum remove -y zoxide" ;;
        pacman) uninstall_cmd="sudo pacman -Rs --noconfirm zoxide" ;;
        zypper) uninstall_cmd="sudo zypper remove -y zoxide" ;;
        *)
            if ! command -v zoxide &>/dev/null; then
                return 0
            fi
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "Unknown package manager — cannot auto-uninstall zoxide" \
                "$(command -v zoxide 2>/dev/null || echo 'unknown')" \
                "Remove zoxide via your system package manager" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
            ;;
    esac

    if ! eval "$uninstall_cmd" 2>/dev/null; then
        [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
            "$uninstall_cmd failed" \
            "$(command -v zoxide 2>/dev/null || echo 'unknown')" \
            "run: $uninstall_cmd" \
            > "$_PKG_UNINSTALL_REPORT_FILE"
        return 1
    fi

    # Note: ~/.local/share/zoxide/db.zo is user navigation history — preserved.
    # To remove it manually: rm -rf ~/.local/share/zoxide/
    _dotfiles_log_detail "zoxide: navigation database preserved at ${_ZO_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/zoxide}/db.zo"
    _dotfiles_log_detail "        remove manually if desired: rm -rf ~/.local/share/zoxide/"

    return 0
}

init_package_template "$PKG_NAME"

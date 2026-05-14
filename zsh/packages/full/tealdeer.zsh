#!/usr/bin/env zsh

PKG_NAME="tealdeer"
PKG_DESC="A very fast implementation of tldr in Rust"
PKG_CMD="tldr"

pkg_post_install() {
    # Populate the cache on first install (tealdeer cache is a directory, not a file)
    command -v tldr &>/dev/null && tldr --update &>/dev/null
}

pkg_init() {
    # No alias: 'help' is a zsh built-in; shadowing it breaks built-in help.
    # Use 'tldr <command>' directly.
    :
}

pkg_doctor() {
    local issues=0
    if command -v tldr &>/dev/null; then
        local ver
        ver="$(tldr --version 2>/dev/null | head -1)"
        _dotfiles_log_result "tealdeer" "${ver:-installed}"
    else
        _dotfiles_log_result "tealdeer" "NOT FOUND (tldr binary missing)"
        ((issues++))
        return $issues
    fi

    # Check cache freshness — tealdeer cache dir varies by platform
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/tealdeer"
    if [[ -d "$cache_dir" ]]; then
        _dotfiles_log_dim "cache: $cache_dir"
    else
        _dotfiles_log_dim "cache: not populated — run: tldr --update"
        ((issues++))
    fi

    return $issues
}

pkg_clean() {
    local force="${DOTFILES_CLEAN_FORCE:-}"
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/tealdeer"

    if [[ -d "$cache_dir" ]]; then
        _dotfiles_log_detail "tealdeer: page cache at $cache_dir"
        if [[ "$force" == "--force" ]]; then
            command -v tldr &>/dev/null && tldr --clear-cache 2>/dev/null
            rm -rf "$cache_dir" 2>/dev/null
            _dotfiles_log_detail "tealdeer: cleared page cache"
        fi
    fi
    return 0
}

pkg_uninstall() {
    local pkg_mgr
    pkg_mgr="$(dotfiles_pkg_manager)"

    # Clear cache before removing binary
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/tealdeer"
    command -v tldr &>/dev/null && tldr --clear-cache 2>/dev/null
    rm -rf "$cache_dir" 2>/dev/null

    local uninstall_cmd=""
    case "$pkg_mgr" in
        brew)   uninstall_cmd="brew uninstall tealdeer" ;;
        apt)    uninstall_cmd="sudo apt remove -y tealdeer" ;;
        dnf)    uninstall_cmd="sudo dnf remove -y tealdeer" ;;
        yum)    uninstall_cmd="sudo yum remove -y tealdeer" ;;
        pacman) uninstall_cmd="sudo pacman -Rs --noconfirm tealdeer" ;;
        zypper) uninstall_cmd="sudo zypper remove -y tealdeer" ;;
        *)
            if ! command -v tldr &>/dev/null; then
                return 0
            fi
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "Unknown package manager — cannot auto-uninstall tealdeer" \
                "$(command -v tldr 2>/dev/null || echo 'unknown')" \
                "Remove tealdeer via your system package manager" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
            ;;
    esac

    if ! eval "$uninstall_cmd" 2>/dev/null; then
        [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
            "$uninstall_cmd failed" \
            "$(command -v tldr 2>/dev/null || echo 'unknown')" \
            "run: $uninstall_cmd" \
            > "$_PKG_UNINSTALL_REPORT_FILE"
        return 1
    fi
    return 0
}

init_package_template "$PKG_NAME"

#!/usr/bin/env zsh

PKG_NAME="ripgrep"
PKG_DESC="A line-oriented search tool that recursively searches directories"
PKG_CMD="rg"

pkg_init() {
    export RIPGREP_CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/ripgreprc"
}

pkg_doctor() {
    local issues=0
    if command -v rg &>/dev/null; then
        local ver
        ver="$(rg --version 2>/dev/null | head -1)"
        _dotfiles_log_result "ripgrep" "${ver:-installed}"
    else
        _dotfiles_log_result "ripgrep" "NOT FOUND"
        ((issues++))
    fi

    local config_path="${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/ripgreprc"
    if [[ -f "$config_path" ]]; then
        _dotfiles_log_dim "config: $config_path"
    else
        _dotfiles_log_dim "config: $config_path (not present — using defaults)"
    fi

    return $issues
}

pkg_clean() {
    # ripgrep has no runtime cache or state
    return 0
}

pkg_uninstall() {
    local pkg_mgr
    pkg_mgr="$(dotfiles_pkg_manager)"

    local uninstall_cmd=""
    case "$pkg_mgr" in
        brew)   uninstall_cmd="brew uninstall ripgrep" ;;
        apt)    uninstall_cmd="sudo apt remove -y ripgrep" ;;
        dnf)    uninstall_cmd="sudo dnf remove -y ripgrep" ;;
        yum)    uninstall_cmd="sudo yum remove -y ripgrep" ;;
        pacman) uninstall_cmd="sudo pacman -Rs --noconfirm ripgrep" ;;
        zypper) uninstall_cmd="sudo zypper remove -y ripgrep" ;;
        *)
            if ! command -v rg &>/dev/null; then
                return 0
            fi
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "Unknown package manager — cannot auto-uninstall ripgrep" \
                "$(command -v rg 2>/dev/null || echo 'unknown')" \
                "Remove ripgrep via your system package manager" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
            ;;
    esac

    if ! eval "$uninstall_cmd" 2>/dev/null; then
        [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
            "$uninstall_cmd failed" \
            "$(command -v rg 2>/dev/null || echo 'unknown')" \
            "run: $uninstall_cmd" \
            > "$_PKG_UNINSTALL_REPORT_FILE"
        return 1
    fi
    return 0
}

init_package_template "$PKG_NAME"

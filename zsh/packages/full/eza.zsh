#!/usr/bin/env zsh

PKG_NAME="eza"
PKG_DESC="A modern replacement for ls"

pkg_init() {
    alias ls="eza -g"
    alias ll="eza -lg"
    alias la="eza -lag"
    alias lt="eza --tree"
    alias lta="eza --tree -ag"
}

pkg_doctor() {
    local issues=0
    if command -v eza &>/dev/null; then
        local ver
        ver="$(eza --version 2>/dev/null | head -1)"
        _dotfiles_log_result "eza" "${ver:-installed}"
    else
        _dotfiles_log_result "eza" "NOT FOUND"
        ((issues++))
    fi
    return $issues
}

pkg_clean() {
    # eza has no runtime cache or state
    return 0
}

pkg_uninstall() {
    local pkg_mgr
    pkg_mgr="$(dotfiles_pkg_manager)"

    local uninstall_cmd=""
    case "$pkg_mgr" in
        brew)   uninstall_cmd="brew uninstall eza" ;;
        apt)    uninstall_cmd="sudo apt remove -y eza" ;;
        dnf)    uninstall_cmd="sudo dnf remove -y eza" ;;
        yum)    uninstall_cmd="sudo yum remove -y eza" ;;
        pacman) uninstall_cmd="sudo pacman -Rs --noconfirm eza" ;;
        zypper) uninstall_cmd="sudo zypper remove -y eza" ;;
        *)
            if ! command -v eza &>/dev/null; then
                return 0
            fi
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "Unknown package manager — cannot auto-uninstall eza" \
                "$(command -v eza 2>/dev/null || echo 'unknown')" \
                "Remove eza via your system package manager" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
            ;;
    esac

    if ! eval "$uninstall_cmd" 2>/dev/null; then
        [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
            "$uninstall_cmd failed" \
            "$(command -v eza 2>/dev/null || echo 'unknown')" \
            "run: $uninstall_cmd" \
            > "$_PKG_UNINSTALL_REPORT_FILE"
        return 1
    fi
    return 0
}

init_package_template "$PKG_NAME"

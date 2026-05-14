#!/usr/bin/env zsh

PKG_NAME="jq"
PKG_DESC="Lightweight command-line JSON processor"

# No pkg_init — jq is a plain binary, no shell hook needed.

pkg_doctor() {
    local issues=0
    if command -v jq &>/dev/null; then
        local ver
        ver="$(jq --version 2>/dev/null | head -1)"
        _dotfiles_log_result "jq" "${ver:-installed}"
    else
        _dotfiles_log_result "jq" "NOT FOUND"
        ((issues++))
    fi
    return $issues
}

pkg_clean() {
    # jq has no runtime cache or state
    return 0
}

pkg_uninstall() {
    local pkg_mgr
    pkg_mgr="$(dotfiles_pkg_manager)"

    local uninstall_cmd=""
    case "$pkg_mgr" in
        brew)   uninstall_cmd="brew uninstall jq" ;;
        apt)    uninstall_cmd="sudo apt remove -y jq" ;;
        dnf)    uninstall_cmd="sudo dnf remove -y jq" ;;
        yum)    uninstall_cmd="sudo yum remove -y jq" ;;
        pacman) uninstall_cmd="sudo pacman -Rs --noconfirm jq" ;;
        zypper) uninstall_cmd="sudo zypper remove -y jq" ;;
        *)
            if ! command -v jq &>/dev/null; then
                return 0
            fi
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "Unknown package manager — cannot auto-uninstall jq" \
                "$(command -v jq 2>/dev/null || echo 'unknown')" \
                "Remove jq via your system package manager" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
            ;;
    esac

    if ! eval "$uninstall_cmd" 2>/dev/null; then
        [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
            "$uninstall_cmd failed" \
            "$(command -v jq 2>/dev/null || echo 'unknown')" \
            "run: $uninstall_cmd" \
            > "$_PKG_UNINSTALL_REPORT_FILE"
        return 1
    fi
    return 0
}

init_package_template "$PKG_NAME"

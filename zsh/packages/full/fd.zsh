#!/usr/bin/env zsh

PKG_NAME="fd"
PKG_DESC="A simple, fast and user-friendly alternative to find"

pkg_pre_install() {
    # Ubuntu/Debian names the package 'fd-find' (binary: fdfind)
    if [[ "$(dotfiles_pkg_manager)" == "apt" ]]; then
        PKG_NAME="fd-find"
        PKG_CMD="fd"
    fi
}

pkg_post_install() {
    # Ubuntu/Debian names the binary 'fdfind' — create a 'fd' compat symlink
    _dotfiles_linux_compat_symlink "fdfind" "fd"
}

pkg_init() {
    export FD_OPTIONS="--follow --exclude .git --exclude node_modules"
}

pkg_doctor() {
    local issues=0
    local fd_bin
    fd_bin="$(command -v fd 2>/dev/null || command -v fdfind 2>/dev/null || true)"

    if [[ -n "$fd_bin" ]]; then
        local ver
        ver="$("$fd_bin" --version 2>/dev/null | head -1)"
        _dotfiles_log_result "fd" "${ver:-installed} ($fd_bin)"
    else
        _dotfiles_log_result "fd" "NOT FOUND"
        ((issues++))
    fi
    return $issues
}

pkg_clean() {
    # fd has no runtime cache or state
    return 0
}

pkg_uninstall() {
    local pkg_mgr
    pkg_mgr="$(dotfiles_pkg_manager)"

    local uninstall_cmd=""
    case "$pkg_mgr" in
        brew)   uninstall_cmd="brew uninstall fd" ;;
        apt)    uninstall_cmd="sudo apt remove -y fd-find" ;;
        dnf)    uninstall_cmd="sudo dnf remove -y fd-find" ;;
        yum)    uninstall_cmd="sudo yum remove -y fd-find" ;;
        pacman) uninstall_cmd="sudo pacman -Rs --noconfirm fd" ;;
        zypper) uninstall_cmd="sudo zypper remove -y fd" ;;
        *)
            if ! command -v fd &>/dev/null && ! command -v fdfind &>/dev/null; then
                return 0
            fi
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "Unknown package manager — cannot auto-uninstall fd" \
                "$(command -v fd 2>/dev/null || command -v fdfind 2>/dev/null || echo 'unknown')" \
                "Remove fd via your system package manager" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
            ;;
    esac

    if ! eval "$uninstall_cmd" 2>/dev/null; then
        [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
            "$uninstall_cmd failed" \
            "$(command -v fd 2>/dev/null || command -v fdfind 2>/dev/null || echo 'unknown')" \
            "run: $uninstall_cmd" \
            > "$_PKG_UNINSTALL_REPORT_FILE"
        return 1
    fi

    # Remove Linux compat symlink created by pkg_post_install
    local compat_link="$HOME/.local/bin/fd"
    [[ -L "$compat_link" ]] && rm -f "$compat_link" 2>/dev/null

    return 0
}

init_package_template "fd"

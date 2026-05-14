#!/usr/bin/env zsh

PKG_NAME="bat"
PKG_DESC="A cat clone with syntax highlighting and Git integration"

pkg_post_install() {
    # Ubuntu/Debian names the binary 'batcat' — create a 'bat' compat symlink
    _dotfiles_linux_compat_symlink "batcat" "bat"
}

pkg_init() {
    # Don't clobber a user's pre-existing MANPAGER choice.
    # Explicit return 0 — otherwise pkg_init inherits the failed [[ test ]]
    # exit code when MANPAGER is already set, which init_package_template
    # interprets as init failure.
    if [[ -z "${MANPAGER:-}" ]]; then
        export MANPAGER="sh -c 'col -bx | bat -l man -p'"
    fi
    return 0
}

pkg_doctor() {
    local issues=0
    local bat_bin
    bat_bin="$(command -v bat 2>/dev/null || command -v batcat 2>/dev/null || true)"

    if [[ -n "$bat_bin" ]]; then
        local ver
        ver="$("$bat_bin" --version 2>/dev/null | head -1)"
        _dotfiles_log_result "bat" "${ver:-installed} ($bat_bin)"
    else
        _dotfiles_log_result "bat" "NOT FOUND"
        ((issues++))
    fi
    return $issues
}

pkg_clean() {
    local force="${DOTFILES_CLEAN_FORCE:-}"
    local bat_bin
    bat_bin="$(command -v bat 2>/dev/null || command -v batcat 2>/dev/null || true)"

    [[ -z "$bat_bin" ]] && return 0

    local config_dir
    config_dir="$("$bat_bin" --config-dir 2>/dev/null || true)"
    local cache_dir="${config_dir}/cache"

    if [[ -d "$cache_dir" ]]; then
        _dotfiles_log_detail "bat: theme cache at $cache_dir"
        if [[ "$force" == "--force" ]]; then
            "$bat_bin" cache --clear 2>/dev/null || rm -rf "$cache_dir" 2>/dev/null
            _dotfiles_log_detail "bat: cleared theme cache"
        fi
    fi
    return 0
}

pkg_uninstall() {
    local os pkg_mgr
    os="$(dotfiles_os)"
    pkg_mgr="$(dotfiles_pkg_manager)"

    # Clear compiled theme cache before removing binary
    local bat_bin
    bat_bin="$(command -v bat 2>/dev/null || command -v batcat 2>/dev/null || true)"
    [[ -n "$bat_bin" ]] && "$bat_bin" cache --clear 2>/dev/null

    local uninstall_cmd=""
    case "$pkg_mgr" in
        brew)
            uninstall_cmd="brew uninstall bat" ;;
        apt)
            # Try 'bat' first (newer apt repos), fall back to 'batcat'
            if dpkg -l bat &>/dev/null 2>&1; then
                uninstall_cmd="sudo apt remove -y bat"
            else
                uninstall_cmd="sudo apt remove -y batcat"
            fi
            ;;
        dnf)    uninstall_cmd="sudo dnf remove -y bat" ;;
        yum)    uninstall_cmd="sudo yum remove -y bat" ;;
        pacman) uninstall_cmd="sudo pacman -Rs --noconfirm bat" ;;
        zypper) uninstall_cmd="sudo zypper remove -y bat" ;;
        *)
            if ! command -v bat &>/dev/null && ! command -v batcat &>/dev/null; then
                return 0
            fi
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "Unknown package manager — cannot auto-uninstall bat" \
                "$(command -v bat 2>/dev/null || command -v batcat 2>/dev/null || echo 'unknown')" \
                "Remove bat via your system package manager" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
            ;;
    esac

    if ! eval "$uninstall_cmd" 2>/dev/null; then
        [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
            "$uninstall_cmd failed" \
            "$(command -v bat 2>/dev/null || command -v batcat 2>/dev/null || echo 'unknown')" \
            "run: $uninstall_cmd" \
            > "$_PKG_UNINSTALL_REPORT_FILE"
        return 1
    fi

    # Remove Linux compat symlink
    local compat_link="$HOME/.local/bin/bat"
    [[ -L "$compat_link" ]] && rm -f "$compat_link" 2>/dev/null

    return 0
}

init_package_template "$PKG_NAME"

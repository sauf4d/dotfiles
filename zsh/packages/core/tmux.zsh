#!/usr/bin/env zsh

PKG_NAME="tmux"
PKG_DESC="Terminal multiplexer for managing multiple shell sessions"

pkg_post_install() {
    # Symlink tmux config
    create_symlink "${DOTFILES_ROOT}/tmux.conf" "$HOME/.tmux.conf"

    # Install TPM (tmux plugin manager) and plugins
    local tpm_dir="$HOME/.tmux/plugins/tpm"
    if [[ ! -d "$tpm_dir" ]]; then
        _dotfiles_log_info "Installing tmux plugin manager..."
        if command -v git &>/dev/null; then
            # Pinned to v3.1.0 — update tag+SHA together when bumping
            # Commit SHA verified 2026-04-03
            _dotfiles_safe_git_clone \
                "https://github.com/tmux-plugins/tpm" \
                "v3.1.0" \
                "7bdb7ca33c9cc6440a600202b50142f401b6fe21" \
                "$tpm_dir" && _dotfiles_log_success "TPM installed successfully"
        else
            _dotfiles_log_warning "git not found, cannot install TPM"
            return 1
        fi
    fi

    local tpm_install_script="$tpm_dir/bindings/install_plugins"
    if [[ -f "$tpm_install_script" ]]; then
        _dotfiles_log_info "Installing tmux plugins..."
        "$tpm_install_script" &>/dev/null
    fi
}

pkg_doctor() {
    local issues=0

    if command -v tmux &>/dev/null; then
        local ver
        ver="$(tmux -V 2>/dev/null)"
        _dotfiles_log_result "tmux" "${ver:-installed}"
    else
        _dotfiles_log_result "tmux" "NOT FOUND"
        ((issues++))
    fi

    local conf_target
    conf_target="$(readlink -f "$HOME/.tmux.conf" 2>/dev/null || true)"
    if [[ -f "$HOME/.tmux.conf" ]]; then
        _dotfiles_log_dim "config: $HOME/.tmux.conf${conf_target:+ -> $conf_target}"
    else
        _dotfiles_log_dim "config: ~/.tmux.conf missing"
        ((issues++))
    fi

    local tpm_dir="$HOME/.tmux/plugins/tpm"
    if [[ -d "$tpm_dir" ]]; then
        _dotfiles_log_dim "TPM: $tpm_dir"
    else
        _dotfiles_log_dim "TPM: not installed at $tpm_dir"
    fi

    return $issues
}

pkg_clean() {
    local plugins_dir="$HOME/.tmux/plugins"
    local resurrect_dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
    local force="${DOTFILES_CLEAN_FORCE:-}"

    local found=0

    # Report non-TPM plugin dirs (these are runtime downloads, not source files)
    if [[ -d "$plugins_dir" ]]; then
        local d
        for d in "$plugins_dir"/*/; do
            [[ "$(basename "$d")" == "tpm" ]] && continue
            ((found++))
            _dotfiles_log_detail "tmux: plugin dir: $d"
        done
    fi

    # Tmux resurrection sessions
    if [[ -d "$resurrect_dir" ]]; then
        local count
        count="$(find "$resurrect_dir" -maxdepth 1 -name '*.txt' 2>/dev/null | wc -l | tr -d ' ')"
        if [[ "$count" -gt 0 ]]; then
            ((found++))
            _dotfiles_log_detail "tmux: resurrect sessions: $count file(s) in $resurrect_dir"
        fi
    fi

    [[ $found -eq 0 ]] && return 0

    if [[ "$force" == "--force" ]]; then
        if [[ -d "$plugins_dir" ]]; then
            local d
            for d in "$plugins_dir"/*/; do
                [[ "$(basename "$d")" == "tpm" ]] && continue
                rm -rf "$d" 2>/dev/null
            done
        fi
        rm -rf "$resurrect_dir" 2>/dev/null
        _dotfiles_log_detail "tmux: removed plugin downloads and resurrect sessions"
    fi
    return 0
}

pkg_uninstall() {
    local os pkg_mgr
    os="$(dotfiles_os)"
    pkg_mgr="$(dotfiles_pkg_manager)"

    # Remove tmux config symlink only if it points into the dotfiles repo
    local conf="$HOME/.tmux.conf"
    if [[ -L "$conf" ]]; then
        local target
        target="$(readlink "$conf" 2>/dev/null || true)"
        [[ "$target" == "${DOTFILES_ROOT:-$HOME/.dotfiles}"* ]] && rm -f "$conf" 2>/dev/null
    fi

    # Remove TPM and all plugins (runtime state, not the binary)
    rm -rf "$HOME/.tmux/plugins" 2>/dev/null

    local uninstall_cmd=""
    case "$pkg_mgr" in
        brew)   uninstall_cmd="brew uninstall tmux" ;;
        apt)    uninstall_cmd="sudo apt remove -y tmux" ;;
        dnf)    uninstall_cmd="sudo dnf remove -y tmux" ;;
        yum)    uninstall_cmd="sudo yum remove -y tmux" ;;
        pacman) uninstall_cmd="sudo pacman -Rs --noconfirm tmux" ;;
        zypper) uninstall_cmd="sudo zypper remove -y tmux" ;;
        *)
            if ! command -v tmux &>/dev/null; then
                return 0  # already gone
            fi
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "Unknown package manager — cannot auto-uninstall tmux" \
                "$(command -v tmux 2>/dev/null || echo 'unknown')" \
                "Remove tmux via your system package manager" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
            ;;
    esac

    if ! eval "$uninstall_cmd" 2>/dev/null; then
        [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
            "$uninstall_cmd failed" \
            "$(command -v tmux 2>/dev/null || echo 'unknown')" \
            "run: $uninstall_cmd" \
            > "$_PKG_UNINSTALL_REPORT_FILE"
        return 1
    fi
    return 0
}

init_package_template "$PKG_NAME"

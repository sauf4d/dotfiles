#!/usr/bin/env zsh

PKG_NAME="sheldon"
PKG_DESC="A fast and configurable shell plugin manager"

pkg_install() {
    if [[ "$(dotfiles_os)" == "linux" ]] && command -v curl &>/dev/null; then
        _dotfiles_log_info "Installing $PKG_NAME via verified curl installer..."
        # SHA256 of crate.sh — verified 2026-04-03
        # If install fails with checksum mismatch, fetch the new hash:
        #   curl --proto '=https' --tlsv1.2 -fsSL https://rossmacarthur.github.io/install/crate.sh | shasum -a 256
        local installer_sha256="2f456def6ec8e1c11c5fc416f8653e31189682b2a823cc18dbcd33188f2e9b65"
        _dotfiles_safe_sudo_run_installer \
            "https://rossmacarthur.github.io/install/crate.sh" \
            "$installer_sha256" \
            -s -- --repo rossmacarthur/sheldon --to "/usr/local/bin"
    else
        _dotfiles_install_package "$PKG_NAME" "$PKG_DESC" || return 1
    fi
}

pkg_post_install() {
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/sheldon"
    ensure_directory "$config_dir"
    copy_if_missing "${DOTFILES_ROOT}/config/sheldon/plugins.toml" "${config_dir}/plugins.toml"
    sheldon lock --update &>/dev/null || _dotfiles_log_warning "Failed to update $PKG_NAME plugins."
}

pkg_init() {
    # Assert sheldon resolves to a real binary before eval-ing its output
    local sheldon_bin
    sheldon_bin="$(command -v sheldon 2>/dev/null)" || {
        _dotfiles_log_error "sheldon not found in PATH"
        return 1
    }
    local sheldon_output
    sheldon_output="$("$sheldon_bin" source)" || {
        _dotfiles_log_error "sheldon source failed — plugins may not load correctly"
        return 1
    }
    eval "$sheldon_output"

    # Initialize completions AFTER sheldon so zsh-completions is fully in fpath.
    # 30-completion.zsh sets zstyle only; compinit must run here.
    autoload -Uz compinit
    if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
        compinit        # full rebuild (at most once per day)
    else
        # compinit -C skips fpath ownership audit for performance.
        # Risk: attacker-writable fpath dir could inject completions.
        # Acceptable on single-user machines; remove -C on shared systems.
        compinit -C
    fi
}

pkg_doctor() {
    local issues=0
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/sheldon"

    if command -v sheldon &>/dev/null; then
        local ver
        ver="$(sheldon --version 2>/dev/null | head -1)"
        _dotfiles_log_result "sheldon" "${ver:-installed}"
    else
        _dotfiles_log_result "sheldon" "NOT FOUND"
        ((issues++))
    fi

    if [[ -f "${config_dir}/plugins.toml" ]]; then
        _dotfiles_log_dim "config: ${config_dir}/plugins.toml"
    else
        _dotfiles_log_result "sheldon" "plugins.toml missing at ${config_dir}"
        ((issues++))
    fi

    return $issues
}

pkg_clean() {
    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/sheldon"
    local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/sheldon"
    local lock_file="${config_dir}/sheldon.lock"
    local force="${DOTFILES_CLEAN_FORCE:-}"

    local found=0
    [[ -f "$lock_file" ]] && ((found++)) && _dotfiles_log_detail "sheldon: lock file: $lock_file"
    if [[ -d "$data_dir" ]]; then
        ((found++))
        _dotfiles_log_detail "sheldon: plugin cache: $data_dir"
    fi

    [[ $found -eq 0 ]] && return 0

    if [[ "$force" == "--force" ]]; then
        rm -f "$lock_file" 2>/dev/null
        rm -rf "$data_dir" 2>/dev/null
        _dotfiles_log_detail "sheldon: removed lock file and plugin cache"
    fi
    return 0
}

pkg_uninstall() {
    local os pkg_mgr
    os="$(dotfiles_os)"
    pkg_mgr="$(dotfiles_pkg_manager)"

    local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/sheldon"
    local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/sheldon"

    # Remove plugin cache and config (plugins.toml symlink removed by symlink sweep)
    rm -rf "$data_dir" 2>/dev/null
    rm -rf "$config_dir" 2>/dev/null

    # Uninstall binary — mirror the install path
    if [[ "$os" == "macos" && "$pkg_mgr" == "brew" ]]; then
        if ! brew uninstall sheldon 2>/dev/null; then
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "brew uninstall sheldon failed" \
                "$(command -v sheldon 2>/dev/null || echo 'unknown')" \
                "run: brew uninstall sheldon" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
        fi
    elif [[ "$os" == "linux" ]]; then
        local sheldon_bin="/usr/local/bin/sheldon"
        if [[ -f "$sheldon_bin" ]]; then
            if ! sudo rm -f "$sheldon_bin" 2>/dev/null; then
                [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                    "Failed to remove sheldon binary" \
                    "$sheldon_bin" \
                    "run: sudo rm -f $sheldon_bin" \
                    > "$_PKG_UNINSTALL_REPORT_FILE"
                return 1
            fi
        fi
    fi

    # Idempotency: not installed is fine
    return 0
}

init_package_template "$PKG_NAME"

#!/usr/bin/env zsh

PKG_NAME="vfox"
PKG_DESC="Cross-platform SDK version manager (Unix/macOS/Windows native)"

# SDK manifest lives in config/vfox/sdks (symlinked to ~/.config/vfox/sdks).
# Edit that file to change managed runtimes — keeps SDK versions in sync across
# machines via the dotfiles repo.

pkg_install() {
    local os pkg_mgr
    os="$(dotfiles_os)"
    pkg_mgr="$(dotfiles_pkg_manager)"

    if [[ "$os" == "macos" && "$pkg_mgr" == "brew" ]]; then
        brew install vfox || return 1
    elif [[ "$pkg_mgr" == "apt" ]]; then
        # vfox distributes via Fury apt repo. Install with GPG verification.
        sudo install -dm 755 /etc/apt/keyrings
        curl --proto '=https' --tlsv1.2 -fsSL https://apt.fury.io/versionfox/gpg.key \
            | sudo gpg --dearmor -o /etc/apt/keyrings/vfox.gpg
        echo "deb [signed-by=/etc/apt/keyrings/vfox.gpg] https://apt.fury.io/versionfox/ /" \
            | sudo tee /etc/apt/sources.list.d/versionfox.list >/dev/null
        sudo apt-get update -qq && sudo apt-get install -y vfox || return 1
    else
        _dotfiles_log_warning "vfox: unsupported platform — install manually from https://vfox.dev"
        return 1
    fi
}

pkg_post_install() {
    command -v vfox &>/dev/null || return 0

    local sdks_file="${XDG_CONFIG_HOME:-$HOME/.config}/vfox/sdks"
    if [[ ! -f "$sdks_file" ]]; then
        _dotfiles_log_warning "vfox: SDK manifest not found at $sdks_file (skipping provisioning)"
        return 0
    fi

    local line plugin version
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip blank lines and comments
        [[ -z "$line" || "$line" == \#* ]] && continue
        # Trim inline whitespace
        line="${line## }"; line="${line%% }"
        # Require plugin@version format
        if [[ "$line" != *@* ]]; then
            _dotfiles_log_warning "vfox: malformed manifest line (skipping): $line"
            continue
        fi
        plugin="${line%@*}"
        version="${line#*@}"

        if ! vfox info "$plugin" &>/dev/null; then
            _dotfiles_log_info "vfox: adding plugin $plugin"
            vfox add "$plugin" 2>/dev/null || {
                _dotfiles_log_warning "vfox: failed to add plugin $plugin (skipping)"
                continue
            }
        fi

        _dotfiles_log_info "vfox: installing $plugin@$version"
        vfox install "$plugin@$version" 2>/dev/null || {
            _dotfiles_log_warning "vfox: install failed for $plugin@$version (skipping)"
            continue
        }

        # `vfox use -g` requires an active shell hook. The install flow runs
        # non-interactively, so spawn an interactive zsh that auto-activates vfox.
        zsh -ic "vfox use -g $plugin@$version" &>/dev/null || \
            _dotfiles_log_warning "vfox: could not set $plugin@$version as global"
    done < "$sdks_file"
}

pkg_init() {
    [[ "${_DOTFILES_VFOX_LOADED:-}" == "1" ]] && return 0

    # vfox activate registers a precmd hook that runs `vfox env -s zsh` to refresh
    # PATH per directory. Unlike mise, vfox snapshots and re-exports PATH at source
    # time, so SDK paths are present immediately (no shims-first hack needed).
    command -v vfox &>/dev/null && eval "$(vfox activate zsh)"

    _DOTFILES_VFOX_LOADED="1"   # NOT exported — must reset on `exec zsh`
}

pkg_doctor() {
    local issues=0

    if ! command -v vfox &>/dev/null; then
        _dotfiles_log_result "vfox" "NOT FOUND"
        ((issues++))
        return $issues
    fi

    local ver
    ver="$(vfox --version 2>/dev/null | head -1)"
    _dotfiles_log_result "vfox" "${ver:-installed}"

    local sdks_file="${XDG_CONFIG_HOME:-$HOME/.config}/vfox/sdks"
    if [[ -f "$sdks_file" ]]; then
        _dotfiles_log_dim "SDK manifest: $sdks_file"
    else
        _dotfiles_log_dim "SDK manifest: missing at $sdks_file"
        ((issues++))
    fi

    # List installed plugins and their current versions
    local plugins_output
    plugins_output="$(vfox list 2>/dev/null || true)"
    if [[ -n "$plugins_output" ]]; then
        _dotfiles_log_dim "installed SDKs:"
        while IFS= read -r line; do
            _dotfiles_log_dim "  $line"
        done <<< "$plugins_output"
    else
        _dotfiles_log_dim "no SDKs currently installed"
    fi

    return $issues
}

pkg_clean() {
    local force="${DOTFILES_CLEAN_FORCE:-}"
    local cache_dir="${HOME}/.version-fox/cache"

    # vfox SDK download cache
    if [[ -d "$cache_dir" ]]; then
        _dotfiles_log_detail "vfox: SDK download cache at $cache_dir"
        if [[ "$force" == "--force" ]]; then
            rm -rf "$cache_dir" 2>/dev/null
            _dotfiles_log_detail "vfox: removed SDK download cache"
        fi
    fi

    # mise leftover hint (migrated from hardcoded clean_dotfiles block)
    local mise_data="${HOME}/.local/share/mise"
    local mise_config="${HOME}/.config/mise"
    local has_mise=false
    [[ -d "$mise_data" || -d "$mise_config" ]] && has_mise=true

    if $has_mise; then
        _dotfiles_log_detail "vfox: mise leftovers detected"
        [[ -d "$mise_data" ]] && _dotfiles_log_detail "  $mise_data"
        [[ -d "$mise_config" ]] && _dotfiles_log_detail "  $mise_config"
        if [[ "$force" == "--force" ]]; then
            rm -rf "$mise_data" 2>/dev/null
            rm -rf "$mise_config" 2>/dev/null
            _dotfiles_log_detail "vfox: removed mise leftover directories"
        else
            _dotfiles_log_detail "  (pass --force to remove)"
        fi
    fi

    return 0
}

pkg_uninstall() {
    local os pkg_mgr
    os="$(dotfiles_os)"
    pkg_mgr="$(dotfiles_pkg_manager)"

    # Deactivate all SDKs before removing vfox itself
    if command -v vfox &>/dev/null; then
        vfox remove --all 2>/dev/null || true
    fi

    # Remove vfox runtime state; the config/vfox/sdks symlink is handled by
    # the symlink sweep in uninstall_dotfiles — do not remove the parent dir blindly
    rm -rf "${HOME}/.version-fox" 2>/dev/null

    # Remove vfox config dir only if the sdks symlink is already gone (or not dotfiles-managed)
    local vfox_config="${XDG_CONFIG_HOME:-$HOME/.config}/vfox"
    local sdks_link="$vfox_config/sdks"
    if [[ -L "$sdks_link" ]]; then
        # Symlink sweep hasn't run yet; remove just the non-symlink contents
        find "$vfox_config" -mindepth 1 -not -name "sdks" -delete 2>/dev/null || true
    else
        rm -rf "$vfox_config" 2>/dev/null
    fi

    # Uninstall binary
    if [[ "$os" == "macos" && "$pkg_mgr" == "brew" ]]; then
        if ! brew uninstall vfox 2>/dev/null; then
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "brew uninstall vfox failed" \
                "$(command -v vfox 2>/dev/null || echo 'unknown'); ~/.version-fox may still exist" \
                "run: brew uninstall vfox && rm -rf ~/.version-fox" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
        fi
    elif [[ "$pkg_mgr" == "apt" ]]; then
        if ! sudo apt remove -y vfox 2>/dev/null; then
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "apt remove vfox failed" \
                "$(command -v vfox 2>/dev/null || echo 'unknown')" \
                "run: sudo apt remove -y vfox" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
        fi
        # Remove the Fury apt source and keyring added during pkg_install
        sudo rm -f /etc/apt/sources.list.d/versionfox.list 2>/dev/null
        sudo rm -f /etc/apt/keyrings/vfox.gpg 2>/dev/null
        sudo apt-get update -qq 2>/dev/null || true
    else
        if command -v vfox &>/dev/null; then
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "Unknown package manager — cannot auto-uninstall vfox" \
                "$(command -v vfox 2>/dev/null || echo 'unknown')" \
                "Remove vfox via your system package manager or from https://vfox.dev" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
        fi
    fi

    return 0
}

init_package_template "$PKG_NAME"

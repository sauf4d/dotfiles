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

    # All install paths below follow the official vfox guide:
    # https://vfox.lhan.me/guides/quick-install.html
    # The apt/yum branches use `trusted=yes` / `gpgcheck=0` per upstream —
    # a deliberate simplicity-over-signature-verification tradeoff. If you
    # want GPG verification, install vfox manually with the upstream key.

    if [[ "$os" == "macos" && "$pkg_mgr" == "brew" ]]; then
        brew install vfox || return 1

    elif [[ "$pkg_mgr" == "apt" ]]; then
        echo "deb [trusted=yes lang=none] https://apt.fury.io/versionfox/ /" \
            | sudo tee /etc/apt/sources.list.d/versionfox.list >/dev/null
        sudo apt-get update -qq && sudo apt-get install -y vfox || return 1

    elif [[ "$pkg_mgr" == "yum" || "$pkg_mgr" == "dnf" ]]; then
        sudo tee /etc/yum.repos.d/versionfox.repo >/dev/null <<'EOF'
[vfox]
name=VersionFox Repo
baseurl=https://yum.fury.io/versionfox/
enabled=1
gpgcheck=0
EOF
        sudo "$pkg_mgr" install -y vfox || return 1

    else
        # Fallback: upstream curl|bash installer (matches official guide).
        _dotfiles_log_info "vfox: using upstream installer (pkg_mgr=$pkg_mgr)"
        curl -sSL https://raw.githubusercontent.com/version-fox/vfox/main/install.sh | bash || return 1
    fi
}

pkg_post_install() {
    # SDK plugin installation is intentionally manual — run `vfox add <plugin>`
    # and `vfox install <plugin>@<version>` yourself to manage runtimes.
    # This hook only verifies the vfox binary is present after installation.
    if ! command -v vfox &>/dev/null; then
        _dotfiles_log_warning "vfox: binary not found after install"
        return 1
    fi
    return 0
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

    # Uninstall binary — branches mirror pkg_install
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
        if ! sudo apt-get remove -y vfox 2>/dev/null; then
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "apt-get remove vfox failed" \
                "$(command -v vfox 2>/dev/null || echo 'unknown')" \
                "run: sudo apt-get remove -y vfox" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
        fi
        # Remove Fury apt source list. The /etc/apt/keyrings/vfox.gpg path is
        # legacy from the pre-v2 GPG-keyring install — clean it up if present
        # so machines upgrading from older dotfiles don't leak stale state.
        sudo rm -f /etc/apt/sources.list.d/versionfox.list 2>/dev/null
        sudo rm -f /etc/apt/keyrings/vfox.gpg 2>/dev/null
        sudo apt-get update -qq 2>/dev/null || true

    elif [[ "$pkg_mgr" == "yum" || "$pkg_mgr" == "dnf" ]]; then
        if ! sudo "$pkg_mgr" remove -y vfox 2>/dev/null; then
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "$pkg_mgr remove vfox failed" \
                "$(command -v vfox 2>/dev/null || echo 'unknown')" \
                "run: sudo $pkg_mgr remove -y vfox" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
        fi
        sudo rm -f /etc/yum.repos.d/versionfox.repo 2>/dev/null

    else
        # Fallback installer path — binary was dropped by curl|bash. Locate it
        # via PATH and remove. If not on PATH, assume already removed (idempotent).
        local vfox_bin
        vfox_bin="$(command -v vfox 2>/dev/null)"
        if [[ -n "$vfox_bin" ]]; then
            if ! sudo rm -f "$vfox_bin" 2>/dev/null; then
                [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                    "Failed to remove vfox binary at $vfox_bin" \
                    "$vfox_bin" \
                    "run: sudo rm -f $vfox_bin" \
                    > "$_PKG_UNINSTALL_REPORT_FILE"
                return 1
            fi
        fi
    fi

    return 0
}

init_package_template "$PKG_NAME"

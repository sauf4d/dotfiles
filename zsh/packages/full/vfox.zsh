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

init_package_template "$PKG_NAME"

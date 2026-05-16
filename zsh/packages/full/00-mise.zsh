#!/usr/bin/env zsh

# 00- prefix forces alphabetical first-load. Every other tool in this
# profile (bat, eza, fd, fzf, jq, ripgrep, zoxide) is installed AND made
# discoverable by mise — they need mise's PATH active before their own
# `command -v` checks run. Don't rename this file.

PKG_NAME="mise"
PKG_DESC="Polyglot tool & SDK version manager (replaces vfox + per-tool apt/brew)"

# Tool manifest lives in config/mise/config.toml (symlinked to
# ~/.config/mise/config.toml). Edit that file to add/remove tools — runs
# transparently on the next `dotfiles install` via pkg_post_install.

pkg_install() {
    local os pkg_mgr
    os="$(dotfiles_os)"
    pkg_mgr="$(dotfiles_pkg_manager)"

    # All paths follow the official install guide: https://mise.jdx.dev/installing-mise.html
    if [[ "$os" == "macos" && "$pkg_mgr" == "brew" ]]; then
        brew install mise || return 1

    elif [[ "$pkg_mgr" == "apt" ]]; then
        # Official apt repo with signed keyring.
        sudo install -dm 755 /etc/apt/keyrings
        wget -qO - https://mise.jdx.dev/gpg-key.pub \
            | sudo gpg --dearmor -o /etc/apt/keyrings/mise-archive-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=amd64] https://mise.jdx.dev/deb stable main" \
            | sudo tee /etc/apt/sources.list.d/mise.list >/dev/null
        sudo apt-get update -qq && sudo apt-get install -y mise || return 1

    elif [[ "$pkg_mgr" == "dnf" || "$pkg_mgr" == "yum" ]]; then
        sudo tee /etc/yum.repos.d/mise.repo >/dev/null <<'EOF'
[mise]
name=Mise
baseurl=https://mise.jdx.dev/rpm
enabled=1
gpgcheck=1
gpgkey=https://mise.jdx.dev/gpg-key.pub
EOF
        sudo "$pkg_mgr" install -y mise || return 1

    elif [[ "$pkg_mgr" == "pacman" ]]; then
        sudo pacman -S --noconfirm mise || return 1

    else
        # Universal fallback: upstream curl|bash installer drops to ~/.local/bin.
        _dotfiles_log_info "mise: using upstream installer (pkg_mgr=$pkg_mgr)"
        curl -fsSL https://mise.run | sh || return 1
        # Make ~/.local/bin discoverable for the rest of this run.
        export PATH="$HOME/.local/bin:$PATH"
    fi
}

pkg_post_install() {
    if ! command -v mise &>/dev/null; then
        _dotfiles_log_warning "mise: binary not found after install"
        return 1
    fi

    # Materialize every tool in config/mise/config.toml. Idempotent — mise
    # skips tools whose pinned version is already installed.
    _dotfiles_log_debug "mise: installing tools from manifest"
    if ! mise install --yes 2>&1 | while IFS= read -r line; do
        _dotfiles_log_debug "mise: $line"
    done; then
        _dotfiles_log_warning "mise install reported failures — run 'mise doctor' for details"
    fi
    return 0
}

pkg_init() {
    [[ "${_DOTFILES_MISE_LOADED:-}" == "1" ]] && return 0

    # `mise activate zsh` registers a precmd hook that re-evaluates PATH
    # per-directory. Tools installed by mise show up in PATH immediately.
    command -v mise &>/dev/null && eval "$(mise activate zsh)"

    _DOTFILES_MISE_LOADED="1"   # NOT exported — must reset on `exec zsh`
}

pkg_doctor() {
    local issues=0

    if ! command -v mise &>/dev/null; then
        _dotfiles_log_result "mise" "NOT FOUND"
        ((issues++))
        return $issues
    fi

    local ver
    ver="$(mise --version 2>/dev/null | head -1)"
    _dotfiles_log_result "mise" "${ver:-installed}"

    local manifest="${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml"
    if [[ -f "$manifest" ]]; then
        _dotfiles_log_dim "manifest: $manifest"
    else
        _dotfiles_log_dim "manifest: missing at $manifest"
        ((issues++))
    fi

    # Surface currently-installed tools + active versions.
    local current
    current="$(mise current 2>/dev/null || true)"
    if [[ -n "$current" ]]; then
        _dotfiles_log_dim "active tools:"
        while IFS= read -r line; do
            _dotfiles_log_dim "  $line"
        done <<< "$current"
    fi

    return $issues
}

pkg_clean() {
    local force="${DOTFILES_CLEAN_FORCE:-}"

    # mise download cache
    local cache_dir="${HOME}/.cache/mise"
    if [[ -d "$cache_dir" ]]; then
        _dotfiles_log_detail "mise: download cache at $cache_dir"
        if [[ "$force" == "--force" ]]; then
            rm -rf "$cache_dir" 2>/dev/null
            _dotfiles_log_detail "mise: removed download cache"
        fi
    fi

    # vfox leftover hint (inverse of the migration we just performed)
    local vfox_data="${HOME}/.version-fox"
    local vfox_config="${HOME}/.config/vfox"
    if [[ -d "$vfox_data" || -d "$vfox_config" ]]; then
        _dotfiles_log_detail "mise: vfox leftovers detected"
        [[ -d "$vfox_data" ]]   && _dotfiles_log_detail "  $vfox_data"
        [[ -d "$vfox_config" ]] && _dotfiles_log_detail "  $vfox_config"
        if [[ "$force" == "--force" ]]; then
            rm -rf "$vfox_data" "$vfox_config" 2>/dev/null
            _dotfiles_log_detail "mise: removed vfox leftover directories"
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

    # Remove all mise-managed tools first.
    if command -v mise &>/dev/null; then
        mise uninstall --all 2>/dev/null || true
    fi

    # Wipe mise runtime state. The config.toml symlink is handled by the
    # symlink sweep in uninstall_dotfiles — don't nuke the parent dir blindly.
    rm -rf "${HOME}/.local/share/mise" 2>/dev/null
    rm -rf "${HOME}/.cache/mise" 2>/dev/null

    local mise_config="${XDG_CONFIG_HOME:-$HOME/.config}/mise"
    local manifest_link="$mise_config/config.toml"
    if [[ -L "$manifest_link" ]]; then
        # Symlink sweep hasn't run yet — leave the link, clear siblings only.
        find "$mise_config" -mindepth 1 -not -name "config.toml" -delete 2>/dev/null || true
    else
        rm -rf "$mise_config" 2>/dev/null
    fi

    # Uninstall the binary itself — branches mirror pkg_install.
    if [[ "$os" == "macos" && "$pkg_mgr" == "brew" ]]; then
        if ! brew uninstall mise 2>/dev/null; then
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "brew uninstall mise failed" \
                "$(command -v mise 2>/dev/null || echo 'unknown')" \
                "run: brew uninstall mise" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
        fi

    elif [[ "$pkg_mgr" == "apt" ]]; then
        sudo apt-get remove -y mise 2>/dev/null || true
        sudo rm -f /etc/apt/sources.list.d/mise.list 2>/dev/null
        sudo rm -f /etc/apt/keyrings/mise-archive-keyring.gpg 2>/dev/null
        sudo apt-get update -qq 2>/dev/null || true

    elif [[ "$pkg_mgr" == "dnf" || "$pkg_mgr" == "yum" ]]; then
        sudo "$pkg_mgr" remove -y mise 2>/dev/null || true
        sudo rm -f /etc/yum.repos.d/mise.repo 2>/dev/null

    elif [[ "$pkg_mgr" == "pacman" ]]; then
        sudo pacman -Rs --noconfirm mise 2>/dev/null || true

    else
        # Curl-installer fallback path.
        local mise_bin
        mise_bin="$(command -v mise 2>/dev/null)"
        if [[ -n "$mise_bin" ]]; then
            if ! rm -f "$mise_bin" 2>/dev/null && ! sudo rm -f "$mise_bin" 2>/dev/null; then
                [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                    "Failed to remove mise binary at $mise_bin" \
                    "$mise_bin" \
                    "run: sudo rm -f $mise_bin" \
                    > "$_PKG_UNINSTALL_REPORT_FILE"
                return 1
            fi
        fi
    fi

    return 0
}

init_package_template "$PKG_NAME"

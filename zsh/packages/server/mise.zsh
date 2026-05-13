#!/usr/bin/env zsh

PKG_NAME="mise"
PKG_DESC="Universal version manager for Node.js, Python, Go, Ruby, and more"

pkg_install() {
    local os="$(dotfiles_os)"
    local pkg_mgr="$(dotfiles_pkg_manager)"

    if [[ "$os" == "macos" ]] && [[ "$pkg_mgr" == "brew" ]]; then
        brew install mise || return 1
    elif [[ "$pkg_mgr" == "apt" ]]; then
        sudo install -dm 755 /etc/apt/keyrings
        curl --proto '=https' --tlsv1.2 -fsSL https://mise.jdx.dev/gpg-key.pub \
            | sudo gpg --dearmor -o /etc/apt/keyrings/mise-archive-keyring.gpg
        local arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
        echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=${arch}] https://mise.jdx.dev/deb stable main" \
            | sudo tee /etc/apt/sources.list.d/mise.list >/dev/null
        sudo apt-get update -qq && sudo apt-get install -y mise || return 1
    else
        curl --proto '=https' --tlsv1.2 -fsSL https://mise.run | sh || return 1
    fi
}

pkg_post_install() {
    # Install tools declared in ~/.config/mise/config.toml on first install.
    # Best-effort: don't fail the whole install flow if a single tool plugin breaks.
    command -v mise &>/dev/null || return 0
    mise install -y 2>/dev/null || true
}

pkg_init() {
    [[ "${_DOTFILES_MISE_LOADED:-}" == "1" ]] && return 0

    # Use shims for PATH management — works in interactive shells, scripts,
    # cron jobs, and non-interactive environments without hook overhead.
    local shims_dir="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims"
    if [[ -d "$shims_dir" && ":$PATH:" != *":$shims_dir:"* ]]; then
        export PATH="$shims_dir:$PATH"
    fi

    export _DOTFILES_MISE_LOADED="1"
}

init_package_template "$PKG_NAME"

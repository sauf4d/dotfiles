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

init_package_template "$PKG_NAME"

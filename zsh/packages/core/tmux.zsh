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

init_package_template "$PKG_NAME"

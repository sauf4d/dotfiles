#!/usr/bin/env zsh

PKG_NAME="fd"
PKG_DESC="A simple, fast and user-friendly alternative to find"

pkg_pre_install() {
    # Ubuntu/Debian names the package 'fd-find' (binary: fdfind)
    if [[ "$(dotfiles_pkg_manager)" == "apt" ]]; then
        PKG_NAME="fd-find"
        PKG_CMD="fd"
    fi
}

pkg_post_install() {
    # Ubuntu/Debian names the binary 'fdfind' — create a 'fd' compat symlink
    _dotfiles_linux_compat_symlink "fdfind" "fd"
}

pkg_init() {
    export FD_OPTIONS="--follow --exclude .git --exclude node_modules"
}

init_package_template "fd"

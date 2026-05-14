#!/usr/bin/env zsh

PKG_NAME="tealdeer"
PKG_DESC="A very fast implementation of tldr in Rust"
PKG_CMD="tldr"

pkg_post_install() {
    # Populate the cache on first install (tealdeer cache is a directory, not a file)
    command -v tldr &>/dev/null && tldr --update &>/dev/null
}

pkg_init() {
    # No alias: 'help' is a zsh built-in; shadowing it breaks built-in help.
    # Use 'tldr <command>' directly.
    :
}

init_package_template "$PKG_NAME"

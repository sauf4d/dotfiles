#!/usr/bin/env zsh

PKG_NAME="ripgrep"
PKG_DESC="A line-oriented search tool that recursively searches directories"
PKG_CMD="rg"

pkg_init() {
    export RIPGREP_CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/ripgreprc"
}

init_package_template "$PKG_NAME"

#!/usr/bin/env zsh

PKG_NAME="eza"
PKG_DESC="A modern replacement for ls"

pkg_init() {
    alias ls="eza -g"
    alias ll="eza -lg"
    alias la="eza -lag"
    alias lt="eza --tree"
    alias lta="eza --tree -ag"
}

init_package_template "$PKG_NAME"

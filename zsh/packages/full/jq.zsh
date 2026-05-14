#!/usr/bin/env zsh

PKG_NAME="jq"
PKG_DESC="Lightweight command-line JSON processor"

# No pkg_init — jq is a plain binary, no shell hook needed.

init_package_template "$PKG_NAME"

#!/usr/bin/env zsh

# Bootstrap defaults (overridden by ~/.zshenv values set via 'dotfiles profile')
export DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
export DOTFILES_PROFILE="${DOTFILES_PROFILE:-core}"
export DOTFILES_VERBOSE="${DOTFILES_VERBOSE:-false}"

# Validate environment
if [[ ! -d "$DOTFILES_ROOT" ]]; then
    echo "ERROR: DOTFILES_ROOT not found: $DOTFILES_ROOT" >&2
    return 1 2>/dev/null || exit 1
fi
if [[ ! -d "$DOTFILES_ROOT/zsh" ]]; then
    echo "ERROR: $DOTFILES_ROOT/zsh not found — run: dotfiles install" >&2
    return 1 2>/dev/null || exit 1
fi

# Load core modules in numeric order: 10-options, 20-history, 30-completion, 40-aliases, 50-theme
for _f in "$DOTFILES_ROOT"/zsh/core/*.zsh(N); do source "$_f"; done
unset _f

# Load shared libraries
source "$DOTFILES_ROOT/zsh/lib/platform.zsh"
source "$DOTFILES_ROOT/zsh/lib/installer.zsh"

# Load packages for active profile (cumulative: core ⊆ full)
# `minimal` and `server` accepted as legacy aliases for one release —
# auto-migrated to `core`/`full` by bin/dotfiles' set_defaults on next install.
typeset -a _pkg_dirs
case "${DOTFILES_PROFILE}" in
    core|minimal)
        _pkg_dirs=("$DOTFILES_ROOT/zsh/packages/core") ;;
    full|server)
        _pkg_dirs=("$DOTFILES_ROOT/zsh/packages/core" "$DOTFILES_ROOT/zsh/packages/full") ;;
    *)
        echo "[dotfiles] Unknown profile '${DOTFILES_PROFILE}' — defaulting to core. Run: dotfiles profile <core|full>" >&2
        _pkg_dirs=("$DOTFILES_ROOT/zsh/packages/core") ;;
esac
for _pkg_dir in "$_pkg_dirs[@]"; do
    for _pkg_file in "$_pkg_dir"/*.zsh(N); do source "$_pkg_file"; done
done
unset _pkg_dirs _pkg_dir _pkg_file

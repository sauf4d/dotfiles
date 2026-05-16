#!/usr/bin/env zsh

# Bootstrap defaults (overridden by ~/.zshenv values set via 'dotfiles profile')
export DOTFILES_ROOT="${DOTFILES_ROOT:-$HOME/.dotfiles}"
export DOTFILES_PROFILE="${DOTFILES_PROFILE:-core}"

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

# Load packages for active profile (cumulative: core ⊆ <profile>).
# Profile dirs are derived from the filesystem: $DOTFILES_ROOT/zsh/packages/<name>/
# Legacy aliases (NFR-D — kept for at least one major version):
#   `minimal` → core, `full` → dev (one-shot migrated by bin/dotfiles'
#   set_defaults on next `dotfiles install`). `server` is now a REAL profile.
typeset -a _pkg_dirs
_pkg_dirs=("$DOTFILES_ROOT/zsh/packages/core")
if [[ "${DOTFILES_PROFILE}" != "core" && "${DOTFILES_PROFILE}" != "minimal" ]]; then
    _profile="${DOTFILES_PROFILE}"
    [[ "$_profile" == "full" ]] && _profile="dev"  # legacy alias
    if [[ -d "$DOTFILES_ROOT/zsh/packages/$_profile" ]]; then
        _pkg_dirs+=("$DOTFILES_ROOT/zsh/packages/$_profile")
    else
        echo "[dotfiles] Unknown profile '${DOTFILES_PROFILE}' — defaulting to core. Run: dotfiles config set profile <name>" >&2
    fi
    unset _profile
fi
for _pkg_dir in "$_pkg_dirs[@]"; do
    for _pkg_file in "$_pkg_dir"/*.zsh(N); do source "$_pkg_file"; done
done
unset _pkg_dirs _pkg_dir _pkg_file

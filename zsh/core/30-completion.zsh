#!/usr/bin/env zsh

# =============================================================================
# Completion styles
# NOTE: compinit is called in zsh/packages/core/00-sheldon.zsh AFTER
# sheldon sources zsh-completions, ensuring fpath is fully populated first.
# This file contains only zstyle declarations + fpath additions — no compinit.
# =============================================================================

# Repo-shipped completions (e.g. `_dotfiles`). Must be added BEFORE compinit
# runs in sheldon's pkg_init — that ordering is guaranteed by 30-completion.zsh
# loading before any package file.
if [[ -d "$DOTFILES_ROOT/share/completions" ]]; then
    fpath=("$DOTFILES_ROOT/share/completions" $fpath)
fi

# Menu-based completion with selection highlight
zstyle ':completion:*' menu select

# Group completions by category
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '[%d]'

# Case-insensitive, then partial-word, then substring matching
zstyle ':completion:*' matcher-list \
    'm:{a-zA-Z}={A-Za-z}' \
    'r:|[._-]=* r:|=*' \
    'l:|=* r:|=*'

# Use colors in file completion (same palette as ls)
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# Disable sort for git checkout (keeps branch order meaningful)
zstyle ':completion:*:git-checkout:*' sort false

# fzf-tab: switch between groups with < and >
zstyle ':fzf-tab:*' switch-group '<' '>'

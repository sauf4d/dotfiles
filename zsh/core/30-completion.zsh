#!/usr/bin/env zsh

# =============================================================================
# Completion styles
# NOTE: compinit is called in zsh/packages/core/00-sheldon.zsh AFTER
# sheldon sources zsh-completions, ensuring fpath is fully populated first.
# This file contains only zstyle declarations — no compinit call.
# =============================================================================

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

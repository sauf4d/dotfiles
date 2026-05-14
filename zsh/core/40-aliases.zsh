#!/usr/bin/env zsh

# =============================================================================
# Shell aliases
# Tool-specific aliases (ls/eza, cd/zoxide) live in their package files
# so they are only active when the tool is installed.
# =============================================================================

# Shell reload
alias zshsrc="source ~/.zshrc"
alias zshedit="${EDITOR:-vi} ~/.zshrc"

# Navigation shortcuts
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias ~="cd ~"

#!/usr/bin/env zsh

# =============================================================================
# Shell aliases
# Tool-specific aliases (ls/eza, cd/zoxide) live in their package files
# so they are only active when the tool is installed.
# =============================================================================

# dotfiles CLI — wraps the binary so exec zsh happens in THIS process,
# replacing the current shell instead of spawning a child (one exit to quit).
dotfiles() {
  DOTFILES_WRAPPER=1 command dotfiles "$@"
  local rc=$?
  [[ $rc -eq 0 ]] || return $rc
  # Strip a leading verbose flag to find the actual command
  local _cmd="${1:-}"
  [[ "$_cmd" == "-v" || "$_cmd" == "--verbose" ]] && _cmd="${2:-}"
  case "$_cmd" in
    install|i|-i|sync|s|-s|update|u|-u) exec zsh ;;
  esac
  return $rc
}

# Shell reload
alias zshsrc="source ~/.zshrc"
alias zshedit="${EDITOR:-vi} ~/.zshrc"

# Navigation shortcuts
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias ~="cd ~"

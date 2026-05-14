#!/bin/sh
# =============================================================================
# Shared logging helpers — sourced by bash (bin/dotfiles) AND zsh
# (zsh/lib/installer.zsh). MUST stay POSIX-compatible.
# =============================================================================
#
# Two-tier model:
#
#   Tier 1 — Always-print (visible in CLI invocations and shell startup errors)
#     _dotfiles_log_step      CLI progress marker              stdout
#     _dotfiles_log_detail    plain bullet: always-visible     stdout
#     _dotfiles_log_result    label: value diagnostic line     stdout
#     _dotfiles_log_summary   one-line final outcome           stdout
#     _dotfiles_log_warning   non-fatal problem                stderr
#     _dotfiles_log_error     fatal problem                    stderr
#
#   Tier 2 — Verbose-only (silent unless DOTFILES_VERBOSE=true)
#     _dotfiles_log_debug     low-priority trace               stdout
#     _dotfiles_log_info      normal info                      stdout
#     _dotfiles_log_dim       indented detail                  stdout
#     _dotfiles_log_success   operation succeeded              stdout
#
# Shell startup uses ONLY verbose-only helpers → normal shell start is silent.
# CLI commands use always-print helpers → useful output without -v flag.
# Pass DOTFILES_VERBOSE=true (or -v) to add deep diagnostic depth (Tier 2).
# =============================================================================

# Re-source guard
[ -n "${_DOTFILES_LOG_LOADED:-}" ] && return 0
_DOTFILES_LOG_LOADED=1

# -----------------------------------------------------------------------------
# Colors and glyphs — disabled when stdout is not a TTY or NO_COLOR is set
# -----------------------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _DF_BOLD='\033[1m'
    _DF_RESET='\033[0m'
    _DF_RED='\033[31m'
    _DF_GREEN='\033[32m'
    _DF_YELLOW='\033[33m'
    _DF_BLUE='\033[34m'
    _DF_MAGENTA='\033[35m'
    _DF_CYAN='\033[36m'
    _DF_WHITE='\033[97m'
    _DF_GRAY='\033[90m'
else
    _DF_BOLD=''; _DF_RESET=''; _DF_RED=''; _DF_GREEN=''
    _DF_YELLOW=''; _DF_BLUE=''; _DF_MAGENTA=''; _DF_CYAN=''
    _DF_WHITE=''; _DF_GRAY=''
fi

# Unicode glyphs (CLI style)
_DF_CHECK='✓'
_DF_CROSS='✗'
_DF_ARROW='→'
_DF_BULLET='•'
_DF_WARN='⚠'

# -----------------------------------------------------------------------------
# Verbose helpers
# -----------------------------------------------------------------------------
_dotfiles_is_verbose() {
    [ "${DOTFILES_VERBOSE:-false}" = "true" ]
}

# -----------------------------------------------------------------------------
# Verbose-only helpers (silent unless DOTFILES_VERBOSE=true)
# -----------------------------------------------------------------------------
_dotfiles_log_debug() {
    _dotfiles_is_verbose || return 0
    printf '%b[DEBUG]%b %b%s%b\n' "$_DF_MAGENTA" "$_DF_RESET" "$_DF_GRAY" "$*" "$_DF_RESET"
}

_dotfiles_log_info() {
    _dotfiles_is_verbose || return 0
    printf '%b%s%b %b%s%b\n' "$_DF_CYAN" "$_DF_BULLET" "$_DF_RESET" "$_DF_WHITE" "$*" "$_DF_RESET"
}

_dotfiles_log_dim() {
    _dotfiles_is_verbose || return 0
    printf '  %b%s%b\n' "$_DF_GRAY" "$*" "$_DF_RESET"
}

_dotfiles_log_success() {
    _dotfiles_is_verbose || return 0
    printf '%b%s%b %b%b%s%b\n' "$_DF_GREEN" "$_DF_CHECK" "$_DF_RESET" "$_DF_BOLD" "$_DF_GREEN" "$*" "$_DF_RESET"
}

# -----------------------------------------------------------------------------
# Always-print helpers
# -----------------------------------------------------------------------------
_dotfiles_log_step() {
    printf '%b%s%b %b%b%s%b\n' "$_DF_MAGENTA" "$_DF_ARROW" "$_DF_RESET" "$_DF_BOLD" "$_DF_MAGENTA" "$*" "$_DF_RESET"
}

_dotfiles_log_summary() {
    printf '%b%s%b %s\n' "$_DF_GREEN" "$_DF_CHECK" "$_DF_RESET" "$*"
}

_dotfiles_log_warning() {
    printf '%b%s%b  %b%s%b\n' "$_DF_YELLOW" "$_DF_WARN" "$_DF_RESET" "$_DF_YELLOW" "$*" "$_DF_RESET" >&2
}

_dotfiles_log_error() {
    printf '%b%s%b %b%b%s%b\n' "$_DF_RED" "$_DF_CROSS" "$_DF_RESET" "$_DF_BOLD" "$_DF_RED" "$*" "$_DF_RESET" >&2
}

_dotfiles_log_detail() {
    printf '%b%s%b %b%s%b\n' "$_DF_CYAN" "$_DF_BULLET" "$_DF_RESET" "$_DF_WHITE" "$*" "$_DF_RESET"
}

_dotfiles_log_result() {
    printf '  %b%s:%b %b%s%b\n' "$_DF_GRAY" "$1" "$_DF_RESET" "$_DF_WHITE" "$2" "$_DF_RESET"
}

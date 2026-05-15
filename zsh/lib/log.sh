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
    _DF_DIM='\033[2m'
    _DF_RESET='\033[0m'
    _DF_RED='\033[31m'
    _DF_GREEN='\033[32m'
    _DF_YELLOW='\033[33m'
    _DF_BLUE='\033[34m'
    _DF_MAGENTA='\033[35m'
    _DF_CYAN='\033[36m'
    _DF_WHITE='\033[97m'
    _DF_GRAY='\033[90m'
    # Semantic palette — use these in feature code instead of raw colors.
    # Centralized so theme tweaks live in one place.
    _DF_C_OK="$_DF_GREEN"        # success states
    _DF_C_WARN="$_DF_YELLOW"     # warnings, soft failures
    _DF_C_FAIL="$_DF_RED"        # hard failures
    _DF_C_INFO="$_DF_CYAN"       # neutral information
    _DF_C_DIM="$_DF_GRAY"        # de-emphasized text, labels
    _DF_C_HIGHLIGHT="$_DF_WHITE" # primary values
    _DF_C_ACCENT="$_DF_MAGENTA"  # section markers, progress
else
    _DF_BOLD=''; _DF_DIM=''; _DF_RESET=''; _DF_RED=''; _DF_GREEN=''
    _DF_YELLOW=''; _DF_BLUE=''; _DF_MAGENTA=''; _DF_CYAN=''
    _DF_WHITE=''; _DF_GRAY=''
    _DF_C_OK=''; _DF_C_WARN=''; _DF_C_FAIL=''; _DF_C_INFO=''
    _DF_C_DIM=''; _DF_C_HIGHLIGHT=''; _DF_C_ACCENT=''
fi

# Unicode glyphs (CLI style)
_DF_CHECK='✓'
_DF_CROSS='✗'
_DF_ARROW='→'
_DF_BULLET='•'
_DF_WARN='⚠'

# -----------------------------------------------------------------------------
# Verbose / quiet helpers
# -----------------------------------------------------------------------------
_dotfiles_is_verbose() {
    [ "${DOTFILES_VERBOSE:-false}" = "true" ]
}

_dotfiles_is_quiet() {
    [ "${DOTFILES_QUIET:-false}" = "true" ]
}

# -----------------------------------------------------------------------------
# Verbose-only helpers (silent unless DOTFILES_VERBOSE=true)
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# Debug timing helper — returns a monotonic-ish float in seconds.
# Uses EPOCHREALTIME (bash 5+, microsecond) when available, falls back to
# `date +%s.%N` (Linux) or `date +%s` (BSD/macOS without GNU date).
# -----------------------------------------------------------------------------
_dotfiles_now() {
    if [ -n "${EPOCHREALTIME:-}" ]; then
        printf '%s\n' "$EPOCHREALTIME"
        return 0
    fi
    # GNU date supports %N; BSD date does not. Try %N; if it echoes "N" literal,
    # fall back to integer seconds. Done once per session for speed.
    if [ -z "${_DF_DATE_FMT:-}" ]; then
        if date +%N 2>/dev/null | grep -q '^[0-9]'; then
            _DF_DATE_FMT='%s.%N'
        else
            _DF_DATE_FMT='%s'
        fi
    fi
    date +"$_DF_DATE_FMT"
}

# _dotfiles_log_debug [<scope>] <message...>
#
# Emits a verbose-only debug line with optional scope tag, wall-clock time,
# and a delta since the previous debug call in this scope.
#
# Format:
#   [HH:MM:SS.mmm] [scope] message (+12ms)
#
# Scope sources, in order:
#   1. First arg if it matches \[?[A-Z][A-Z0-9_:-]*\]?  (e.g. "PKG:fzf" or "[PKG:fzf]")
#   2. $DOTFILES_LOG_SCOPE env var
#   3. No scope tag
#
# Backward compat: callers that pass just "<message>" with no scope keep
# working — output gains a timestamp prefix but no scope tag.
_dotfiles_log_debug() {
    _dotfiles_is_quiet && return 0
    _dotfiles_is_verbose || return 0

    local scope="" msg="" ts_iso="" delta_ms=""
    # Detect inline scope arg (matches bracketed or bare "KEY" or "KEY:value").
    case "${1:-}" in
        \[*\])
            scope="${1#[}"; scope="${scope%]}"
            shift
            ;;
        [A-Z]*)
            # Heuristic: ALL-CAPS first arg with optional :colon is a scope.
            if [ -z "${1##*[!A-Z0-9_:-]*}" ]; then
                : # Contains non-scope chars — treat as message.
            else
                scope="$1"
                shift
            fi
            ;;
    esac
    [ -z "$scope" ] && scope="${DOTFILES_LOG_SCOPE:-}"
    msg="$*"

    # Timestamp HH:MM:SS.mmm (POSIX date can't do ms — combine with EPOCHREALTIME)
    local now_s
    now_s="$(_dotfiles_now)"
    # Extract HH:MM:SS from `date`, append milliseconds from now_s
    local hms ms
    hms="$(date +'%H:%M:%S' 2>/dev/null)"
    # ms = fractional part of now_s, padded/truncated to 3 digits
    case "$now_s" in
        *.*) ms="${now_s#*.}"; ms="${ms}000"; ms="${ms:0:3}" ;;
        *)   ms="000" ;;
    esac
    ts_iso="${hms}.${ms}"

    # Delta since previous debug call (per session, not per scope — kept simple)
    if [ -n "${_DF_LAST_DEBUG_TIME:-}" ]; then
        # Float subtraction in shell — use awk (already a dep) for portability.
        delta_ms="$(awk -v a="$now_s" -v b="$_DF_LAST_DEBUG_TIME" 'BEGIN { printf "%d", (a - b) * 1000 }')"
    fi
    _DF_LAST_DEBUG_TIME="$now_s"

    # Assemble output. All decoration is colored; the message stays plain.
    if [ -n "$scope" ] && [ -n "$delta_ms" ]; then
        printf '%b[%s]%b %b[%s]%b %b%s%b %b(+%sms)%b\n' \
            "$_DF_DIM" "$ts_iso" "$_DF_RESET" \
            "$_DF_C_ACCENT" "$scope" "$_DF_RESET" \
            "$_DF_GRAY" "$msg" "$_DF_RESET" \
            "$_DF_DIM" "$delta_ms" "$_DF_RESET"
    elif [ -n "$scope" ]; then
        printf '%b[%s]%b %b[%s]%b %b%s%b\n' \
            "$_DF_DIM" "$ts_iso" "$_DF_RESET" \
            "$_DF_C_ACCENT" "$scope" "$_DF_RESET" \
            "$_DF_GRAY" "$msg" "$_DF_RESET"
    elif [ -n "$delta_ms" ]; then
        printf '%b[%s]%b %b%s%b %b(+%sms)%b\n' \
            "$_DF_DIM" "$ts_iso" "$_DF_RESET" \
            "$_DF_GRAY" "$msg" "$_DF_RESET" \
            "$_DF_DIM" "$delta_ms" "$_DF_RESET"
    else
        printf '%b[%s]%b %b%s%b\n' \
            "$_DF_DIM" "$ts_iso" "$_DF_RESET" \
            "$_DF_GRAY" "$msg" "$_DF_RESET"
    fi
}

_dotfiles_log_info() {
    _dotfiles_is_quiet && return 0
    _dotfiles_is_verbose || return 0
    printf '%b%s%b %b%s%b\n' "$_DF_CYAN" "$_DF_BULLET" "$_DF_RESET" "$_DF_WHITE" "$*" "$_DF_RESET"
}

_dotfiles_log_dim() {
    _dotfiles_is_quiet && return 0
    _dotfiles_is_verbose || return 0
    printf '  %b%b%b\n' "$_DF_GRAY" "$*" "$_DF_RESET"
}

_dotfiles_log_success() {
    _dotfiles_is_quiet && return 0
    _dotfiles_is_verbose || return 0
    printf '%b%s%b %b%b%s%b\n' "$_DF_GREEN" "$_DF_CHECK" "$_DF_RESET" "$_DF_BOLD" "$_DF_GREEN" "$*" "$_DF_RESET"
}

# -----------------------------------------------------------------------------
# Always-print helpers
# -----------------------------------------------------------------------------
_dotfiles_log_step() {
    _dotfiles_is_quiet && return 0
    printf '%b%s%b %b%b%s%b\n' "$_DF_MAGENTA" "$_DF_ARROW" "$_DF_RESET" "$_DF_BOLD" "$_DF_MAGENTA" "$*" "$_DF_RESET"
}

_dotfiles_log_summary() {
    _dotfiles_is_quiet && return 0
    printf '%b%s%b %s\n' "$_DF_GREEN" "$_DF_CHECK" "$_DF_RESET" "$*"
}

_dotfiles_log_warning() {
    printf '%b%s%b  %b%s%b\n' "$_DF_YELLOW" "$_DF_WARN" "$_DF_RESET" "$_DF_YELLOW" "$*" "$_DF_RESET" >&2
}

_dotfiles_log_error() {
    printf '%b%s%b %b%b%s%b\n' "$_DF_RED" "$_DF_CROSS" "$_DF_RESET" "$_DF_BOLD" "$_DF_RED" "$*" "$_DF_RESET" >&2
}

# Recovery hint — pair with _dotfiles_log_error to suggest the fix.
# Goes to stderr so it survives `command 2>&1 | grep -v hint` style filters
# but stays adjacent to its error in normal terminal use.
_dotfiles_log_hint() {
    _dotfiles_is_quiet && return 0
    printf '  %bhint:%b %b%s%b\n' "$_DF_GRAY" "$_DF_RESET" "$_DF_WHITE" "$*" "$_DF_RESET" >&2
}

_dotfiles_log_detail() {
    _dotfiles_is_quiet && return 0
    printf '%b%s%b %b%s%b\n' "$_DF_CYAN" "$_DF_BULLET" "$_DF_RESET" "$_DF_WHITE" "$*" "$_DF_RESET"
}

_dotfiles_log_result() {
    _dotfiles_is_quiet && return 0
    printf '  %b%s:%b %b%s%b\n' "$_DF_GRAY" "$1" "$_DF_RESET" "$_DF_WHITE" "$2" "$_DF_RESET"
}

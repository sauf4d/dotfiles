#!/usr/bin/env bash
# =============================================================================
# UI primitives for the dotfiles CLI — bash 4+ only.
#
# Sourced ONLY by bin/dotfiles. Never sourced by zsh shell startup.
# POSIX compatibility is NOT required here; bashisms are fine.
#
# Provides:
#   _dotfiles_spin         <label> -- <cmd...>   run cmd with spinner
#   _dotfiles_table        <key> <val> ...       aligned key:value table
#   _dotfiles_badge        <STATUS> <label>      colored status pill
#   _dotfiles_progress     <cur> <total> <lbl>   in-place progress bar
#   _dotfiles_did_you_mean <input> <cands...>    Levenshtein suggestion
#
# All primitives degrade gracefully when stdout is not a TTY or NO_COLOR is set.
# All primitives honor DOTFILES_QUIET=true (silent unless a wrapped command
# fails, in which case failure output still goes to stderr).
# =============================================================================

# Re-source guard
[[ -n "${_DOTFILES_UI_LOADED:-}" ]] && return 0
_DOTFILES_UI_LOADED=1

# Defensive: source log.sh for the shared palette if not already loaded.
if [[ -z "${_DF_GREEN+x}" ]]; then
    # shellcheck source=/dev/null
    . "${BASH_SOURCE[0]%/*}/log.sh"
fi

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

# Returns 0 if stdout is an interactive TTY with color allowed.
_dotfiles_ui_is_interactive() {
    [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]
}

# Current wall-clock seconds as a float. Uses EPOCHREALTIME (bash 5+) when
# available; falls back to `date +%s.%N`.
_dotfiles_ui_now() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        printf '%s\n' "$EPOCHREALTIME"
    else
        date +%s.%N
    fi
}

# Compute end - start as a 2-decimal-digit seconds string, pure bash.
# Inputs may have nanoseconds; we truncate to centiseconds and subtract via
# integer math to avoid awk/bc.
_dotfiles_ui_elapsed() {
    local start="$1" end="$2"
    # Strip the dot, keep first two fractional digits, pad if missing.
    local s_int s_frac e_int e_frac
    s_int="${start%%.*}"
    e_int="${end%%.*}"
    s_frac="${start#*.}"
    e_frac="${end#*.}"
    # If no fractional part, restore empty.
    [[ "$s_frac" == "$start" ]] && s_frac=""
    [[ "$e_frac" == "$end" ]]   && e_frac=""
    # Normalize to 2 digits (centiseconds).
    s_frac="${s_frac}00"
    e_frac="${e_frac}00"
    s_frac="${s_frac:0:2}"
    e_frac="${e_frac:0:2}"
    # Strip leading zeros to avoid octal interpretation.
    s_frac="${s_frac#0}"; [[ -z "$s_frac" ]] && s_frac=0
    e_frac="${e_frac#0}"; [[ -z "$e_frac" ]] && e_frac=0
    local s_cs=$(( s_int * 100 + s_frac ))
    local e_cs=$(( e_int * 100 + e_frac ))
    local diff=$(( e_cs - s_cs ))
    (( diff < 0 )) && diff=0
    local whole=$(( diff / 100 ))
    local frac=$(( diff % 100 ))
    printf '%d.%02d' "$whole" "$frac"
}

# Detect 256-color support without requiring `tput`.
_dotfiles_ui_has_256() {
    if command -v tput >/dev/null 2>&1; then
        local n
        n="$(tput colors 2>/dev/null || echo 0)"
        [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 256 ))
        return $?
    fi
    case "${TERM:-}" in
        *-256color|*-256|xterm-kitty|alacritty|tmux-256color) return 0 ;;
    esac
    return 1
}

# Pick spinner frames based on locale: braille if UTF, else ASCII.
_dotfiles_ui_spinner_frames() {
    case "${LANG:-}${LC_ALL:-}" in
        *UTF*|*utf*) printf '%s\n' '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' ;;
        *)           printf '%s\n' '|' '/' '-' '\' ;;
    esac
}

# -----------------------------------------------------------------------------
# 1. _dotfiles_spin <label> -- <cmd...>
# -----------------------------------------------------------------------------
_dotfiles_spin() {
    local label=""
    # Collect label tokens up to the literal '--' separator.
    while (( $# )); do
        if [[ "$1" == "--" ]]; then
            shift
            break
        fi
        label+="${label:+ }$1"
        shift
    done
    if (( $# == 0 )); then
        _dotfiles_log_error "_dotfiles_spin: missing command after '--'"
        return 2
    fi

    local quiet=0
    _dotfiles_is_quiet 2>/dev/null && quiet=1
    local interactive=1
    _dotfiles_ui_is_interactive || interactive=0

    local tmp rc=0 start end elapsed
    tmp="$(mktemp -t dotfiles_spin.XXXXXX 2>/dev/null || mktemp)"

    start="$(_dotfiles_ui_now)"

    # Non-interactive or quiet: run silently, only surface on failure.
    if (( quiet )) || (( ! interactive )); then
        "$@" >"$tmp" 2>&1
        rc=$?
        end="$(_dotfiles_ui_now)"
        elapsed="$(_dotfiles_ui_elapsed "$start" "$end")"
        if (( rc != 0 )); then
            printf '%b%s%b %s %b(%ss)%b\n' \
                "$_DF_RED" "$_DF_CROSS" "$_DF_RESET" \
                "$label" "$_DF_GRAY" "$elapsed" "$_DF_RESET" >&2
            printf '  %b───── output ─────%b\n' "$_DF_GRAY" "$_DF_RESET" >&2
            tail -n 20 "$tmp" | sed 's/^/  /' >&2
            printf '  %b──────────────────%b\n' "$_DF_GRAY" "$_DF_RESET" >&2
        elif (( ! quiet )); then
            # Non-interactive but not quiet: still emit a one-line completion.
            printf '%b%s%b %s %b(%ss)%b\n' \
                "$_DF_GREEN" "$_DF_CHECK" "$_DF_RESET" \
                "$label" "$_DF_GRAY" "$elapsed" "$_DF_RESET"
        fi
        rm -f "$tmp"
        return "$rc"
    fi

    # Interactive: background the command, spin until it finishes.
    local frames=()
    local f
    while IFS= read -r f; do frames+=("$f"); done < <(_dotfiles_ui_spinner_frames)
    local frame_count=${#frames[@]}

    "$@" >"$tmp" 2>&1 &
    local pid=$!

    # Cleanup on signal: clear line, kill child, remove tmp.
    # shellcheck disable=SC2064
    trap "kill $pid 2>/dev/null; printf '\r\033[K' >&2; rm -f '$tmp'; trap - INT TERM; return 130" INT TERM

    # Hide cursor.
    printf '\033[?25l' >&2

    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r\033[K%b%s%b %s' \
            "$_DF_CYAN" "${frames[i % frame_count]}" "$_DF_RESET" "$label" >&2
        i=$(( i + 1 ))
        sleep 0.08
    done

    wait "$pid"
    rc=$?
    end="$(_dotfiles_ui_now)"
    elapsed="$(_dotfiles_ui_elapsed "$start" "$end")"

    # Clear the spinner line and restore cursor.
    printf '\r\033[K' >&2
    printf '\033[?25h' >&2
    trap - INT TERM

    if (( rc == 0 )); then
        printf '%b%s%b %s %b(%ss)%b\n' \
            "$_DF_GREEN" "$_DF_CHECK" "$_DF_RESET" \
            "$label" "$_DF_GRAY" "$elapsed" "$_DF_RESET"
    else
        printf '%b%s%b %s %b(%ss)%b\n' \
            "$_DF_RED" "$_DF_CROSS" "$_DF_RESET" \
            "$label" "$_DF_GRAY" "$elapsed" "$_DF_RESET" >&2
        printf '  %b───── output ─────%b\n' "$_DF_GRAY" "$_DF_RESET" >&2
        tail -n 20 "$tmp" | sed 's/^/  /' >&2
        printf '  %b──────────────────%b\n' "$_DF_GRAY" "$_DF_RESET" >&2
    fi

    rm -f "$tmp"
    return "$rc"
}

# -----------------------------------------------------------------------------
# 2. _dotfiles_table <k1> <v1> <k2> <v2> ...
# -----------------------------------------------------------------------------
_dotfiles_table() {
    if (( $# == 0 )); then
        return 0
    fi
    if (( $# % 2 != 0 )); then
        _dotfiles_log_error "_dotfiles_table: odd number of args (need key/value pairs)"
        return 2
    fi

    local quiet=0
    _dotfiles_is_quiet 2>/dev/null && quiet=1
    local interactive=1
    _dotfiles_ui_is_interactive || interactive=0

    # Compute longest key for alignment (both TTY and non-TTY paths use it).
    local args=("$@")
    local max=0 k v i
    for (( i=0; i<${#args[@]}; i+=2 )); do
        k="${args[i]}"
        (( ${#k} > max )) && max=${#k}
    done

    # Quiet: nothing. (Tables are tier-1 status output, not errors.)
    if (( quiet )); then
        return 0
    fi

    # Non-interactive but not quiet: aligned plain text, no colors. Keeps the
    # 2-space indent so output piped to file/grep still looks like a list.
    if (( ! interactive )); then
        for (( i=0; i<${#args[@]}; i+=2 )); do
            k="${args[i]}"
            v="${args[i+1]}"
            printf '  %-*s : %s\n' "$max" "$k" "$v"
        done
        return 0
    fi

    # Interactive: colored, aligned, gray keys / white values.
    for (( i=0; i<${#args[@]}; i+=2 )); do
        k="${args[i]}"
        v="${args[i+1]}"
        printf '  %b%-*s%b %b:%b %b%s%b\n' \
            "$_DF_GRAY" "$max" "$k" "$_DF_RESET" \
            "$_DF_GRAY" "$_DF_RESET" \
            "$_DF_WHITE" "$v" "$_DF_RESET"
    done
}

# -----------------------------------------------------------------------------
# 3. _dotfiles_badge <STATUS> <label>
# -----------------------------------------------------------------------------
_dotfiles_badge() {
    local status="$1"
    shift
    local label="$*"

    local interactive=1
    _dotfiles_ui_is_interactive || interactive=0

    if (( ! interactive )); then
        printf '[%s] %s\n' "$status" "$label"
        return 0
    fi

    # 256-color palette indices (close to the named colors above).
    local bg_idx fg fg_name glyph text
    case "$status" in
        OK)   bg_idx=22;  fg="$_DF_GREEN";  glyph="$_DF_CHECK"; text=" OK   " ;;
        WARN) bg_idx=94;  fg="$_DF_YELLOW"; glyph="$_DF_WARN";  text=" WARN " ;;
        FAIL) bg_idx=52;  fg="$_DF_RED";    glyph="$_DF_CROSS"; text=" FAIL " ;;
        INFO) bg_idx=24;  fg="$_DF_BLUE";   glyph="$_DF_BULLET";text=" INFO " ;;
        *)
            printf '[%s] %s\n' "$status" "$label"
            return 0
            ;;
    esac

    if _dotfiles_ui_has_256; then
        # White text on colored background pill, then glyph + label.
        printf '\033[1m\033[38;5;15m\033[48;5;%sm%s\033[0m %b%s%b %s\n' \
            "$bg_idx" "$text" "$fg" "$glyph" "$_DF_RESET" "$label"
    else
        # Foreground-only fallback: bold colored [STATUS] glyph label
        printf '%b%b[%s]%b %b%s%b %s\n' \
            "$_DF_BOLD" "$fg" "$status" "$_DF_RESET" \
            "$fg" "$glyph" "$_DF_RESET" "$label"
    fi
}

# -----------------------------------------------------------------------------
# 4. _dotfiles_progress <current> <total> <label>
# -----------------------------------------------------------------------------
_dotfiles_progress() {
    local current="$1" total="$2"
    shift 2
    local label="$*"
    local width=20

    # Guard against div by zero / weird input.
    if ! [[ "$current" =~ ^[0-9]+$ ]] || ! [[ "$total" =~ ^[0-9]+$ ]] || (( total <= 0 )); then
        return 2
    fi
    (( current > total )) && current=$total

    local quiet=0
    _dotfiles_is_quiet 2>/dev/null && quiet=1
    local interactive=1
    _dotfiles_ui_is_interactive || interactive=0

    # Quiet or non-interactive: only print on completion as a single line.
    if (( quiet )) || (( ! interactive )); then
        if (( current == total )); then
            printf '%d/%d %s\n' "$current" "$total" "$label"
        fi
        return 0
    fi

    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))

    # Build bar strings.
    local bar="" i
    for (( i=0; i<filled; i++ )); do bar+='█'; done
    for (( i=0; i<empty;  i++ )); do bar+='░'; done

    printf '\r\033[K%b[%s]%b %d/%d %s' \
        "$_DF_CYAN" "$bar" "$_DF_RESET" \
        "$current" "$total" "$label"

    if (( current == total )); then
        printf '\n'
    fi
}

# -----------------------------------------------------------------------------
# 5. _dotfiles_did_you_mean <input> <candidates...>
# -----------------------------------------------------------------------------

# Pure-bash Levenshtein distance. Echoes the integer distance.
_dotfiles_ui_levenshtein() {
    local a="$1" b="$2"
    local la=${#a} lb=${#b}

    # Trivial cases.
    if (( la == 0 )); then printf '%d\n' "$lb"; return; fi
    if (( lb == 0 )); then printf '%d\n' "$la"; return; fi

    # Two-row dynamic programming. prev[j], curr[j] for j in 0..lb.
    local -a prev curr
    local i j cost
    for (( j=0; j<=lb; j++ )); do prev[j]=$j; done

    for (( i=1; i<=la; i++ )); do
        curr[0]=$i
        local ai="${a:i-1:1}"
        for (( j=1; j<=lb; j++ )); do
            local bj="${b:j-1:1}"
            if [[ "$ai" == "$bj" ]]; then cost=0; else cost=1; fi
            local del=$(( prev[j] + 1 ))
            local ins=$(( curr[j-1] + 1 ))
            local sub=$(( prev[j-1] + cost ))
            local m=$del
            (( ins < m )) && m=$ins
            (( sub < m )) && m=$sub
            curr[j]=$m
        done
        for (( j=0; j<=lb; j++ )); do prev[j]=${curr[j]}; done
    done

    printf '%d\n' "${prev[lb]}"
}

_dotfiles_did_you_mean() {
    local input="$1"
    shift
    (( $# == 0 )) && return 0
    [[ -z "$input" ]] && return 0

    local best_cand="" best_dist=999
    local cand dist
    for cand in "$@"; do
        dist="$(_dotfiles_ui_levenshtein "$input" "$cand")"
        if (( dist < best_dist )); then
            best_dist=$dist
            best_cand=$cand
        fi
    done

    # Thresholds: distance <= 3 AND distance < len(input)/2.
    local half=$(( ${#input} / 2 ))
    if (( best_dist <= 3 )) && (( best_dist < half )); then
        printf '%s\n' "$best_cand"
    fi
}

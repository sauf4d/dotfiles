#!/usr/bin/env zsh

# Stale-sync nudge (UC-10) — one non-blocking line on interactive shell start
# if the repo's last fetch was more than 7 days ago. Pure local stat — no
# network call (NFR-B: daily operation must be offline).
#
# Gated on:
#   - interactive shell (skip in scripts, dotfiles install subshells, CI)
#   - DOTFILES_QUIET != true
#   - $DOTFILES_ROOT/.git exists (defensive — skip on detached/uncloned setups)
#   - FETCH_HEAD exists (otherwise the repo was never fetched, nothing to nudge)

[[ -o interactive ]] || return 0
[[ "${DOTFILES_QUIET:-false}" == "true" ]] && return 0
[[ -d "$DOTFILES_ROOT/.git" ]] || return 0

() {
    local fetch_head="$DOTFILES_ROOT/.git/FETCH_HEAD"
    [[ -f "$fetch_head" ]] || return 0

    zmodload zsh/stat zsh/datetime 2>/dev/null

    local -A stat_out
    zstat -H stat_out +mtime "$fetch_head" 2>/dev/null || return 0
    local mtime="${stat_out[mtime]}"
    [[ -z "$mtime" ]] && return 0

    local now="${EPOCHSECONDS:-$(date +%s)}"
    local age_days=$(( (now - mtime) / 86400 ))

    (( age_days < 7 )) && return 0

    # Tier-1 hint on stderr — visible without -v, never blocks shell startup.
    print -u2 "[dotfiles] last synced ${age_days} days ago — run \`dotfiles sync\`"
} "$@"

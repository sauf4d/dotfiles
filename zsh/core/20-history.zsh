#!/usr/bin/env zsh

# =============================================================================
# History settings and fzf history widget
# =============================================================================

HISTSIZE=3000
SAVEHIST=3000
HISTFILE=~/.zsh_history

setopt SHARE_HISTORY           # Share history between sessions (implies INC_APPEND_HISTORY)
setopt APPEND_HISTORY          # Append to history file
setopt HIST_IGNORE_DUPS        # Don't record duplicates
setopt HIST_IGNORE_SPACE       # Don't record commands starting with space
setopt HIST_REDUCE_BLANKS      # Remove superfluous blanks
setopt HIST_VERIFY             # Show command before running history expansion
setopt HIST_EXPIRE_DUPS_FIRST  # Expire duplicates first when trimming
setopt HIST_FIND_NO_DUPS       # Don't display duplicates when searching
setopt HIST_IGNORE_ALL_DUPS    # Delete old entry if new entry is a duplicate

# Reset mouse tracking escape sequences left behind by apps (vim, fzf, less, etc.)
# Runs before every prompt to prevent raw SGR mouse codes leaking into the shell.
autoload -Uz add-zsh-hook
_dotfiles_reset_mouse() {
    printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l'
}
add-zsh-hook precmd _dotfiles_reset_mouse

# fzf-powered history search widget (bound to Ctrl+R)
# Only registered when fzf is available — fzf is a full-tier package and
# may not be present on core profile machines.
if command -v fzf &>/dev/null; then
    function fzf-history-search() {
        local selected
        selected=$(fc -l 1 | fzf --height 20 --reverse --margin=0,1 \
            --bind ctrl-f:page-down,ctrl-b:page-up \
            --marker='✚' --pointer='▶' --prompt='❯ ' --no-separator --scrollbar='█' \
            --color='bg+:#262626,fg+:#dadada,hl:#f95189,hl+:#f95189' \
            --color='border:#303030,info:#cfcfb0,header:#80a0ff,spinner:#36c692' \
            --color='prompt:#87afff,pointer:#ff5189,marker:#f09479')
        if [[ -n "$selected" ]]; then
            local num
            num=$(echo "$selected" | awk '{print $1}')
            [[ -n "$num" ]] && zle vi-fetch-history -n "$num"
        fi
        zle reset-prompt
    }

    zle -N fzf-history-search
    bindkey '^R' fzf-history-search
fi

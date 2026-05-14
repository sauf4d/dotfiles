#!/usr/bin/env zsh

PKG_NAME="fzf"
PKG_DESC="A command-line fuzzy finder"

pkg_init() {
    export FZF_DEFAULT_COMMAND="fd --type f"
    export FZF_DEFAULT_OPTS="--height 75% --multi --reverse --margin=0,1 \
        --bind ctrl-f:page-down,ctrl-b:page-up,ctrl-/:toggle-preview \
        --bind pgdn:preview-page-down,pgup:preview-page-up \
        --preview 'bat --line-range :100 {}' \
        --marker='✚' --pointer='▶' --prompt='❯ ' --no-separator --scrollbar='█' \
        --color bg+:#262626,fg+:#dadada,hl:#f09479,hl+:#f09479 \
        --color border:#303030,info:#cfcfb0,header:#80a0ff,spinner:#36c692 \
        --color prompt:#87afff,pointer:#ff5189,marker:#f09479"
    export FZF_CTRL_T_COMMAND="rg --files --hidden --follow --glob '!.git/*'"
    export FZF_CTRL_T_OPTS="--preview 'bat --line-range :100 {}'"
    export FZF_ALT_C_COMMAND="fd --type d"
    # eza is a full-tier package (installed alongside fzf); guard defensively
    if command -v eza &>/dev/null; then
        export FZF_ALT_C_OPTS="--preview 'eza --tree --level 2 --group-directories-first {}'"
    fi
}

init_package_template "$PKG_NAME"

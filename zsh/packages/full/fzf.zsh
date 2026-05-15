#!/usr/bin/env zsh

PKG_NAME="fzf"
PKG_DESC="A command-line fuzzy finder"

pkg_init() {
    export FZF_DEFAULT_COMMAND="fd --type f"
    export FZF_DEFAULT_OPTS="--height 75% --multi --reverse --margin=0,1 \
        --bind ctrl-f:page-down,ctrl-b:page-up,ctrl-/:toggle-preview \
        --bind pgdn:preview-page-down,pgup:preview-page-up \
        --marker='✚' --pointer='▶' --prompt='❯ ' --no-separator --scrollbar='█' \
        --color bg+:#262626,fg+:#dadada,hl:#f09479,hl+:#f09479 \
        --color border:#303030,info:#cfcfb0,header:#80a0ff,spinner:#36c692 \
        --color prompt:#87afff,pointer:#ff5189,marker:#f09479"
    # Ctrl+R — history fuzzy search, no preview (commands are self-describing)
    export FZF_CTRL_R_OPTS="--no-preview"
    # Ctrl+T — file search; bat theme/color come from ~/.config/bat/config
    export FZF_CTRL_T_COMMAND="rg --files --hidden --follow --glob '!.git/*'"
    export FZF_CTRL_T_OPTS="--preview 'bat --line-range :100 {}'"
    # Alt+C  — directory jump with eza tree preview
    export FZF_ALT_C_COMMAND="fd --type d"
    if command -v eza &>/dev/null; then
        export FZF_ALT_C_OPTS="--preview 'eza --tree --level 2 --group-directories-first {}'"
    fi

    # Wire up keybindings — must come AFTER env vars so the bindings pick
    # up FZF_CTRL_T_COMMAND, FZF_ALT_C_COMMAND, etc.
    if fzf --zsh &>/dev/null; then
        eval "$(fzf --zsh)"
    else
        local _fzf_shell="$(brew --prefix fzf 2>/dev/null)/shell"
        [[ -f "$_fzf_shell/key-bindings.zsh" ]] && source "$_fzf_shell/key-bindings.zsh"
        [[ -f "$_fzf_shell/completion.zsh"   ]] && source "$_fzf_shell/completion.zsh"
    fi

    # macOS: Option+C sends ç instead of the ESC-c sequence fzf expects for Alt+C.
    [[ "$(uname)" == "Darwin" ]] && bindkey 'ç' fzf-cd-widget 2>/dev/null
}

pkg_doctor() {
    local issues=0
    if command -v fzf &>/dev/null; then
        local ver
        ver="$(fzf --version 2>/dev/null | head -1)"
        _dotfiles_log_result "fzf" "${ver:-installed}"
    else
        _dotfiles_log_result "fzf" "NOT FOUND"
        ((issues++))
    fi
    return $issues
}

pkg_clean() {
    # fzf has no runtime cache or state
    return 0
}

pkg_uninstall() {
    local pkg_mgr
    pkg_mgr="$(dotfiles_pkg_manager)"

    local uninstall_cmd=""
    case "$pkg_mgr" in
        brew)   uninstall_cmd="brew uninstall fzf" ;;
        apt)    uninstall_cmd="sudo apt remove -y fzf" ;;
        dnf)    uninstall_cmd="sudo dnf remove -y fzf" ;;
        yum)    uninstall_cmd="sudo yum remove -y fzf" ;;
        pacman) uninstall_cmd="sudo pacman -Rs --noconfirm fzf" ;;
        zypper) uninstall_cmd="sudo zypper remove -y fzf" ;;
        *)
            if ! command -v fzf &>/dev/null; then
                return 0
            fi
            [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
                "Unknown package manager — cannot auto-uninstall fzf" \
                "$(command -v fzf 2>/dev/null || echo 'unknown')" \
                "Remove fzf via your system package manager" \
                > "$_PKG_UNINSTALL_REPORT_FILE"
            return 1
            ;;
    esac

    if ! eval "$uninstall_cmd" 2>/dev/null; then
        [[ -n "${_PKG_UNINSTALL_REPORT_FILE:-}" ]] && printf 'ERROR=%s\nREMAINING=%s\nRECOVERY=%s\n' \
            "$uninstall_cmd failed" \
            "$(command -v fzf 2>/dev/null || echo 'unknown')" \
            "run: $uninstall_cmd" \
            > "$_PKG_UNINSTALL_REPORT_FILE"
        return 1
    fi
    return 0
}

init_package_template "$PKG_NAME"

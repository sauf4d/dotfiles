#!/usr/bin/env zsh

# =============================================================================
# Package lifecycle engine — check, warn, install, init
# =============================================================================

# Re-source guard
[[ -n "${_DOTFILES_INSTALLER_LOADED:-}" ]] && return 0
readonly _DOTFILES_INSTALLER_LOADED=1

# Shared logging helpers (POSIX-compatible, also sourced by bin/dotfiles)
source "${DOTFILES_ROOT:-$HOME/.dotfiles}/zsh/lib/_log.sh"

# -----------------------------------------------------------------------------
# Package check
# -----------------------------------------------------------------------------
is_package_installed() {
    local cmd_path
    cmd_path=$(command -v "$1" 2>/dev/null)
    [[ -n "$cmd_path" && -x "$cmd_path" ]]
}

# -----------------------------------------------------------------------------
# OS-aware package installer (delegates to detected package manager)
# Falls back to pkg_install_fallback() if distro is unknown
# -----------------------------------------------------------------------------
_dotfiles_install_package() {
    local package_name="$1"
    local package_desc="${2:-}"
    local pkg_mgr
    pkg_mgr="$(dotfiles_pkg_manager)"

    _dotfiles_log_info "Installing ${package_name} via ${pkg_mgr}..."

    local success=false
    case "$pkg_mgr" in
        brew)
            brew install "$package_name" && success=true ;;
        apt)
            sudo apt update -qq && sudo apt install -y "$package_name" && success=true ;;
        dnf)
            sudo dnf install -y "$package_name" && success=true ;;
        yum)
            sudo yum install -y "$package_name" && success=true ;;
        pacman)
            sudo pacman -S --noconfirm "$package_name" && success=true ;;
        zypper)
            sudo zypper install -y "$package_name" && success=true ;;
        pkg)
            sudo pkg install -y "$package_name" && success=true ;;
        unknown)
            if typeset -f pkg_install_fallback >/dev/null; then
                _dotfiles_log_info "No known package manager. Trying pkg_install_fallback..."
                pkg_install_fallback && success=true
            else
                local distro
                distro="$(dotfiles_distro)"
                _dotfiles_log_error "Cannot auto-install ${package_name} on ${distro}. Install manually, then re-run."
                return 1
            fi ;;
    esac

    if [[ "$success" == "true" ]]; then
        _dotfiles_log_success "${package_name} installed successfully"
        return 0
    else
        _dotfiles_log_error "Failed to install ${package_name}"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# _dotfiles_check_installed — unified check using PKG_CHECK_FUNC or binary
# -----------------------------------------------------------------------------
_dotfiles_check_installed() {
    local pkg_cmd="$1"
    if [[ -n "${PKG_CHECK_FUNC:-}" ]] && typeset -f "${PKG_CHECK_FUNC}" >/dev/null; then
        "${PKG_CHECK_FUNC}"
    elif [[ -n "$pkg_cmd" ]]; then
        is_package_installed "$pkg_cmd"
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Package lifecycle orchestrator
# Usage: init_package_template "$PKG_NAME"
# Reads package variables: PKG_NAME, PKG_DESC, PKG_CMD, PKG_CHECK_FUNC
# Calls hook functions if defined: pkg_pre_install, pkg_install,
#   pkg_install_fallback, pkg_post_install, pkg_init
# -----------------------------------------------------------------------------
_dotfiles_cleanup_package_hooks() {
    # Properly cleanup hooks with unfunction; silence any Zsh errors
    local h
    for h in pkg_pre_install pkg_install pkg_install_fallback pkg_post_install pkg_init; do
        unfunction "$h" 2>/dev/null
    done
    unset PKG_NAME PKG_DESC PKG_CMD PKG_CHECK_FUNC 2>/dev/null
}

init_package_template() {
    # Synchronize initial values
    local package_name="${1:-${PKG_NAME:-}}"
    local package_desc="${PKG_DESC:-}"
    local package_command="${PKG_CMD:-$package_name}"

    if [[ -z "$package_name" ]]; then
        _dotfiles_log_error "Package name not provided"
        _dotfiles_cleanup_package_hooks
        return 1
    fi

    _dotfiles_log_debug "Checking ${package_name}..."

    # Check if installed
    if _dotfiles_check_installed "$package_command"; then
        _dotfiles_log_debug "${package_name} is installed ✓"
        if typeset -f pkg_init >/dev/null; then
            pkg_init || {
                _dotfiles_log_error "Failed to initialize ${package_name}"
                _dotfiles_cleanup_package_hooks
                return 1
            }
        fi
        _dotfiles_log_success "${package_name} initialized"
        _dotfiles_cleanup_package_hooks
        return 0
    fi

    # Not installed — warn on normal startup, full install when DOTFILES_INSTALL=true
    if [[ "${DOTFILES_INSTALL:-false}" != "true" ]]; then
        _dotfiles_log_warning "${package_name} not installed — run: dotfiles install"
        _dotfiles_cleanup_package_hooks
        return 0
    fi

    # Full install flow (DOTFILES_INSTALL=true)
    echo
    _dotfiles_log_warning "${package_name} not found — ${package_desc}"

    # Run pre-install hook
    if typeset -f pkg_pre_install >/dev/null; then
        pkg_pre_install || {
            _dotfiles_log_error "Pre-install failed for ${package_name}"
            _dotfiles_cleanup_package_hooks
            return 1
        }
        # Re-sync EVERYTHING in case pre-install hook modified parameters
        package_name="${PKG_NAME:-$package_name}"
        package_desc="${PKG_DESC:-$package_desc}"
        package_command="${PKG_CMD:-$package_name}"
    fi

    _dotfiles_log_info "Attempting to install ${package_name}..."

    if typeset -f pkg_install >/dev/null; then
        pkg_install || {
            _dotfiles_log_error "Installation failed for ${package_name}"
            _dotfiles_cleanup_package_hooks
            return 1
        }
    else
        _dotfiles_install_package "$package_name" "$package_desc" || {
            _dotfiles_log_error "Installation failed for ${package_name}"
            _dotfiles_cleanup_package_hooks
            return 1
        }
    fi

    if typeset -f pkg_post_install >/dev/null; then
        pkg_post_install || _dotfiles_log_warning "Post-install failed for ${package_name}"
    fi

    # Re-verify after install (post-install might have created symlinks)
    if ! _dotfiles_check_installed "$package_command"; then
        _dotfiles_log_error "${package_name} installation completed but not found"
        _dotfiles_cleanup_package_hooks
        return 1
    fi

    if typeset -f pkg_init >/dev/null; then
        pkg_init || {
            _dotfiles_log_error "Failed to initialize ${package_name}"
            _dotfiles_cleanup_package_hooks
            return 1
        }
    fi

    _dotfiles_log_success "${package_name} installed and initialized ✓"
    echo

    _dotfiles_cleanup_package_hooks
    return 0
}

# -----------------------------------------------------------------------------
# Utility functions
# -----------------------------------------------------------------------------
ensure_directory() {
    [[ -d "$1" ]] || mkdir -p "$1" 2>/dev/null
}

copy_if_missing() {
    [[ -f "$1" && ! -f "$2" ]] && cp "$1" "$2" 2>/dev/null
    return 0
}

create_symlink() {
    [[ ! -e "$2" && -e "$1" ]] && ln -sf "$1" "$2" 2>/dev/null
    return 0
}

# Create a ~/.local/bin compat symlink (Linux-only, for Debian/Ubuntu binary-name quirks)
# Usage: _dotfiles_linux_compat_symlink "original_binary" "desired_name"
# Example: _dotfiles_linux_compat_symlink "batcat" "bat"
_dotfiles_linux_compat_symlink() {
    local original="$1" alias_name="$2"
    [[ "$(dotfiles_os)" == "linux" ]] || return 0
    command -v "$original" &>/dev/null && ! command -v "$alias_name" &>/dev/null || return 0
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v "$original")" "$HOME/.local/bin/$alias_name"
}

# -----------------------------------------------------------------------------
# Safe installer helpers — download to temp, verify SHA256, then execute
# Never pipe curl directly to bash.
# -----------------------------------------------------------------------------

# Verify SHA256 of a file. Works on macOS (shasum) and Linux (sha256sum).
_dotfiles_verify_sha256() {
    local file="$1" expected="$2"
    local actual=""
    if command -v sha256sum &>/dev/null; then
        actual="$(sha256sum "$file" | awk '{print $1}')"
    elif command -v shasum &>/dev/null; then
        actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    else
        _dotfiles_log_error "No sha256sum or shasum found — cannot verify installer integrity"
        return 1
    fi
    if [[ "$actual" != "$expected" ]]; then
        _dotfiles_log_error "Checksum mismatch — possible tampering or corrupted download"
        _dotfiles_log_error "  Expected: $expected"
        _dotfiles_log_error "  Got:      $actual"
        return 1
    fi
    _dotfiles_log_debug "Checksum OK: $file"
}

# Download URL to a temp file, verify SHA256, run with bash.
# Usage: _dotfiles_safe_run_installer <url> <sha256> [-- script_args...]
_dotfiles_safe_run_installer() {
    local url="$1" expected_sha256="$2"
    shift 2
    local tmp
    tmp="$(mktemp /tmp/dotfiles-installer.XXXXXX)" || { _dotfiles_log_error "mktemp failed"; return 1; }
    curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$tmp" || {
        rm -f "$tmp"; _dotfiles_log_error "Download failed: $url"; return 1
    }
    _dotfiles_verify_sha256 "$tmp" "$expected_sha256" || { rm -f "$tmp"; return 1; }
    bash "$tmp" "$@"; local rc=$?; rm -f "$tmp"; return $rc
}

# Clone a git repo at a pinned tag/branch and verify the resulting HEAD commit SHA.
# Usage: _dotfiles_safe_git_clone <url> <tag_or_branch> <expected_commit_sha> <dest>
# For repos without tags, pass the full 40-char commit SHA as tag_or_branch too.
_dotfiles_safe_git_clone() {
    local url="$1" ref="$2" expected_sha="$3" dest="$4"

    if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
        # Bare commit SHA: partial clone (all commits/trees, no blobs) then checkout.
        # Much faster than a full clone; blobs are fetched lazily on checkout.
        git clone --filter=blob:none --no-checkout "$url" "$dest" || {
            rm -rf "$dest"; _dotfiles_log_error "Clone failed: $url"; return 1
        }
        git -C "$dest" checkout "$ref" || {
            rm -rf "$dest"; _dotfiles_log_error "Checkout $ref failed for $url"; return 1
        }
    else
        # Tag or branch: shallow clone
        git clone --branch "$ref" --depth 1 "$url" "$dest" || {
            rm -rf "$dest"; _dotfiles_log_error "Clone failed: $url at $ref"; return 1
        }
    fi

    local actual_sha
    actual_sha="$(git -C "$dest" rev-parse HEAD 2>/dev/null)" || {
        rm -rf "$dest"; _dotfiles_log_error "Could not read HEAD SHA for $dest"; return 1
    }
    if [[ "$actual_sha" != "$expected_sha" ]]; then
        rm -rf "$dest"
        _dotfiles_log_error "Commit SHA mismatch for $url at $ref"
        _dotfiles_log_error "  Expected: $expected_sha"
        _dotfiles_log_error "  Got:      $actual_sha"
        return 1
    fi
    _dotfiles_log_debug "Verified clone: $url ($actual_sha)"
}

# Same as above but executes with sudo bash (for system-wide installs).
_dotfiles_safe_sudo_run_installer() {
    local url="$1" expected_sha256="$2"
    shift 2
    local tmp
    tmp="$(mktemp /tmp/dotfiles-installer.XXXXXX)" || { _dotfiles_log_error "mktemp failed"; return 1; }
    curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$tmp" || {
        rm -f "$tmp"; _dotfiles_log_error "Download failed: $url"; return 1
    }
    _dotfiles_verify_sha256 "$tmp" "$expected_sha256" || { rm -f "$tmp"; return 1; }
    sudo bash "$tmp" "$@"; local rc=$?; rm -f "$tmp"; return $rc
}

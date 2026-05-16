# =============================================================================
# pwsh/lib/Log.ps1 — two-tier logging (mirror of zsh/lib/log.sh)
#
# Tier 1 — always-print (Write-DotfilesStep/Detail/Result/Summary/Warning/
#                        Error/Hint). Used by CLI commands; visible without -v.
# Tier 2 — verbose-only (Write-DotfilesDebug/Info/Dim/Success). Gated on
#                        $env:DOTFILES_VERBOSE; reserved for shell startup
#                        and package hooks. Silent unless -v / verbose=true.
# =============================================================================

# Color helpers — auto-disable when host doesn't support ANSI or $env:NO_COLOR is set.
$script:DotfilesUseColor = $true
if ($env:NO_COLOR) { $script:DotfilesUseColor = $false }
if (-not [Environment]::UserInteractive) { $script:DotfilesUseColor = $false }

function _Color {
    param([string]$Code, [string]$Text)
    if ($script:DotfilesUseColor) { "$([char]27)[${Code}m${Text}$([char]27)[0m" } else { $Text }
}

function _IsVerbose { return ($env:DOTFILES_VERBOSE -eq 'true') }
function _IsQuiet   { return ($env:DOTFILES_QUIET   -eq 'true') }

# ── Tier 1 — CLI output ──────────────────────────────────────────────────────
function Write-DotfilesStep {
    param([Parameter(Mandatory)][string]$Message)
    if (_IsQuiet) { return }
    Write-Host (_Color '1;36' "→ $Message")
}

function Write-DotfilesDetail {
    param([Parameter(Mandatory)][string]$Message)
    if (_IsQuiet) { return }
    Write-Host "  $(_Color '2' '•') $Message"
}

function Write-DotfilesResult {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )
    if (_IsQuiet) { return }
    Write-Host ("  {0}: {1}" -f $Label, $Value)
}

function Write-DotfilesSummary {
    param([Parameter(Mandatory)][string]$Message)
    if (_IsQuiet) { return }
    Write-Host (_Color '32' "✓ $Message")
}

function Write-DotfilesWarning {
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Error.WriteLine((_Color '33' "⚠  $Message"))
}

function Write-DotfilesError {
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Error.WriteLine((_Color '1;31' "✗ $Message"))
}

function Write-DotfilesHint {
    param([Parameter(Mandatory)][string]$Message)
    [Console]::Error.WriteLine("  $(_Color '90' "hint: $Message")")
}

# ── Tier 2 — verbose-only ────────────────────────────────────────────────────
function Write-DotfilesDebug {
    param([Parameter(Mandatory)][string]$Message, [string]$Scope = $env:DOTFILES_LOG_SCOPE)
    if (-not (_IsVerbose)) { return }
    $ts = (Get-Date -Format 'HH:mm:ss.fff')
    $prefix = if ($Scope) { "[$ts] [$Scope]" } else { "[$ts]" }
    [Console]::Error.WriteLine((_Color '90' "$prefix $Message"))
}

function Write-DotfilesInfo {
    param([Parameter(Mandatory)][string]$Message)
    if (-not (_IsVerbose)) { return }
    Write-Host (_Color '37' "• $Message")
}

function Write-DotfilesDim {
    param([Parameter(Mandatory)][string]$Message)
    if (-not (_IsVerbose)) { return }
    Write-Host (_Color '90' "  $Message")
}

function Write-DotfilesSuccess {
    param([Parameter(Mandatory)][string]$Message)
    if (-not (_IsVerbose)) { return }
    Write-Host (_Color '32' "✓ $Message")
}

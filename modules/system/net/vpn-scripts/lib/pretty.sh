#!/usr/bin/env bash
# pretty.sh — unified terminal aesthetics for all shell scripts
# Source: https://github.com/anomalyco/cfg (CC0 / public domain)
#
# Usage:
#   source scripts/lib/pretty.sh
#   pretty::header  "Deploying system_description"
#   pretty::phase   "Installing packages" 3 10
#   pretty::ok      "All 65 states valid"
#   pretty::fail    "zapret2.sls: missing dependency"
#   pretty::warn    "gopass locked — dotfiles skipped"
#   pretty::info    "Log: logs/system_description-20260513.log"
#   pretty::section "Network Configuration"
#   pretty::progress 67 100
#   pretty::spinner "Pulling ollama image" & _spinner_pid=$!
#       ...slow work...
#   kill $_spinner_pid 2>/dev/null; pretty::ok "Image pulled"

set -uo pipefail

# ── Capability detection ────────────────────────────────────────────────
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    _PRETTY_TTY=1
else
    _PRETTY_TTY=0
fi

_HAS_UTF8=0
if [[ "${LANG:-}" == *UTF-8* || "${LC_ALL:-}" == *UTF-8* || "${LC_CTYPE:-}" == *UTF-8* ]]; then
    _HAS_UTF8=1
fi

# ── Color palette (256-color, fallback to 16) ───────────────────────────
if [[ $_PRETTY_TTY -eq 1 ]]; then
    # 256-color mode
    _C_RESET='\033[0m'
    _C_BOLD='\033[1m'
    _C_DIM='\033[2m'
    _C_ITALIC='\033[3m'
    _C_UNDERLINE='\033[4m'

    # 16-color fallbacks (always work)
    _C_RED='\033[31m'
    _C_GREEN='\033[32m'
    _C_YELLOW='\033[33m'
    _C_BLUE='\033[34m'
    _C_MAGENTA='\033[35m'
    _C_CYAN='\033[36m'
    _C_WHITE='\033[37m'

    _C_RED_BOLD='\033[1;31m'
    _C_GREEN_BOLD='\033[1;32m'
    _C_YELLOW_BOLD='\033[1;33m'
    _C_BLUE_BOLD='\033[1;34m'
    _C_CYAN_BOLD='\033[1;36m'
    _C_WHITE_BOLD='\033[1;37m'

    _C_BG_RED='\033[41m'
    _C_BG_GREEN='\033[42m'
    _C_BG_BLUE='\033[44m'
    _C_BG_DARK='\033[48;5;236m'

    _C_MAGENTA_BOLD='\033[1;35m'
    _C_GREY='\033[90m'
    _C_GREY_BOLD='\033[1;90m'
else
    # No color
    _C_RESET='' ; _C_BOLD='' ; _C_DIM='' ; _C_ITALIC='' ; _C_UNDERLINE=''
    _C_RED='' ; _C_GREEN='' ; _C_YELLOW='' ; _C_BLUE='' ; _C_MAGENTA='' ; _C_CYAN='' ; _C_WHITE=''
    _C_RED_BOLD='' ; _C_GREEN_BOLD='' ; _C_YELLOW_BOLD='' ; _C_BLUE_BOLD='' ; _C_CYAN_BOLD='' ; _C_WHITE_BOLD=''
    _C_BG_RED='' ; _C_BG_GREEN='' ; _C_BG_BLUE='' ; _C_BG_DARK=''
    _C_MAGENTA_BOLD='' ; _C_GREY='' ; _C_GREY_BOLD=''
fi

# ── Icons ────────────────────────────────────────────────────────────────
if [[ $_HAS_UTF8 -eq 1 ]]; then
    _I_OK='✓'
    _I_FAIL='✗'
    _I_WARN='⚠'
    _I_INFO='●'
    _I_PHASE='▶'
    _I_CLOCK='⏳'
    _I_ARROW='→'
    _I_STAR='★'
    _I_BULLET='•'
    _I_BOX_V='║'
    _I_BOX_H='═'
    _I_BOX_TL='╔'
    _I_BOX_TR='╗'
    _I_BOX_BL='╚'
    _I_BOX_BR='╝'
    _I_SECTION='─'
else
    _I_OK='OK'
    _I_FAIL='!!'
    _I_WARN='*'
    _I_INFO='>'
    _I_PHASE='>>'
    _I_CLOCK='...'
    _I_ARROW='->'
    _I_STAR='*'
    _I_BULLET='-'
    _I_BOX_V='|'
    _I_BOX_H='='
    _I_BOX_TL='+'
    _I_BOX_TR='+'
    _I_BOX_BL='+'
    _I_BOX_BR='+'
    _I_SECTION='-'
fi

# Braille spinner frames (UTF-8) / basic spinner (ASCII)
if [[ $_HAS_UTF8 -eq 1 ]]; then
    _SPINNER_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
else
    _SPINNER_FRAMES=('/' '-' '\' '|')
fi

# ── Internal helpers ─────────────────────────────────────────────────────
_pretty_width() {
    local w
    w=$(tput cols 2>/dev/null) || w=80
    echo "${w:-80}"
}

_pretty_repeat() {
    local char="$1" count="$2"
    local out=""
    local i
    for (( i = 0; i < count; i++ )); do
        out+="$char"
    done
    printf '%s' "$out"
}

_pretty_pad_right() {
    local text="$1" width="$2"
    local text_len=${#text}
    if (( text_len >= width )); then
        printf '%s' "$text"
    else
        printf '%s%*s' "$text" $((width - text_len)) ''
    fi
}

_pretty_elapsed() {
    local start=$1
    local now elapsed
    now=$(date +%s%N 2>/dev/null || date +%s)
    if [[ "$now" == *N ]]; then
        elapsed=$(( (now - start) / 1000000000 ))
    else
        elapsed=$(( now - start ))
    fi
    if (( elapsed < 60 )); then
        printf '%ds' "$elapsed"
    elif (( elapsed < 3600 )); then
        printf '%dm%ds' $((elapsed/60)) $((elapsed%60))
    else
        printf '%dh%dm' $((elapsed/3600)) $(((elapsed%3600)/60))
    fi
}

#   dim text — low-contrast output
pretty::dim() {
    printf '%b%s%b\n' "${_C_DIM}" "$*" "${_C_RESET}"
}

#   badge "STATUS" — colored inline badge (OK=green, FAIL=red, WARN=yellow, INFO=blue)
pretty::badge() {
    local s="${1:-}"
    case "$(printf '%s' "$s" | tr '[:lower:]' '[:upper:]')" in
        OK|PASS|SUCCESS|ACTIVE|ENABLED)
            printf '%b %s %b' "${_C_BG_GREEN}${_C_WHITE_BOLD}" "$s" "${_C_RESET}" ;;
        FAIL|ERROR|FAILED)
            printf '%b %s %b' "${_C_BG_RED}${_C_WHITE_BOLD}" "$s" "${_C_RESET}" ;;
        WARN|SKIP|SKIPPED|PENDING)
            printf '%b %s %b' "${_C_YELLOW_BOLD}" "$s" "${_C_RESET}" ;;
        INFO|NOTE)
            printf '%b %s %b' "${_C_BLUE_BOLD}" "$s" "${_C_RESET}" ;;
        CHANGED|UPDATED|MODIFIED)
            printf '%b %s %b' "${_C_CYAN_BOLD}" "$s" "${_C_RESET}" ;;
        *)
            printf '%b %s %b' "${_C_GREY_BOLD}" "$s" "${_C_RESET}" ;;
    esac
}

# ── Public API ───────────────────────────────────────────────────────────

# ╔══════════════════════════════════════════╗
# ║  header text                            ║
# ╚══════════════════════════════════════════╝
pretty::header() {
    local text="$*"
    local width=$(_pretty_width)
    local inner_width=$((width - 4))
    local text_len=${#text}
    local pad_left=$(( (inner_width - text_len) / 2 ))
    local pad_right=$(( inner_width - text_len - pad_left ))
    (( pad_left < 0 )) && pad_left=0
    (( pad_right < 0 )) && pad_right=0

    printf '%b%s%b' "${_C_MAGENTA_BOLD}" "${_I_BOX_TL}" "${_C_CYAN_BOLD}"
    _pretty_repeat "${_I_BOX_H}" $((width - 2))
    printf '%b%s%b\n' "${_C_MAGENTA_BOLD}" "${_I_BOX_TR}" "${_C_RESET}"
    printf '%b%s%b' "${_C_CYAN_BOLD}" "${_I_BOX_V}" "${_C_RESET}"
    printf '%s' ' '
    _pretty_repeat ' ' "$pad_left"
    printf '%b%s%b' "${_C_WHITE_BOLD}" "$text" "${_C_RESET}"
    _pretty_repeat ' ' "$pad_right"
    printf ' %b%s%b\n' "${_C_CYAN_BOLD}" "${_I_BOX_V}" "${_C_RESET}"
    printf '%b%s%b' "${_C_CYAN_BOLD}" "${_I_BOX_BL}" "${_C_MAGENTA_BOLD}"
    _pretty_repeat "${_I_BOX_H}" $((width - 2))
    printf '%b%s%b\n' "${_C_MAGENTA_BOLD}" "${_I_BOX_BR}" "${_C_RESET}"
}

#   ✓ message
pretty::ok() {
    printf '%b %s %b%s%b\n' "${_C_GREEN_BOLD}" "${_I_OK}" "${_C_GREEN}" "$*" "${_C_RESET}"
}

#   ✗ message
pretty::fail() {
    printf '%b %s %b%s%b\n' "${_C_RED_BOLD}" "${_I_FAIL}" "${_C_RED}" "$*" "${_C_RESET}"
}

#   ⚠ message
pretty::warn() {
    printf '%b %s %b%s%b\n' "${_C_YELLOW_BOLD}" "${_I_WARN}" "${_C_YELLOW}" "$*" "${_C_RESET}"
}

#   ● message (blue bullet, white text)
pretty::info() {
    printf '%b %s %b%s%b\n' "${_C_CYAN_BOLD}" "${_I_INFO}" "${_C_RESET}" "$*" "${_C_RESET}"
}

#   ▶ [N/T] message
pretty::phase() {
    local n="${1:-?}" total="${2:-?}" msg="${3:-}"
    if [[ -n "$msg" ]]; then
        printf '%b %s %b[%s/%s]%b %s%b\n' "${_C_CYAN_BOLD}" "${_I_PHASE}" "${_C_YELLOW}" "$n" "$total" "${_C_CYAN_BOLD}" "$msg" "${_C_RESET}"
    else
        printf '%b %s %s%b\n' "${_C_CYAN_BOLD}" "${_I_PHASE}" "${1:-}" "${_C_RESET}"
    fi
}

# ── section ────────────────────────────────────────────────────────
pretty::section() {
    local text="$*"
    local width=$(_pretty_width)
    local remain=$((width - ${#text} - 6))
    (( remain < 2 )) && remain=2
    printf '%b%s %b%s%b ' "${_C_GREY_BOLD}" "$(_pretty_repeat "${_I_SECTION}" 3)" "${_C_CYAN_BOLD}" "$text" "${_C_GREY_BOLD}"
    _pretty_repeat "${_I_SECTION}" "$remain"
    printf '%b\n' "${_C_RESET}"
}

# ████████░░░░  67%  (67/100)
pretty::progress() {
    local current="${1:-0}" total="${2:-100}"
    local width=30
    local pct=$(( current * 100 / (total ? total : 1) ))
    local filled=$(( width * current / (total ? total : 1) ))
    local empty=$(( width - filled ))

    printf '\r%b  ' "${_C_RESET}"
    printf '%b' "${_C_GREEN}"
    _pretty_repeat '█' "$filled"
    printf '%b' "${_C_GREY}"
    _pretty_repeat '░' "$empty"
    printf ' %b%3d%%%b  (%d/%d)' "${_C_WHITE_BOLD}" "$pct" "${_C_RESET}" "$current" "$total"
}

# Spinner subprocess — call with & and kill when done
# Usage: pretty::spinner "Loading..." & _pid=$!; ...; kill $_pid 2>/dev/null
pretty::spinner() {
    local msg="${1:-working}"
    local i=0
    local start
    start=$(date +%s%N 2>/dev/null || date +%s)
    while true; do
        printf '\r%b %s %b%s%b  %s' \
            "${_C_CYAN_BOLD}" "${_SPINNER_FRAMES[$i]}" \
            "${_C_WHITE}" "$msg" "${_C_RESET}" \
            "$(_pretty_elapsed "$start")"
        i=$(( (i + 1) % ${#_SPINNER_FRAMES[@]} ))
        sleep 0.1
    done
}

# ── Summary blocks ───────────────────────────────────────────────────────

# Box with count: "━━━ Results: 727 passed, 2 failed ━━━"
pretty::summary_line() {
    local passed="$1" failed="$2" label="${3:-Results}"
    local width=$(_pretty_width)
    local text
    text="${label}: "
    if [[ $failed -gt 0 ]]; then
        text+="${_C_GREEN_BOLD}${passed} passed${_C_BOLD}, ${_C_RED_BOLD}${failed} failed"
    else
        text+="${_C_GREEN_BOLD}${passed} passed"
    fi
    local text_len=${#text}
    # Strip ANSI for width calc
    local plain
    plain=$(printf '%s' "$text" | sed 's/\x1b\[[0-9;]*m//g')
    local pad=$(( (width - ${#plain} - 2) / 2 ))
    (( pad < 0 )) && pad=0

    printf '%b' "${_C_BOLD}"
    _pretty_repeat "${_I_SECTION}" "$pad"
    printf ' %b%s %b' "${_C_RESET}${_C_BOLD}" "$text" "${_C_BOLD}"
    _pretty_repeat "${_I_SECTION}" "$pad"
    printf '%b\n' "${_C_RESET}"
}

# Print a service status line:  ● service_name  active
pretty::service_status() {
    local name="$1" _st="$2"
    case "$_st" in
        active|running|healthy|enabled)
            printf '%b %s %b%-40s%b %bactive%b\n' \
                "${_C_GREEN_BOLD}" "${_I_OK}" "${_C_GREEN}" "$name" "${_C_RESET}" "${_C_GREEN}" "${_C_RESET}" ;;
        failed|error|unhealthy)
            printf '%b %s %b%-40s%b %bfailed%b\n' \
                "${_C_RED_BOLD}" "${_I_FAIL}" "${_C_RED}" "$name" "${_C_RESET}" "${_C_RED}" "${_C_RESET}" ;;
        inactive|disabled|stopped|dead)
            printf '%b %s %b%-40s%b %b%s%b\n' \
                "${_C_GREY}" "${_I_BULLET}" "${_C_RESET}" "$name" "${_C_RESET}" "${_C_DIM}" "$_st" "${_C_RESET}" ;;
        *)
            printf '%b %s %b%-40s%b %s\n' \
                "${_C_YELLOW}" "${_I_WARN}" "${_C_RESET}" "$name" "${_C_RESET}" "$_st" ;;
    esac
}

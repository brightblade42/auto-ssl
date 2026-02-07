#!/usr/bin/env bash
# auto-ssl UI utilities
# Wrappers for gum with fallback to plain bash

# Source common for colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
[[ -f "${SCRIPT_DIR}/common.sh" ]] && source "${SCRIPT_DIR}/common.sh"

#--------------------------------------------------
# Gum detection
#--------------------------------------------------

_has_gum() {
    command -v gum &>/dev/null
}

#--------------------------------------------------
# Spinner / Progress
#--------------------------------------------------

# Run a command with a spinner
# Usage: ui_spin "Message" command arg1 arg2
ui_spin() {
    local message="$1"
    shift
    
    if _has_gum; then
        gum spin --spinner dot --title "$message" -- "$@"
    else
        echo -n "$message... "
        if "$@" >/dev/null 2>&1; then
            echo "done"
        else
            echo "failed"
            return 1
        fi
    fi
}

# Show a spinner while waiting for a condition
# Usage: ui_spin_until "Message" condition_command
ui_spin_until() {
    local message="$1"
    local condition="$2"
    local timeout="${3:-30}"
    
    local elapsed=0
    echo -n "$message... "
    
    while ! eval "$condition" 2>/dev/null; do
        sleep 1
        ((elapsed++))
        if ((elapsed >= timeout)); then
            echo "timeout"
            return 1
        fi
    done
    
    echo "done"
}

#--------------------------------------------------
# Input
#--------------------------------------------------

# Prompt for text input
# Usage: ui_input "Prompt" [default] [placeholder]
ui_input() {
    local prompt="$1"
    local default="${2:-}"
    local placeholder="${3:-}"
    local value
    
    if _has_gum; then
        local args=(--prompt "$prompt ")
        [[ -n "$default" ]] && args+=(--value "$default")
        [[ -n "$placeholder" ]] && args+=(--placeholder "$placeholder")
        value=$(gum input "${args[@]}")
    else
        if [[ -n "$default" ]]; then
            read -rp "$prompt [$default]: " value
            value="${value:-$default}"
        else
            read -rp "$prompt: " value
        fi
    fi
    
    echo "$value"
}

# Prompt for password (hidden input)
# Usage: ui_password "Prompt"
ui_password() {
    local prompt="$1"
    local value
    
    if _has_gum; then
        value=$(gum input --password --prompt "$prompt ")
    else
        read -rsp "$prompt: " value
        echo >&2  # Newline after hidden input
    fi
    
    echo "$value"
}

# Prompt for multiline text
# Usage: ui_text "Prompt" [default]
ui_text() {
    local prompt="$1"
    local default="${2:-}"
    local value
    
    if _has_gum; then
        value=$(gum write --placeholder "$prompt" --value "$default")
    else
        echo "$prompt (Ctrl+D to finish):"
        value=$(cat)
    fi
    
    echo "$value"
}

#--------------------------------------------------
# Selection
#--------------------------------------------------

# Single selection from a list
# Usage: ui_choose "item1" "item2" "item3"
ui_choose() {
    local choice
    
    if _has_gum; then
        choice=$(gum choose "$@")
    else
        PS3="Select an option: "
        select choice in "$@"; do
            [[ -n "$choice" ]] && break
        done
    fi
    
    echo "$choice"
}

# Multiple selection from a list
# Usage: ui_choose_multi "item1" "item2" "item3"
ui_choose_multi() {
    local choices
    
    if _has_gum; then
        choices=$(gum choose --no-limit "$@")
    else
        echo "Select options (space-separated numbers):"
        local i=1
        for item in "$@"; do
            echo "  $i) $item"
            ((i++))
        done
        
        read -rp "Selection: " selection
        
        local result=()
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && ((num > 0 && num <= $#)); then
                result+=("${!num}")
            fi
        done
        
        choices=$(printf '%s\n' "${result[@]}")
    fi
    
    echo "$choices"
}

#--------------------------------------------------
# Confirmation
#--------------------------------------------------

# Yes/No confirmation
# Usage: ui_confirm "Are you sure?" [default: y/n]
ui_confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    if _has_gum; then
        local args=()
        [[ "$default" == "y" ]] && args+=(--default=true)
        gum confirm "$prompt" "${args[@]}"
    else
        local yn
        if [[ "$default" == "y" ]]; then
            read -rp "$prompt [Y/n] " yn
            [[ -z "$yn" || "$yn" =~ ^[Yy] ]]
        else
            read -rp "$prompt [y/N] " yn
            [[ "$yn" =~ ^[Yy] ]]
        fi
    fi
}

#--------------------------------------------------
# Display
#--------------------------------------------------

# Display styled text
# Usage: ui_style "text" [style: bold|dim|italic|underline]
ui_style() {
    local text="$1"
    local style="${2:-}"
    
    if _has_gum; then
        case "$style" in
            bold)      gum style --bold "$text" ;;
            dim)       gum style --faint "$text" ;;
            italic)    gum style --italic "$text" ;;
            underline) gum style --underline "$text" ;;
            *)         gum style "$text" ;;
        esac
    else
        case "$style" in
            bold)      echo -e "${BOLD}${text}${RESET}" ;;
            dim)       echo -e "${DIM}${text}${RESET}" ;;
            *)         echo "$text" ;;
        esac
    fi
}

# Display a formatted box/panel
# Usage: ui_box "Title" "Content"
ui_box() {
    local title="$1"
    local content="$2"
    
    if _has_gum; then
        echo "$content" | gum style \
            --border rounded \
            --border-foreground 240 \
            --padding "1 2" \
            --margin "1 0"
    else
        local width=50
        echo ""
        echo "┌$(printf '─%.0s' $(seq 1 $((width-2))))┐"
        echo "│ ${BOLD}${title}${RESET}$(printf ' %.0s' $(seq 1 $((width - ${#title} - 4))))│"
        echo "├$(printf '─%.0s' $(seq 1 $((width-2))))┤"
        while IFS= read -r line; do
            printf "│ %-$((width-4))s │\n" "$line"
        done <<< "$content"
        echo "└$(printf '─%.0s' $(seq 1 $((width-2))))┘"
        echo ""
    fi
}

# Display a table
# Usage: ui_table "Header1,Header2" "Row1Col1,Row1Col2" "Row2Col1,Row2Col2"
ui_table() {
    if _has_gum; then
        local header="$1"
        shift
        {
            echo "$header"
            for row in "$@"; do
                echo "$row"
            done
        } | gum table
    else
        # Simple table without gum
        local header="$1"
        shift
        
        # Print header
        echo ""
        echo "$header" | tr ',' '\t'
        echo "$(echo "$header" | sed 's/[^,]/-/g' | tr ',' '\t')"
        
        # Print rows
        for row in "$@"; do
            echo "$row" | tr ',' '\t'
        done
        echo ""
    fi
}

#--------------------------------------------------
# File browser (simplified)
#--------------------------------------------------

# Browse for a file
# Usage: ui_file_browser [start_path]
ui_file_browser() {
    local start_path="${1:-.}"
    
    if _has_gum; then
        gum file "$start_path"
    else
        read -rp "Enter file path: " filepath
        echo "$filepath"
    fi
}

#--------------------------------------------------
# Progress (for longer operations)
#--------------------------------------------------

# Simple progress indicator
# Usage: ui_progress 50 100 "Processing..."
ui_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-Progress}"
    
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r%s [%s%s] %d%%" \
        "$message" \
        "$(printf '#%.0s' $(seq 1 $filled))" \
        "$(printf ' %.0s' $(seq 1 $empty))" \
        "$percent"
    
    [[ $current -eq $total ]] && echo ""
}

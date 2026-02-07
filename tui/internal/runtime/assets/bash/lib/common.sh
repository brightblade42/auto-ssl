#!/usr/bin/env bash
# auto-ssl common utilities
# Shared functions for logging, error handling, and general utilities

set -euo pipefail

#--------------------------------------------------
# Version
#--------------------------------------------------
AUTO_SSL_VERSION="0.1.0"

#--------------------------------------------------
# Colors (disabled if not a terminal)
#--------------------------------------------------
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    BOLD=''
    DIM=''
    RESET=''
fi

#--------------------------------------------------
# Logging functions
#--------------------------------------------------

log_info() {
    echo -e "${BLUE}ℹ${RESET} $*"
}

log_success() {
    echo -e "${GREEN}✓${RESET} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${RESET} $*" >&2
}

log_error() {
    echo -e "${RED}✗${RESET} $*" >&2
}

log_debug() {
    if [[ "${AUTO_SSL_DEBUG:-}" == "1" ]]; then
        echo -e "${DIM}[debug] $*${RESET}" >&2
    fi
}

log_step() {
    echo -e "${CYAN}→${RESET} $*"
}

log_header() {
    echo ""
    echo -e "${BOLD}$*${RESET}"
    echo -e "${DIM}$(printf '%.0s─' {1..50})${RESET}"
}

#--------------------------------------------------
# Error handling
#--------------------------------------------------

die() {
    log_error "$*"
    exit 1
}

die_with_help() {
    log_error "$1"
    echo ""
    echo "Run 'auto-ssl $2 --help' for usage information."
    exit 1
}

#--------------------------------------------------
# Requirement checking
#--------------------------------------------------

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This command must be run as root (use sudo)"
    fi
}

require_command() {
    local cmd="$1"
    local install_hint="${2:-}"
    
    if ! command -v "$cmd" &>/dev/null; then
        if [[ -n "$install_hint" ]]; then
            die "Required command '$cmd' not found. $install_hint"
        else
            die "Required command '$cmd' not found."
        fi
    fi
}

require_file() {
    local file="$1"
    local description="${2:-File}"
    
    if [[ ! -f "$file" ]]; then
        die "$description not found: $file"
    fi
}

require_dir() {
    local dir="$1"
    local description="${2:-Directory}"
    
    if [[ ! -d "$dir" ]]; then
        die "$description not found: $dir"
    fi
}

#--------------------------------------------------
# Utility functions
#--------------------------------------------------

# Check if a string is a valid IP address
is_ip() {
    local ip="$1"
    local valid_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ $ip =~ $valid_regex ]]; then
        # Check each octet
        IFS='.' read -ra octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if ((octet > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Get the primary IP address of this machine
get_primary_ip() {
    # Try hostname -I first (Linux)
    if command -v hostname &>/dev/null; then
        local ip
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        if [[ -n "$ip" ]] && is_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Fallback: parse ip route
    if command -v ip &>/dev/null; then
        local ip
        ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[^ ]+')
        if [[ -n "$ip" ]] && is_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Fallback: parse ifconfig
    if command -v ifconfig &>/dev/null; then
        local ip
        ip=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | \
             grep -v '127.0.0.1' | head -1 | awk '{print $2}' | sed 's/addr://')
        if [[ -n "$ip" ]] && is_ip "$ip"; then
            echo "$ip"
            return 0
        fi
    fi
    
    return 1
}

# Parse duration string (e.g., "7d", "24h", "168h") to hours
duration_to_hours() {
    local duration="$1"
    local value="${duration%[dhm]}"
    local unit="${duration: -1}"
    
    case "$unit" in
        d) echo $((value * 24)) ;;
        h) echo "$value" ;;
        m) echo $((value / 60)) ;;
        *) echo "$duration" ;;  # Assume hours if no unit
    esac
}

# Format hours to human-readable duration
hours_to_human() {
    local hours="$1"
    
    if ((hours >= 24)); then
        local days=$((hours / 24))
        local remaining=$((hours % 24))
        if ((remaining == 0)); then
            echo "${days} day(s)"
        else
            echo "${days} day(s), ${remaining} hour(s)"
        fi
    else
        echo "${hours} hour(s)"
    fi
}

random_string() {
    local length="${1:-32}"
    # Generate more bytes than needed to ensure we get enough after filtering
    # base64 encoding reduces ~4/3 ratio, and we filter to alphanumeric (62/64 chars)
    # So generate ~2x to be safe
    local bytes_needed=$((length * 2))
    head -c "$bytes_needed" /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

# Confirm an action (returns 0 for yes, 1 for no)
# Uses gum if available, falls back to read
confirm() {
    local prompt="$1"
    local default="${2:-n}"  # Default to no
    
    # Handled by ui.sh if sourced, but provide fallback
    if [[ "$default" == "y" ]]; then
        read -rp "$prompt [Y/n] " yn
        [[ -z "$yn" || "$yn" =~ ^[Yy] ]]
    else
        read -rp "$prompt [y/N] " yn
        [[ "$yn" =~ ^[Yy] ]]
    fi
}

#--------------------------------------------------
# Path and config helpers
#--------------------------------------------------

# Standard paths
AUTO_SSL_CONFIG_DIR="${AUTO_SSL_CONFIG_DIR:-/etc/auto-ssl}"
AUTO_SSL_DATA_DIR="${AUTO_SSL_DATA_DIR:-/var/lib/auto-ssl}"
AUTO_SSL_CERT_DIR="${AUTO_SSL_CERT_DIR:-/etc/ssl/auto-ssl}"
AUTO_SSL_LOG_DIR="${AUTO_SSL_LOG_DIR:-/var/log/auto-ssl}"

STEP_CA_PATH="${STEP_CA_PATH:-/opt/step-ca}"
STEP_CA_CONFIG="${STEP_CA_PATH}/config/ca.json"

# Ensure directories exist
ensure_dirs() {
    local dirs=("$AUTO_SSL_CONFIG_DIR" "$AUTO_SSL_DATA_DIR" "$AUTO_SSL_CERT_DIR")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 755 "$dir"
        fi
    done
}

#--------------------------------------------------
# Config file helpers
#--------------------------------------------------

# Read a value from the config file
config_get() {
    local key="$1"
    local default="${2:-}"
    local config_file="${AUTO_SSL_CONFIG_DIR}/config.yaml"
    
    if [[ -f "$config_file" ]]; then
        local value=""
        if [[ "$key" == *"."* ]]; then
            local parent="${key%%.*}"
            local child="${key#*.}"
            value=$(awk -v parent="$parent" -v child="$child" '
                $0 ~ "^[[:space:]]*" parent ":[[:space:]]*$" { in_parent=1; next }
                in_parent && $0 ~ "^[^[:space:]]" { in_parent=0 }
                in_parent && $0 ~ "^[[:space:]]+" child ":[[:space:]]*" {
                    sub(/^[[:space:]]+[^:]+:[[:space:]]*/, "", $0)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
                    print
                    exit
                }
            ' "$config_file" 2>/dev/null)
        else
            value=$(awk -v key="$key" '
                $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
                    sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", $0)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
                    print
                    exit
                }
            ' "$config_file" 2>/dev/null)
        fi

        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    fi
    
    echo "$default"
}

# Write a value to the config file
config_set() {
    local key="$1"
    local value="$2"
    local config_file="${AUTO_SSL_CONFIG_DIR}/config.yaml"
    local tmp_file
    
    ensure_dirs
    
    if [[ "$key" == *"."* ]]; then
        local parent="${key%%.*}"
        local child="${key#*.}"

        if [[ -f "$config_file" ]]; then
            tmp_file=$(mktemp)
            awk -v parent="$parent" -v child="$child" -v value="$value" '
                BEGIN { in_parent=0; parent_seen=0; child_set=0 }
                $0 ~ "^[[:space:]]*" parent ":[[:space:]]*$" {
                    print
                    in_parent=1
                    parent_seen=1
                    next
                }
                in_parent && $0 ~ "^[^[:space:]]" {
                    if (!child_set) {
                        print "  " child ": " value
                        child_set=1
                    }
                    in_parent=0
                }
                in_parent && $0 ~ "^[[:space:]]+" child ":[[:space:]]*" {
                    print "  " child ": " value
                    child_set=1
                    next
                }
                { print }
                END {
                    if (!parent_seen) {
                        print parent ":"
                        print "  " child ": " value
                    } else if (in_parent && !child_set) {
                        print "  " child ": " value
                    }
                }
            ' "$config_file" > "$tmp_file"
            mv "$tmp_file" "$config_file"
        else
            cat > "$config_file" << EOF
${parent}:
  ${child}: ${value}
EOF
        fi
    else
        if [[ -f "$config_file" ]]; then
            tmp_file=$(mktemp)
            awk -v key="$key" -v value="$value" '
                BEGIN { set=0 }
                $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
                    print key ": " value
                    set=1
                    next
                }
                { print }
                END {
                    if (!set) {
                        print key ": " value
                    }
                }
            ' "$config_file" > "$tmp_file"
            mv "$tmp_file" "$config_file"
        else
            echo "${key}: ${value}" > "$config_file"
        fi
    fi
    
    chmod 600 "$config_file"
}

#--------------------------------------------------
# Cleanup trap helper
#--------------------------------------------------

# Array to hold cleanup commands
declare -a _cleanup_commands=()

cleanup_add() {
    _cleanup_commands+=("$*")
}

cleanup_run() {
    for cmd in "${_cleanup_commands[@]:-}"; do
        eval "$cmd" || true
    done
}

trap cleanup_run EXIT

#--------------------------------------------------
# Health check helper
#--------------------------------------------------

# Check if CA is healthy
check_ca_health() {
    local ca_url="$1"
    local timeout="${2:-5}"
    
    if [[ -z "$ca_url" ]]; then
        return 1
    fi
    
    # Check health endpoint
    if curl -sf --max-time "$timeout" "${ca_url}/health" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Check CA health and die if not healthy
require_ca_healthy() {
    local ca_url="$1"
    
    if ! check_ca_health "$ca_url"; then
        die "CA is not reachable at ${ca_url}. Check network and firewall."
    fi
}

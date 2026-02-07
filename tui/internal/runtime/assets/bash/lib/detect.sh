#!/usr/bin/env bash
# auto-ssl OS and environment detection
# Detects operating system, distribution, and available tools

#--------------------------------------------------
# OS Detection
#--------------------------------------------------

# Detect the operating system
detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        MINGW*|CYGWIN*|MSYS*) echo "windows" ;;
        *)       echo "unknown" ;;
    esac
}

# Detect Linux distribution
detect_distro() {
    if [[ ! -f /etc/os-release ]]; then
        echo "unknown"
        return
    fi
    
    # shellcheck source=/dev/null
    source /etc/os-release
    
    case "${ID:-}" in
        rhel|centos|rocky|alma|fedora)
            echo "rhel"
            ;;
        ubuntu|debian|pop|mint|elementary)
            echo "debian"
            ;;
        arch|manjaro)
            echo "arch"
            ;;
        opensuse*|sles)
            echo "suse"
            ;;
        *)
            # Check ID_LIKE for derivatives
            case "${ID_LIKE:-}" in
                *rhel*|*fedora*|*centos*)
                    echo "rhel"
                    ;;
                *debian*|*ubuntu*)
                    echo "debian"
                    ;;
                *)
                    echo "unknown"
                    ;;
            esac
            ;;
    esac
}

# Get full distro name and version
get_distro_info() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "${PRETTY_NAME:-${NAME:-Unknown} ${VERSION_ID:-}}"
    elif [[ -f /etc/redhat-release ]]; then
        cat /etc/redhat-release
    elif [[ "$(detect_os)" == "macos" ]]; then
        echo "macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
    else
        echo "Unknown OS"
    fi
}

# Get package manager
get_package_manager() {
    local distro
    distro=$(detect_distro)
    
    case "$distro" in
        rhel)
            if command -v dnf &>/dev/null; then
                echo "dnf"
            else
                echo "yum"
            fi
            ;;
        debian)
            echo "apt"
            ;;
        arch)
            echo "pacman"
            ;;
        suse)
            echo "zypper"
            ;;
        *)
            if [[ "$(detect_os)" == "macos" ]]; then
                echo "brew"
            else
                echo "unknown"
            fi
            ;;
    esac
}

#--------------------------------------------------
# Architecture Detection
#--------------------------------------------------

detect_arch() {
    local arch
    arch=$(uname -m)
    
    case "$arch" in
        x86_64|amd64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l|armhf)
            echo "arm"
            ;;
        i386|i686)
            echo "386"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

#--------------------------------------------------
# Service Manager Detection
#--------------------------------------------------

detect_service_manager() {
    if command -v systemctl &>/dev/null && [[ -d /run/systemd/system ]]; then
        echo "systemd"
    elif command -v service &>/dev/null; then
        echo "sysvinit"
    elif [[ "$(detect_os)" == "macos" ]]; then
        echo "launchd"
    else
        echo "unknown"
    fi
}

#--------------------------------------------------
# Tool Detection
#--------------------------------------------------

# Check if step CLI is installed
has_step_cli() {
    command -v step &>/dev/null
}

# Check if step-ca is installed
has_step_ca() {
    command -v step-ca &>/dev/null
}

# Check if gum is installed (for enhanced UI)
has_gum() {
    command -v gum &>/dev/null
}

# Check if jq is installed (for JSON parsing)
has_jq() {
    command -v jq &>/dev/null
}

# Get step CLI version
get_step_version() {
    if has_step_cli; then
        step version 2>/dev/null | head -1 | awk '{print $2}' | tr -d 'v'
    else
        echo "not installed"
    fi
}

# Get step-ca version
get_step_ca_version() {
    if has_step_ca; then
        step-ca version 2>/dev/null | head -1 | awk '{print $2}' | tr -d 'v'
    else
        echo "not installed"
    fi
}

#--------------------------------------------------
# Environment Detection (CA/Server/Client role)
#--------------------------------------------------

# Check if this machine is running as a CA
is_ca_server() {
    # Check if step-ca service exists and is running
    if [[ "$(detect_service_manager)" == "systemd" ]]; then
        systemctl is-active step-ca &>/dev/null && return 0
    fi
    
    # Check if step-ca config exists
    [[ -f "${STEP_CA_PATH:-/opt/step-ca}/config/ca.json" ]] && return 0
    
    return 1
}

# Check if this machine is enrolled as a server
is_enrolled_server() {
    # Check if we have certificates
    [[ -f "${AUTO_SSL_CERT_DIR:-/etc/ssl/auto-ssl}/server.crt" ]] && return 0
    
    # Check if step is bootstrapped
    [[ -f "${HOME}/.step/config/defaults.json" ]] && return 0
    [[ -f "/root/.step/config/defaults.json" ]] && return 0
    
    return 1
}

# Check if step is bootstrapped to a CA
is_bootstrapped() {
    local step_path="${STEPPATH:-$HOME/.step}"
    [[ -f "${step_path}/config/defaults.json" ]] || \
    [[ -f "${step_path}/certs/root_ca.crt" ]]
}

# Detect the current role/mode
detect_mode() {
    if is_ca_server; then
        echo "ca"
    elif is_enrolled_server; then
        echo "server"
    elif is_bootstrapped; then
        echo "bootstrapped"
    else
        echo "fresh"
    fi
}

#--------------------------------------------------
# Print detection summary (for debugging)
#--------------------------------------------------

print_detection_summary() {
    echo "Environment Detection Summary"
    echo "=============================="
    echo "OS:              $(detect_os)"
    echo "Distribution:    $(get_distro_info)"
    echo "Distro Family:   $(detect_distro)"
    echo "Architecture:    $(detect_arch)"
    echo "Package Manager: $(get_package_manager)"
    echo "Service Manager: $(detect_service_manager)"
    echo ""
    echo "Installed Tools:"
    echo "  step CLI:      $(get_step_version)"
    echo "  step-ca:       $(get_step_ca_version)"
    echo "  gum:           $(has_gum && echo 'yes' || echo 'no')"
    echo "  jq:            $(has_jq && echo 'yes' || echo 'no')"
    echo ""
    echo "Detected Mode:   $(detect_mode)"
    echo "  Is CA Server:  $(is_ca_server && echo 'yes' || echo 'no')"
    echo "  Is Enrolled:   $(is_enrolled_server && echo 'yes' || echo 'no')"
    echo "  Is Bootstrapped: $(is_bootstrapped && echo 'yes' || echo 'no')"
}

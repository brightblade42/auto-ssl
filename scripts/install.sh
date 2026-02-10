#!/usr/bin/env bash
#
# auto-ssl installer
# Installs auto-ssl-tui helper plus a compatibility auto-ssl wrapper
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Brightblade42/auto-ssl/main/scripts/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/Brightblade42/auto-ssl/main/scripts/install.sh | bash -s -- --prefix /usr/local
#
# Options:
#   --prefix DIR  Installation prefix (default: /usr/local)
#

set -euo pipefail

#--------------------------------------------------
# Configuration
#--------------------------------------------------

REPO="Brightblade42/auto-ssl"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' RESET=''
fi

#--------------------------------------------------
# Functions
#--------------------------------------------------

log_info() { echo -e "${BLUE}[INFO]${RESET} $*"; }
log_success() { echo -e "${GREEN}[OK]${RESET} $*"; }
log_warning() { echo -e "${YELLOW}[WARN]${RESET} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die() { log_error "$*"; exit 1; }

detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "darwin" ;;
        *)       die "Unsupported operating system: $(uname -s)" ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        case "${ID:-}" in
            rhel|centos|rocky|alma|fedora) echo "rhel" ;;
            ubuntu|debian|pop|mint) echo "debian" ;;
            *) echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

check_requirements() {
    log_info "Checking requirements..."
    
    local missing=()
    
    # Required commands
    for cmd in curl tar; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required commands: ${missing[*]}"
    fi
    
    # Check for write permission
    if [[ ! -w "${INSTALL_PREFIX}/bin" ]] && [[ $EUID -ne 0 ]]; then
        log_warning "Installation requires root/sudo for ${INSTALL_PREFIX}/bin"
        log_info "Rerun with: curl -fsSL ... | sudo bash"
        die "Permission denied"
    fi
    
    log_success "Requirements satisfied"
}

download_release() {
    local os="$1"
    local arch="$2"
    local dest="$3"

    local url="https://github.com/${REPO}/releases/latest/download/auto-ssl-tui-${os}-${arch}"

    log_info "Downloading auto-ssl-tui from ${url}..."

    if ! curl -fsSL -o "$dest" "$url"; then
        die "Failed to download from ${url}"
    fi

    log_success "Downloaded auto-ssl-tui"
}

install_from_source() {
    log_info "Installing from source (GitHub clone)..."
    
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" EXIT
    
    # Clone repository
    log_info "Cloning repository..."
    git clone --depth 1 "https://github.com/${REPO}.git" "$tmp_dir/auto-ssl"
    
    # Build companion helper
    if ! command -v go &>/dev/null; then
        die "Go is required for --from-source installs"
    fi
    log_info "Building auto-ssl-tui companion..."
    cd "${tmp_dir}/auto-ssl/tui"
    go build -o "${tmp_dir}/auto-ssl-tui" ./cmd/auto-ssl

    # Install binary + wrapper
    log_info "Installing auto-ssl-tui..."
    install -d "${INSTALL_PREFIX}/bin"
    install -m 755 "${tmp_dir}/auto-ssl-tui" "${INSTALL_PREFIX}/bin/auto-ssl-tui"
    install -m 755 "${tmp_dir}/auto-ssl/scripts/auto-ssl-wrapper.sh" "${INSTALL_PREFIX}/bin/auto-ssl"

    log_success "Installed auto-ssl-tui and auto-ssl wrapper"
}

install_from_release() {
    local os
    os=$(detect_os)
    local arch
    arch=$(detect_arch)
    
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf '$tmp_dir'" EXIT
    
    # Download and install companion binary
    download_release "$os" "$arch" "${tmp_dir}/auto-ssl-tui"

    install -d "${INSTALL_PREFIX}/bin"
    install -m 755 "${tmp_dir}/auto-ssl-tui" "${INSTALL_PREFIX}/bin/auto-ssl-tui"

    # Install compatibility wrapper
    cat > "${tmp_dir}/auto-ssl" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec auto-ssl-tui exec -- "$@"
EOF
    install -m 755 "${tmp_dir}/auto-ssl" "${INSTALL_PREFIX}/bin/auto-ssl"

    log_success "Installed auto-ssl-tui and auto-ssl wrapper"
}

install_dependencies() {
    local distro
    distro=$(detect_distro)
    
    log_info "Checking for optional dependencies..."
    
    # gum (optional but recommended for improved prompts)
    if ! command -v gum &>/dev/null; then
        log_info "Installing gum for enhanced CLI experience..."
        case "$distro" in
            rhel)
                if command -v dnf &>/dev/null; then
                    # Try to add charm repo
                    echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo >/dev/null
                    dnf install -y gum 2>/dev/null || log_warning "Could not install gum"
                fi
                ;;
            debian)
                # Try to add charm repo
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null || true
                echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
                sudo apt update 2>/dev/null && sudo apt install -y gum 2>/dev/null || log_warning "Could not install gum"
                ;;
            *)
                log_warning "Cannot auto-install gum. Install manually for enhanced prompt UX."
                ;;
        esac
    fi
    
    # jq (used by some commands)
    if ! command -v jq &>/dev/null; then
        log_info "jq not found. Some features may be limited."
    fi
}

show_completion() {
    echo ""
    echo -e "${GREEN}${BOLD}Installation complete!${RESET}"
    echo ""
    echo "  auto-ssl-tui is now available at: ${INSTALL_PREFIX}/bin/auto-ssl-tui"
    echo "  auto-ssl wrapper is now available at: ${INSTALL_PREFIX}/bin/auto-ssl"
    echo ""
    echo "Quick start:"
    echo ""
    echo "  # Initialize a CA (on CA server)"
    echo "  sudo auto-ssl ca init --name \"My Internal CA\""
    echo ""
    echo "  # Enroll a server (on app servers)"
    echo "  sudo auto-ssl server enroll --ca-url https://CA_IP:9000 --fingerprint FINGERPRINT"
    echo ""
    echo "  # Trust CA on client machines"
    echo "  sudo auto-ssl client trust --ca-url https://CA_IP:9000 --fingerprint FINGERPRINT"
    echo ""
    echo "  # Companion helper commands"
    echo "  auto-ssl-tui doctor"
    echo "  auto-ssl-tui exec -- server status"
    echo ""
    echo "Documentation: https://github.com/${REPO}"
    echo ""
}

#--------------------------------------------------
# Parse arguments
#--------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-tui|--no-tui)
            log_warning "$1 is deprecated. auto-ssl-tui is always installed."
            shift
            ;;
        --prefix)
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        --from-source)
            FROM_SOURCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: install.sh [options]"
            echo ""
            echo "Options:"
            echo "  --prefix DIR     Installation prefix (default: /usr/local)"
            echo "  --from-source    Clone and build from source"
            echo "  -h, --help       Show this help"
            exit 0
            ;;
        *)
            log_warning "Unknown option: $1"
            shift
            ;;
    esac
done

#--------------------------------------------------
# Main
#--------------------------------------------------

echo ""
echo -e "${BOLD}auto-ssl installer${RESET}"
echo -e "${BLUE}Internal PKI made easy${RESET}"
echo ""

check_requirements

if [[ "${FROM_SOURCE:-false}" == true ]] || [[ ! -x "$(command -v curl)" ]]; then
    install_from_source
else
    # Try release first, fall back to source
    install_from_release || install_from_source
fi

install_dependencies
show_completion

#!/usr/bin/env bash
# auto-ssl client commands
# Commands for trusting the CA on client machines

#--------------------------------------------------
# Help
#--------------------------------------------------

cmd_client_help() {
    cat << 'HELP'
auto-ssl client - Client trust management

USAGE
    auto-ssl client <subcommand> [options]

SUBCOMMANDS
    trust           Install root CA into system trust store
    status          Verify root CA is trusted

EXAMPLES
    # Trust the CA
    sudo auto-ssl client trust \
        --ca-url https://192.168.1.100:9000 \
        --fingerprint abc123def456

    # Check trust status
    auto-ssl client status

HELP
}

cmd_client() {
    cmd_client_help
}

#--------------------------------------------------
# Client Trust
#--------------------------------------------------

cmd_client_trust_help() {
    cat << 'HELP'
auto-ssl client trust - Install root CA into system trust store

USAGE
    auto-ssl client trust [options]

OPTIONS
    --ca-url URL          CA server URL (required)
    --fingerprint FP      CA root fingerprint (required)
    --cert-file FILE      Use local CA cert file instead of downloading
    -h, --help            Show this help

EXAMPLES
    # Trust CA by downloading root cert
    sudo auto-ssl client trust \
        --ca-url https://192.168.1.100:9000 \
        --fingerprint abc123def456

    # Trust from local file
    sudo auto-ssl client trust --cert-file /path/to/root_ca.crt

SUPPORTED PLATFORMS
    - macOS (Keychain)
    - RHEL/Fedora/CentOS (update-ca-trust)
    - Ubuntu/Debian (update-ca-certificates)
    - Windows (manual instructions provided)

HELP
}

cmd_client_trust() {
    local ca_url=""
    local fingerprint=""
    local cert_file=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ca-url)
                ca_url="$2"
                shift 2
                ;;
            --fingerprint)
                fingerprint="$2"
                shift 2
                ;;
            --cert-file)
                cert_file="$2"
                shift 2
                ;;
            -h|--help)
                cmd_client_trust_help
                return 0
                ;;
            *)
                die_with_help "Unknown option: $1" "client trust"
                ;;
        esac
    done
    
    log_header "Installing Root CA Trust"
    
    local tmp_cert=""
    
    if [[ -n "$cert_file" ]]; then
        require_file "$cert_file" "Certificate file"
        tmp_cert="$cert_file"
    else
        [[ -z "$ca_url" ]] && die "CA URL required. Use --ca-url URL"
        [[ -z "$fingerprint" ]] && die "Fingerprint required. Use --fingerprint FP"
        
        # Download root CA
        log_step "Downloading root CA from ${ca_url}..."
        tmp_cert=$(mktemp)
        cleanup_add "rm -f '$tmp_cert'"
        
        if ! curl -sk "${ca_url}/roots.pem" -o "$tmp_cert"; then
            die "Failed to download root CA"
        fi
        
        # Verify fingerprint
        log_step "Verifying fingerprint..."
        local actual_fp
        actual_fp=$(step certificate fingerprint "$tmp_cert" 2>/dev/null || \
                    openssl x509 -in "$tmp_cert" -noout -fingerprint -sha256 2>/dev/null | \
                    cut -d= -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')
        
        # Normalize fingerprints for comparison
        fingerprint=$(echo "$fingerprint" | tr -d ':' | tr '[:upper:]' '[:lower:]')
        actual_fp=$(echo "$actual_fp" | tr -d ':' | tr '[:upper:]' '[:lower:]')
        
        if [[ "$actual_fp" != "$fingerprint" ]]; then
            log_error "Fingerprint mismatch!"
            echo "  Expected: ${fingerprint}"
            echo "  Got:      ${actual_fp}"
            die "Root CA verification failed. This could indicate a MITM attack."
        fi
        
        log_success "Fingerprint verified"
    fi
    
    # Detect OS and install
    local os
    os=$(detect_os)
    local distro
    distro=$(detect_distro)
    
    case "$os" in
        macos)
            _trust_macos "$tmp_cert"
            ;;
        linux)
            case "$distro" in
                rhel)
                    _trust_rhel "$tmp_cert"
                    ;;
                debian)
                    _trust_debian "$tmp_cert"
                    ;;
                *)
                    log_warning "Unknown Linux distribution"
                    _trust_linux_generic "$tmp_cert"
                    ;;
            esac
            ;;
        windows)
            _trust_windows "$tmp_cert"
            ;;
        *)
            die "Unsupported operating system: $os"
            ;;
    esac
    
    # Save configuration
    if [[ -n "$ca_url" ]]; then
        config_set "ca.url" "$ca_url"
        config_set "ca.fingerprint" "$fingerprint"
    fi
    
    echo ""
    log_success "Root CA trusted successfully!"
    echo ""
    echo "Browsers and applications should now trust certificates from this CA."
    echo "You may need to restart your browser for changes to take effect."
}

#--------------------------------------------------
# Client Status
#--------------------------------------------------

cmd_client_status() {
    log_header "Client Trust Status"
    
    local ca_url
    ca_url=$(config_get "ca.url" "")
    local fingerprint
    fingerprint=$(config_get "ca.fingerprint" "")
    
    echo "Configuration:"
    echo "  CA URL:      ${ca_url:-not configured}"
    echo "  Fingerprint: ${fingerprint:-not configured}"
    echo ""
    
    local os
    os=$(detect_os)
    local distro
    distro=$(detect_distro)
    
    echo "Trust Store Status:"
    
    case "$os" in
        macos)
            _check_trust_macos
            ;;
        linux)
            case "$distro" in
                rhel)
                    _check_trust_rhel
                    ;;
                debian)
                    _check_trust_debian
                    ;;
                *)
                    echo "  Unable to check trust store for this distribution"
                    ;;
            esac
            ;;
        *)
            echo "  Unable to check trust store for this OS"
            ;;
    esac
    
    # Test actual connection if CA URL is configured
    if [[ -n "$ca_url" ]]; then
        echo ""
        echo "Connection Test:"
        if curl -s "${ca_url}/health" &>/dev/null; then
            log_success "  Can connect to CA without certificate errors"
        else
            if curl -sk "${ca_url}/health" &>/dev/null; then
                log_warning "  Can connect with -k flag (cert not trusted)"
            else
                log_error "  Cannot connect to CA"
            fi
        fi
    fi
}

#--------------------------------------------------
# Platform-specific trust functions
#--------------------------------------------------

_trust_macos() {
    local cert="$1"
    
    require_root
    
    log_step "Installing to macOS System Keychain..."
    
    security add-trusted-cert \
        -d \
        -r trustRoot \
        -k /Library/Keychains/System.keychain \
        "$cert"
    
    log_success "Added to System Keychain"
}

_trust_rhel() {
    local cert="$1"
    
    require_root
    
    log_step "Installing to RHEL/Fedora trust store..."
    
    local dest="/etc/pki/ca-trust/source/anchors/auto-ssl-root-ca.crt"
    cp "$cert" "$dest"
    chmod 644 "$dest"
    
    log_step "Updating CA trust..."
    update-ca-trust
    
    log_success "Added to system trust store"
}

_trust_debian() {
    local cert="$1"
    
    require_root
    
    log_step "Installing to Ubuntu/Debian trust store..."
    
    local dest="/usr/local/share/ca-certificates/auto-ssl-root-ca.crt"
    cp "$cert" "$dest"
    chmod 644 "$dest"
    
    log_step "Updating CA certificates..."
    update-ca-certificates
    
    log_success "Added to system trust store"
}

_trust_linux_generic() {
    local cert="$1"
    
    log_warning "Unknown Linux distribution. Attempting generic installation..."
    
    # Try RHEL-style first
    if [[ -d /etc/pki/ca-trust/source/anchors ]]; then
        _trust_rhel "$cert"
        return
    fi
    
    # Try Debian-style
    if [[ -d /usr/local/share/ca-certificates ]]; then
        _trust_debian "$cert"
        return
    fi
    
    # Manual fallback
    log_warning "Could not auto-detect trust store location"
    echo ""
    echo "Manual installation required. Copy the root CA to your system's trust store:"
    echo "  cp root_ca.crt /path/to/trust/store/"
    echo "  update-ca-trust  (or equivalent command)"
}

_trust_windows() {
    local cert="$1"
    
    log_warning "Windows detected. Automatic installation not supported."
    echo ""
    echo "Manual installation steps:"
    echo ""
    echo "1. Copy the root CA certificate to a Windows-accessible location:"
    echo "   ${cert}"
    echo ""
    echo "2. On Windows, either:"
    echo ""
    echo "   Option A - GUI:"
    echo "   - Double-click the .crt file"
    echo "   - Click 'Install Certificate'"
    echo "   - Select 'Local Machine'"
    echo "   - Select 'Place all certificates in the following store'"
    echo "   - Browse → 'Trusted Root Certification Authorities'"
    echo "   - Finish"
    echo ""
    echo "   Option B - Command line (PowerShell as Admin):"
    echo "   Import-Certificate -FilePath root_ca.crt -CertStoreLocation Cert:\\LocalMachine\\Root"
    echo ""
    echo "3. Restart your browser"
}

#--------------------------------------------------
# Check trust functions
#--------------------------------------------------

_check_trust_macos() {
    if security find-certificate -a -c "auto-ssl" /Library/Keychains/System.keychain &>/dev/null; then
        log_success "  Root CA found in System Keychain"
    else
        log_warning "  Root CA not found in System Keychain"
    fi
}

_check_trust_rhel() {
    if [[ -f /etc/pki/ca-trust/source/anchors/auto-ssl-root-ca.crt ]]; then
        log_success "  Root CA file present in /etc/pki/ca-trust/source/anchors/"
        
        # Check if it's in the extracted bundle
        if grep -q "auto-ssl" /etc/pki/tls/certs/ca-bundle.crt 2>/dev/null; then
            log_success "  Root CA is in active trust bundle"
        else
            log_warning "  Root CA may need 'update-ca-trust' to be run"
        fi
    else
        log_warning "  Root CA not found in /etc/pki/ca-trust/source/anchors/"
    fi
}

_check_trust_debian() {
    if [[ -f /usr/local/share/ca-certificates/auto-ssl-root-ca.crt ]]; then
        log_success "  Root CA file present in /usr/local/share/ca-certificates/"
        
        # Check if it's in the extracted bundle
        if [[ -f /etc/ssl/certs/auto-ssl-root-ca.pem ]]; then
            log_success "  Root CA is in active trust bundle"
        else
            log_warning "  Root CA may need 'update-ca-certificates' to be run"
        fi
    else
        log_warning "  Root CA not found in /usr/local/share/ca-certificates/"
    fi
}

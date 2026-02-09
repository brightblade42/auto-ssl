#!/usr/bin/env bash
# auto-ssl server commands
# Commands for enrolling servers and managing certificates

#--------------------------------------------------
# Help
#--------------------------------------------------

cmd_server_help() {
    cat << 'HELP'
auto-ssl server - Server certificate management

USAGE
    auto-ssl server <subcommand> [options]

SUBCOMMANDS
    enroll          Enroll this server (get certs, setup renewal)
    status          Show certificate status and expiration
    renew           Force immediate certificate renewal
    suspend         Temporarily block certificate renewals
    resume          Re-enable certificate renewals
    revoke          Revoke certificate immediately
    remove          Revoke certificate and remove from inventory

EXAMPLES
    # Enroll this server
    sudo auto-ssl server enroll \
        --ca-url https://192.168.1.100:9000 \
        --fingerprint abc123def456

    # Check certificate status
    auto-ssl server status

    # Force immediate renewal
    sudo auto-ssl server renew --force

HELP
}

cmd_server() {
    cmd_server_help
}

#--------------------------------------------------
# Server Enroll
#--------------------------------------------------

cmd_server_enroll_help() {
    cat << 'HELP'
auto-ssl server enroll - Enroll this server to get certificates

USAGE
    auto-ssl server enroll [options]

OPTIONS
    --ca-url URL          CA server URL (required)
    --fingerprint FP      CA root fingerprint (required)
    --san NAME            Subject Alternative Name (can repeat, default: primary IP)
    --duration DUR        Certificate duration (default: from CA)
    --cert-path PATH      Where to store certificate (default: /etc/ssl/auto-ssl/server.crt)
    --key-path PATH       Where to store private key (default: /etc/ssl/auto-ssl/server.key)
    --provisioner NAME    Provisioner name (default: admin)
    --password-file FILE  Provisioner password file (or prompt)
    --no-renewal          Don't set up automatic renewal
    --non-interactive     Don't prompt for input
    -h, --help            Show this help

EXAMPLES
    # Basic enrollment (interactive)
    sudo auto-ssl server enroll \
        --ca-url https://192.168.1.100:9000 \
        --fingerprint abc123

    # With custom SANs
    sudo auto-ssl server enroll \
        --ca-url https://192.168.1.100:9000 \
        --fingerprint abc123 \
        --san 192.168.1.50 \
        --san myserver.local

    # Non-interactive with password file
    sudo auto-ssl server enroll \
        --ca-url https://192.168.1.100:9000 \
        --fingerprint abc123 \
        --password-file /etc/step/password \
        --non-interactive

HELP
}

cmd_server_enroll() {
    local ca_url=""
    local fingerprint=""
    local sans=()
    local duration=""
    local cert_path="${AUTO_SSL_CERT_DIR}/server.crt"
    local key_path="${AUTO_SSL_CERT_DIR}/server.key"
    local provisioner="admin"
    local password_file=""
    local setup_renewal=true
    local non_interactive=false
    
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
            --san)
                sans+=("$2")
                shift 2
                ;;
            --duration)
                duration="$2"
                shift 2
                ;;
            --cert-path)
                cert_path="$2"
                shift 2
                ;;
            --key-path)
                key_path="$2"
                shift 2
                ;;
            --provisioner)
                provisioner="$2"
                shift 2
                ;;
            --password-file)
                password_file="$2"
                shift 2
                ;;
            --no-renewal)
                setup_renewal=false
                shift
                ;;
            --non-interactive)
                non_interactive=true
                shift
                ;;
            -h|--help)
                cmd_server_enroll_help
                return 0
                ;;
            *)
                die_with_help "Unknown option: $1" "server enroll"
                ;;
        esac
    done
    
    require_root
    
    # Validate required arguments
    [[ -z "$ca_url" ]] && die "CA URL required. Use --ca-url URL"
    [[ -z "$fingerprint" ]] && die "Fingerprint required. Use --fingerprint FP"
    
    log_header "Enrolling Server"
    
    # Default SAN to primary IP
    if [[ ${#sans[@]} -eq 0 ]]; then
        local primary_ip
        primary_ip=$(get_primary_ip) || die "Could not detect primary IP. Use --san to specify."
        sans+=("$primary_ip")
        log_info "Using primary IP as SAN: ${primary_ip}"
    fi
    
    # Get password if needed
    local password=""
    if [[ -n "$password_file" ]]; then
        if [[ "$password_file" == "/dev/stdin" ]]; then
            password=$(cat)
        else
            require_file "$password_file" "Password file"
            password=$(cat "$password_file")
        fi
        [[ -z "$password" ]] && die "Password file is empty: ${password_file}"
    elif [[ "$non_interactive" == true ]]; then
        die "Non-interactive mode requires --password-file"
    elif [[ "$non_interactive" == false ]]; then
        password=$(ui_password "Enter provisioner password")
    fi
    
    # Install step CLI if needed
    if ! has_step_cli; then
        log_step "Installing step CLI..."
        _install_step_cli
    fi
    
    # Create certificate directory
    log_step "Creating certificate directory..."
    mkdir -p "$(dirname "$cert_path")"
    chmod 755 "$(dirname "$cert_path")"
    
    # Bootstrap trust
    log_step "Bootstrapping trust to CA..."
    step ca bootstrap \
        --ca-url "$ca_url" \
        --fingerprint "$fingerprint" \
        --install \
        --force
    
    # Build SAN arguments
    local san_args=()
    for san in "${sans[@]}"; do
        san_args+=(--san "$san")
    done
    
    # Build certificate arguments
    local cert_args=(
        "${sans[0]}"
        "$cert_path"
        "$key_path"
        "${san_args[@]}"
        --provisioner "$provisioner"
        --force
    )
    
    [[ -n "$duration" ]] && cert_args+=(--not-after "$duration")
    
    # Request certificate
    log_step "Requesting certificate..."
    if [[ -n "$password" ]]; then
        # Use password
        local tmp_pw
        tmp_pw=$(mktemp)
        printf '%s' "$password" > "$tmp_pw"
        chmod 600 "$tmp_pw"
        cleanup_add "rm -f '$tmp_pw'"
        
        step ca certificate "${cert_args[@]}" --password-file "$tmp_pw"
        rm -f "$tmp_pw"
    else
        # Interactive password prompt
        step ca certificate "${cert_args[@]}"
    fi
    
    # Set permissions
    chmod 644 "$cert_path"
    chmod 600 "$key_path"
    
    # Verify certificate
    log_step "Verifying certificate..."
    if ! step certificate verify "$cert_path" --roots "$(step path)/certs/root_ca.crt" &>/dev/null; then
        die "Certificate verification failed"
    fi
    
    # Set up automatic renewal
    if [[ "$setup_renewal" == true ]]; then
        log_step "Setting up automatic renewal..."
        _setup_renewal_timer "$cert_path" "$key_path"
    fi
    
    # Save configuration
    log_step "Saving configuration..."
    config_set "ca.url" "$ca_url"
    config_set "ca.fingerprint" "$fingerprint"
    config_set "server.cert_path" "$cert_path"
    config_set "server.key_path" "$key_path"
    config_set "server.sans" "$(IFS=,; echo "${sans[*]}")"
    
    # Get certificate info
    local expiry
    expiry=$(step certificate inspect "$cert_path" --format json 2>/dev/null | \
             grep -o '"not_after": "[^"]*"' | cut -d'"' -f4 || echo "unknown")
    
    echo ""
    log_success "Server enrolled successfully!"
    echo ""
    ui_box "Certificate Information" "$(cat << INFO
Certificate: ${cert_path}
Private Key: ${key_path}
SANs:        ${sans[*]}
Expires:     ${expiry}

Renewal:     $(if [[ "$setup_renewal" == true ]]; then echo "Automatic (systemd timer)"; else echo "Manual"; fi)

Use these paths in your web server configuration:
  ssl_certificate     ${cert_path}
  ssl_certificate_key ${key_path}
INFO
)"
}

#--------------------------------------------------
# Server Status
#--------------------------------------------------

cmd_server_status() {
    log_header "Server Certificate Status"
    
    local cert_path
    cert_path=$(config_get "server.cert_path" "${AUTO_SSL_CERT_DIR}/server.crt")
    local key_path
    key_path=$(config_get "server.key_path" "${AUTO_SSL_CERT_DIR}/server.key")
    
    # Check if enrolled
    if [[ ! -f "$cert_path" ]]; then
        log_warning "No certificate found at ${cert_path}"
        echo ""
        echo "This server is not enrolled. Run:"
        echo "  sudo auto-ssl server enroll --ca-url <URL> --fingerprint <FP>"
        return 1
    fi
    
    echo "Certificate Files:"
    echo "  Certificate: ${cert_path}"
    echo "  Private Key: ${key_path}"
    echo ""
    
    # Certificate details
    echo "Certificate Details:"
    if has_step_cli; then
        step certificate inspect "$cert_path" --short 2>/dev/null | sed 's/^/  /'
    else
        openssl x509 -in "$cert_path" -noout -subject -dates -issuer 2>/dev/null | sed 's/^/  /'
    fi
    
    # Check expiration
    echo ""
    echo "Validity:"
    local end_date
    end_date=$(openssl x509 -in "$cert_path" -noout -enddate 2>/dev/null | cut -d= -f2)
    local end_epoch
    end_epoch=$(date -d "$end_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$end_date" +%s 2>/dev/null)
    local now_epoch
    now_epoch=$(date +%s)
    local days_left=$(( (end_epoch - now_epoch) / 86400 ))
    
    if (( days_left < 0 )); then
        log_error "  Certificate EXPIRED ${days_left#-} days ago"
    elif (( days_left < 1 )); then
        log_warning "  Certificate expires TODAY"
    elif (( days_left < 3 )); then
        log_warning "  Certificate expires in ${days_left} days"
    else
        log_success "  Certificate valid for ${days_left} more days"
    fi
    
    # Renewal timer status
    echo ""
    echo "Renewal Timer:"
    if systemctl is-active auto-ssl-renew.timer &>/dev/null; then
        log_success "  Timer is active"
        systemctl list-timers auto-ssl-renew.timer --no-pager 2>/dev/null | tail -2 | sed 's/^/  /'
    else
        log_warning "  Timer is not active"
        echo "  Set up renewal with: sudo auto-ssl server enroll ..."
    fi
    
    # CA connection
    echo ""
    echo "CA Connection:"
    local ca_url
    ca_url=$(config_get "ca.url" "")
    if [[ -n "$ca_url" ]]; then
        if curl -sk "${ca_url}/health" &>/dev/null; then
            log_success "  CA reachable at ${ca_url}"
        else
            log_warning "  CA not reachable at ${ca_url}"
        fi
    else
        log_warning "  CA URL not configured"
    fi
}

#--------------------------------------------------
# Server Renew
#--------------------------------------------------

cmd_server_renew_help() {
    cat << 'HELP'
auto-ssl server renew - Renew the server certificate

USAGE
    auto-ssl server renew [options]

OPTIONS
    --force         Force renewal even if certificate is still valid
    --exec CMD      Command to run after successful renewal (e.g., reload nginx)
    -h, --help      Show this help

EXAMPLES
    # Force immediate renewal
    sudo auto-ssl server renew --force

    # Renew and reload nginx
    sudo auto-ssl server renew --force --exec "systemctl reload nginx"

HELP
}

cmd_server_renew() {
    local force=false
    local exec_cmd=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                shift
                ;;
            --exec)
                exec_cmd="$2"
                shift 2
                ;;
            -h|--help)
                cmd_server_renew_help
                return 0
                ;;
            *)
                die_with_help "Unknown option: $1" "server renew"
                ;;
        esac
    done
    
    require_root
    
    local cert_path
    cert_path=$(config_get "server.cert_path" "${AUTO_SSL_CERT_DIR}/server.crt")
    local key_path
    key_path=$(config_get "server.key_path" "${AUTO_SSL_CERT_DIR}/server.key")
    
    require_file "$cert_path" "Certificate"
    require_file "$key_path" "Private key"
    
    log_header "Renewing Certificate"
    
    # Backup existing certificate before renewal
    log_step "Backing up current certificate..."
    local backup_dir="/var/lib/auto-ssl/cert-backups"
    mkdir -p "$backup_dir"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    cp "$cert_path" "${backup_dir}/server-${timestamp}.crt" 2>/dev/null || true
    cp "$key_path" "${backup_dir}/server-${timestamp}.key" 2>/dev/null || true
    chmod 600 "${backup_dir}/server-${timestamp}.key" 2>/dev/null || true
    
    # Clean up old backups (keep last 5)
    (cd "$backup_dir" && ls -t server-*.crt 2>/dev/null | tail -n +6 | xargs -r rm -f) || true
    (cd "$backup_dir" && ls -t server-*.key 2>/dev/null | tail -n +6 | xargs -r rm -f) || true
    
    # Use step ca renew (uses existing cert to authenticate)
    log_step "Requesting renewal..."
    
    local renew_args=("$cert_path" "$key_path")
    [[ "$force" == true ]] && renew_args+=(--force)
    
    if step ca renew "${renew_args[@]}"; then
        log_success "Certificate renewed successfully"
        
        # Show new expiration
        local expiry
        expiry=$(step certificate inspect "$cert_path" --format json 2>/dev/null | \
                 grep -o '"not_after": "[^"]*"' | cut -d'"' -f4 || echo "unknown")
        echo "  New expiration: ${expiry}"
        
        # Run post-renewal command
        if [[ -n "$exec_cmd" ]]; then
            log_step "Running post-renewal command..."
            if eval "$exec_cmd"; then
                log_success "Post-renewal command completed"
            else
                log_warning "Post-renewal command failed (exit code: $?)"
            fi
        fi
    else
        die "Certificate renewal failed"
    fi
}

#--------------------------------------------------
# Server Suspend/Resume/Revoke/Remove
#--------------------------------------------------

cmd_server_suspend_help() {
    cat << 'HELP'
auto-ssl server suspend - Temporarily disable automatic certificate renewal

USAGE
    auto-ssl server suspend [options]

OPTIONS
    --reason TEXT   Reason for suspension
    -h, --help      Show this help

EXAMPLES
    sudo auto-ssl server suspend --reason "Under maintenance"

HELP
}

cmd_server_suspend() {
    local reason=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reason) reason="$2"; shift 2 ;;
            -h|--help)
                cmd_server_suspend_help
                return 0
                ;;
            *) die_with_help "Unknown option: $1" "server suspend" ;;
        esac
    done
    
    require_root
    
    log_header "Suspending Certificate Renewal"
    
    # Stop and disable the renewal timer
    if systemctl is-active auto-ssl-renew.timer &>/dev/null; then
        log_step "Disabling renewal timer..."
        systemctl stop auto-ssl-renew.timer
        systemctl disable auto-ssl-renew.timer
        log_success "Renewal timer disabled"
    else
        log_info "Renewal timer was not active"
    fi
    
    # Mark as suspended in config
    config_set "server.suspended" "true"
    [[ -n "$reason" ]] && config_set "server.suspend_reason" "$reason"
    config_set "server.suspended_at" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    
    echo ""
    log_success "Certificate renewal suspended"
    [[ -n "$reason" ]] && echo "  Reason: ${reason}"
    echo ""
    log_warning "Certificate will not auto-renew. Resume with: sudo auto-ssl server resume"
}

cmd_server_resume_help() {
    cat << 'HELP'
auto-ssl server resume - Re-enable automatic certificate renewal

USAGE
    auto-ssl server resume [options]

OPTIONS
    -h, --help      Show this help

EXAMPLES
    sudo auto-ssl server resume

HELP
}

cmd_server_resume() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cmd_server_resume_help
                return 0
                ;;
            *) die_with_help "Unknown option: $1" "server resume" ;;
        esac
    done
    
    require_root
    
    log_header "Resuming Certificate Renewal"
    
    # Check if actually suspended
    local suspended
    suspended=$(config_get "server.suspended" "false")
    
    if [[ "$suspended" != "true" ]]; then
        log_warning "Server is not suspended"
        return 0
    fi
    
    # Re-enable the renewal timer
    if [[ -f /etc/systemd/system/auto-ssl-renew.timer ]]; then
        log_step "Re-enabling renewal timer..."
        systemctl daemon-reload
        systemctl enable auto-ssl-renew.timer
        systemctl start auto-ssl-renew.timer
        log_success "Renewal timer enabled"
    else
        log_error "Renewal timer not found. Server may need re-enrollment."
        return 1
    fi
    
    # Clear suspended status
    config_set "server.suspended" "false"
    config_set "server.resumed_at" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    
    echo ""
    log_success "Certificate renewal resumed"
    
    # Show next renewal time
    systemctl list-timers auto-ssl-renew.timer --no-pager | tail -2
}

cmd_server_revoke_help() {
    cat << 'HELP'
auto-ssl server revoke - Revoke the server certificate

USAGE
    auto-ssl server revoke [options]

OPTIONS
    --reason TEXT   Reason for revocation
    --serial NUM    Certificate serial number (if not current cert)
    -h, --help      Show this help

EXAMPLES
    # Revoke current certificate
    sudo auto-ssl server revoke --reason "Server decommissioned"

HELP
}

cmd_server_revoke() {
    local reason=""
    local serial=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reason) reason="$2"; shift 2 ;;
            --serial) serial="$2"; shift 2 ;;
            -h|--help)
                cmd_server_revoke_help
                return 0
                ;;
            *) die_with_help "Unknown option: $1" "server revoke" ;;
        esac
    done
    
    require_root
    
    local cert_path
    cert_path=$(config_get "server.cert_path" "${AUTO_SSL_CERT_DIR}/server.crt")
    local key_path
    key_path=$(config_get "server.key_path" "${AUTO_SSL_CERT_DIR}/server.key")
    
    log_header "Revoking Certificate"
    
    if [[ -n "$serial" ]]; then
        # Revoke by serial number
        log_step "Revoking certificate with serial: ${serial}"
        step ca revoke "$serial" ${reason:+--reason "$reason"}
    else
        # Revoke current certificate
        require_file "$cert_path" "Certificate"
        require_file "$key_path" "Private key"
        
        if ! ui_confirm "Revoke current certificate? This cannot be undone."; then
            log_info "Cancelled"
            return 1
        fi
        
        log_step "Revoking certificate..."
        step ca revoke --cert "$cert_path" --key "$key_path" ${reason:+--reason "$reason"}
    fi
    
    log_success "Certificate revoked"
    log_warning "The server will need to be re-enrolled to get a new certificate"
}

cmd_server_remove_help() {
    cat << 'HELP'
auto-ssl server remove - Revoke certificate and remove auto-ssl completely

USAGE
    auto-ssl server remove [options]

OPTIONS
    --reason TEXT   Reason for removal
    --keep-certs    Don't delete certificate files
    -h, --help      Show this help

EXAMPLES
    # Complete removal
    sudo auto-ssl server remove --reason "Server decommissioned"
    
    # Remove but keep certificates
    sudo auto-ssl server remove --keep-certs

HELP
}

cmd_server_remove() {
    local reason=""
    local keep_certs=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reason) reason="$2"; shift 2 ;;
            --keep-certs) keep_certs=true; shift ;;
            -h|--help)
                cmd_server_remove_help
                return 0
                ;;
            *) die_with_help "Unknown option: $1" "server remove" ;;
        esac
    done
    
    require_root
    
    log_header "Removing Server Enrollment"
    
    local cert_path
    cert_path=$(config_get "server.cert_path" "${AUTO_SSL_CERT_DIR}/server.crt")
    local key_path
    key_path=$(config_get "server.key_path" "${AUTO_SSL_CERT_DIR}/server.key")
    
    if ! ui_confirm "This will revoke the certificate and remove auto-ssl. Continue?"; then
        log_info "Cancelled"
        return 1
    fi
    
    # Revoke certificate if it exists
    if [[ -f "$cert_path" ]] && [[ -f "$key_path" ]]; then
        log_step "Revoking certificate..."
        if step ca revoke --cert "$cert_path" --key "$key_path" ${reason:+--reason "$reason"} 2>/dev/null; then
            log_success "Certificate revoked"
        else
            log_warning "Certificate revocation failed (may already be revoked or expired)"
        fi
    fi
    
    # Stop and disable renewal timer
    if systemctl is-active auto-ssl-renew.timer &>/dev/null; then
        log_step "Stopping renewal timer..."
        systemctl stop auto-ssl-renew.timer
        systemctl disable auto-ssl-renew.timer
        log_success "Renewal timer stopped"
    fi
    
    # Remove systemd files
    if [[ -f /etc/systemd/system/auto-ssl-renew.service ]]; then
        log_step "Removing systemd units..."
        rm -f /etc/systemd/system/auto-ssl-renew.service
        rm -f /etc/systemd/system/auto-ssl-renew.timer
        systemctl daemon-reload
        log_success "Systemd units removed"
    fi
    
    # Remove certificates unless --keep-certs
    if [[ "$keep_certs" == false ]]; then
        if [[ -d "${AUTO_SSL_CERT_DIR}" ]]; then
            log_step "Removing certificates..."
            rm -rf "${AUTO_SSL_CERT_DIR}"
            log_success "Certificates removed"
        fi
    else
        log_info "Keeping certificates at ${AUTO_SSL_CERT_DIR}"
    fi
    
    # Remove configuration
    if [[ -d "${AUTO_SSL_CONFIG_DIR}" ]]; then
        log_step "Removing configuration..."
        rm -rf "${AUTO_SSL_CONFIG_DIR}"
        log_success "Configuration removed"
    fi
    
    # Remove step trust
    if [[ -d "${HOME}/.step" ]]; then
        log_step "Removing step trust..."
        rm -rf "${HOME}/.step"
        [[ -d "/root/.step" ]] && rm -rf "/root/.step"
        log_success "Step trust removed"
    fi
    
    # Remove cert backups
    if [[ -d "/var/lib/auto-ssl/cert-backups" ]]; then
        log_step "Removing certificate backups..."
        rm -rf "/var/lib/auto-ssl/cert-backups"
        log_success "Backups removed"
    fi
    
    echo ""
    log_success "Server enrollment removed successfully"
    echo ""
    if [[ "$keep_certs" == true ]]; then
        echo "  Certificates preserved at: ${AUTO_SSL_CERT_DIR}"
    fi
    echo ""
    log_info "To re-enroll, run: sudo auto-ssl server enroll ..."
}

#--------------------------------------------------
# Helper functions
#--------------------------------------------------

_install_step_cli() {
    local distro
    distro=$(detect_distro)
    local arch
    arch=$(detect_arch)
    
    case "$distro" in
        rhel)
            log_info "Installing step CLI for RHEL-based system..."
            local rpm_url="https://github.com/smallstep/cli/releases/latest/download/step-cli_${arch}.rpm"
            curl -sLO "$rpm_url"
            dnf install -y "./step-cli_${arch}.rpm" 2>/dev/null || yum install -y "./step-cli_${arch}.rpm"
            rm -f "./step-cli_${arch}.rpm"
            ;;
        debian)
            log_info "Installing step CLI for Debian-based system..."
            local deb_url="https://github.com/smallstep/cli/releases/latest/download/step-cli_${arch}.deb"
            curl -sLO "$deb_url"
            dpkg -i "./step-cli_${arch}.deb" || apt-get install -f -y
            rm -f "./step-cli_${arch}.deb"
            ;;
        *)
            die "Unsupported distribution: $distro. Install step CLI manually."
            ;;
    esac
    
    if ! has_step_cli; then
        die "Failed to install step CLI"
    fi
    
    log_success "step CLI installed"
}

_setup_renewal_timer() {
    local cert_path="$1"
    local key_path="$2"
    
    # Create renewal service
    cat > /etc/systemd/system/auto-ssl-renew.service << EOF
[Unit]
Description=Renew auto-ssl certificate
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/step ca renew --force ${cert_path} ${key_path}
# Uncomment and modify to reload your web server:
# ExecStartPost=/usr/bin/systemctl reload nginx
# ExecStartPost=/usr/bin/systemctl reload caddy
EOF
    
    # Create renewal timer (every 5 days for 7-day certs)
    cat > /etc/systemd/system/auto-ssl-renew.timer << EOF
[Unit]
Description=Renew auto-ssl certificate periodically

[Timer]
# Run every 5 days
OnCalendar=*-*-01,06,11,16,21,26 00:00:00
# Add random delay up to 1 hour to avoid thundering herd
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Enable and start timer
    systemctl daemon-reload
    systemctl enable auto-ssl-renew.timer
    systemctl start auto-ssl-renew.timer
    
    log_success "Renewal timer configured (runs every 5 days)"
}

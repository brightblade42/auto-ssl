#!/usr/bin/env bash
# auto-ssl CA commands
# Commands for initializing and managing the Certificate Authority

#--------------------------------------------------
# Help
#--------------------------------------------------

cmd_ca_help() {
    cat << 'HELP'
auto-ssl ca - Certificate Authority management

USAGE
    auto-ssl ca <subcommand> [options]

SUBCOMMANDS
    init            Initialize this machine as the CA server
    status          Show CA health and configuration
    backup          Create encrypted backup of CA
    restore         Restore CA from backup
    reset           Remove CA and local auto-ssl state (start over)
    backup-schedule Configure automatic backups

EXAMPLES
    # Initialize CA with default settings
    sudo auto-ssl ca init --name "My Internal CA"

    # Initialize with custom settings
    sudo auto-ssl ca init \
        --name "My Internal CA" \
        --address "192.168.1.100:9000" \
        --cert-duration 7d \
        --max-duration 30d

    # Check CA status
    auto-ssl ca status

    # Create a backup
    sudo auto-ssl ca backup --output /backup/ca-backup.enc

    # Restore from backup
    sudo auto-ssl ca restore --input /backup/ca-backup.enc

HELP
}

cmd_ca_reset_help() {
    cat << 'HELP'
auto-ssl ca reset - Remove CA and local auto-ssl state (start over)

USAGE
    auto-ssl ca reset [options]

OPTIONS
    --yes           Skip confirmation prompts
    --no-backup     Do not create a safety backup before deleting data
    -h, --help      Show this help

EXAMPLES
    # Interactive reset with safety backup
    sudo auto-ssl ca reset

    # Non-interactive reset
    sudo auto-ssl ca reset --yes

HELP
}

cmd_ca_reset() {
    local assume_yes=false
    local create_backup=true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes)
                assume_yes=true
                shift
                ;;
            --no-backup)
                create_backup=false
                shift
                ;;
            -h|--help)
                cmd_ca_reset_help
                return 0
                ;;
            *)
                die_with_help "Unknown option: $1" "ca reset"
                ;;
        esac
    done

    require_root

    log_header "Resetting CA Server (Start Over)"

    if [[ "$assume_yes" != true ]]; then
        log_warning "This will stop CA services and delete local CA/config/cert state."
        if ! ui_confirm "Continue with CA reset?"; then
            log_info "Cancelled"
            return 1
        fi

        if ! ui_confirm "Final confirmation: DELETE local CA state now?"; then
            log_info "Cancelled"
            return 1
        fi
    fi

    if [[ "$create_backup" == true ]]; then
        local reset_backup_root="/var/lib/auto-ssl/reset-backups"
        local stamp
        stamp=$(date +%Y%m%d-%H%M%S)
        local reset_backup_dir="${reset_backup_root}/${stamp}"

        log_step "Creating safety backup at ${reset_backup_dir}..."
        mkdir -p "$reset_backup_dir"
        [[ -d "${STEP_CA_PATH}" ]] && cp -a "${STEP_CA_PATH}" "${reset_backup_dir}/step-ca" 2>/dev/null || true
        [[ -d "${AUTO_SSL_CONFIG_DIR}" ]] && cp -a "${AUTO_SSL_CONFIG_DIR}" "${reset_backup_dir}/config" 2>/dev/null || true
        [[ -d "${AUTO_SSL_CERT_DIR}" ]] && cp -a "${AUTO_SSL_CERT_DIR}" "${reset_backup_dir}/certs" 2>/dev/null || true
        log_success "Safety backup created"
    fi

    if command -v systemctl &>/dev/null; then
        log_step "Stopping services..."
        systemctl stop step-ca 2>/dev/null || true
        systemctl disable step-ca 2>/dev/null || true
        systemctl stop auto-ssl-renew.timer 2>/dev/null || true
        systemctl disable auto-ssl-renew.timer 2>/dev/null || true
    fi

    log_step "Removing service units..."
    rm -f /etc/systemd/system/step-ca.service
    rm -f /etc/systemd/system/auto-ssl-renew.service
    rm -f /etc/systemd/system/auto-ssl-renew.timer
    command -v systemctl &>/dev/null && systemctl daemon-reload 2>/dev/null || true

    log_step "Removing CA and auto-ssl local state..."
    rm -rf "${STEP_CA_PATH}"
    rm -rf "${AUTO_SSL_CONFIG_DIR}"
    rm -rf "${AUTO_SSL_CERT_DIR}"
    rm -rf "/var/lib/auto-ssl/cert-backups"
    rm -rf "/root/.step"
    [[ -d "${HOME}/.step" ]] && rm -rf "${HOME}/.step"

    echo ""
    log_success "CA reset complete"
    echo ""
    log_info "To start over, run: sudo auto-ssl ca init --name \"Internal CA\""
}

# Called when 'auto-ssl ca' is run without subcommand
cmd_ca() {
    cmd_ca_help
}

#--------------------------------------------------
# CA Init
#--------------------------------------------------

cmd_ca_init_help() {
    cat << 'HELP'
auto-ssl ca init - Initialize this machine as the CA server

USAGE
    auto-ssl ca init [options]

OPTIONS
    --name NAME           CA name (default: "Internal CA")
    --address ADDR        Listen address (default: <primary-ip>:9000)
    --cert-duration DUR   Default certificate duration (default: 168h / 7 days)
    --max-duration DUR    Maximum certificate duration (default: 720h / 30 days)
    --password-file FILE  Read CA password from file (or prompt if not specified)
    --non-interactive     Don't prompt for input (requires --password-file)
    -h, --help            Show this help

EXAMPLES
    # Interactive initialization
    sudo auto-ssl ca init --name "My Internal CA"

    # Non-interactive with password file
    sudo auto-ssl ca init \
        --name "My Internal CA" \
        --password-file /etc/step-ca/password \
        --non-interactive

HELP
}

cmd_ca_init() {
    local name="Internal CA"
    local address=""
    local cert_duration="168h"
    local max_duration="720h"
    local password_file=""
    local non_interactive=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            --address)
                address="$2"
                shift 2
                ;;
            --cert-duration)
                cert_duration="$2"
                shift 2
                ;;
            --max-duration)
                max_duration="$2"
                shift 2
                ;;
            --password-file)
                password_file="$2"
                shift 2
                ;;
            --non-interactive)
                non_interactive=true
                shift
                ;;
            -h|--help)
                cmd_ca_init_help
                return 0
                ;;
            *)
                die_with_help "Unknown option: $1" "ca init"
                ;;
        esac
    done
    
    require_root
    
    log_header "Initializing Certificate Authority"
    
    # Detect address if not specified
    if [[ -z "$address" ]]; then
        local ip
        ip=$(get_primary_ip) || die "Could not detect primary IP. Use --address to specify."
        address="${ip}:9000"
        log_info "Using detected address: $address"
    fi
    
    local ip_only="${address%:*}"
    local port="${address##*:}"
    
    # Check if CA already exists
    
    # Check if CA already exists
    if [[ -d "${STEP_CA_PATH}" ]] && [[ -f "${STEP_CA_CONFIG}" ]]; then
        log_warning "CA already initialized at ${STEP_CA_PATH}"
        if ! ui_confirm "Reinitialize? This will DESTROY the existing CA!"; then
            log_info "Cancelled"
            return 1
        fi
        
        # Create backup before destruction for rollback
        local backup_dir="/var/lib/auto-ssl/ca-init-backup"
        log_step "Creating safety backup..."
        mkdir -p "$backup_dir"
        cp -a "${STEP_CA_PATH}" "${backup_dir}/step-ca-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
        cp -a "${AUTO_SSL_CONFIG_DIR}" "${backup_dir}/config-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
        
        # Clean up old backups (keep last 2)
        (cd "$backup_dir" && ls -t | tail -n +5 | xargs -r rm -rf) 2>/dev/null || true
        
        rm -rf "${STEP_CA_PATH}"
    fi
    # Get or generate password
    local password
    if [[ -n "$password_file" ]]; then
        require_file "$password_file" "Password file"
        password=$(cat "$password_file")
    elif [[ "$non_interactive" == true ]]; then
        die "Non-interactive mode requires --password-file"
    else
        password=$(ui_password "Enter CA password (min 8 characters)")
        local password_confirm
        password_confirm=$(ui_password "Confirm CA password")
        
        if [[ "$password" != "$password_confirm" ]]; then
            die "Passwords do not match"
        fi
        
        if [[ ${#password} -lt 8 ]]; then
            die "Password must be at least 8 characters"
        fi
    fi
    
    # Install step-ca if needed
    if ! has_step_ca; then
        log_step "Installing step-ca..."
        _install_step_ca
    fi
    
    if ! has_step_cli; then
        log_step "Installing step CLI..."
        _install_step_cli
    fi
    
    # Create directories
    log_step "Creating directories..."
    mkdir -p "${STEP_CA_PATH}"
    chmod 700 "${STEP_CA_PATH}"
    mkdir -p "${AUTO_SSL_CONFIG_DIR}"
    chmod 755 "${AUTO_SSL_CONFIG_DIR}"
    
    # Store password securely
    log_step "Storing CA password..."
    local pw_file="${AUTO_SSL_CONFIG_DIR}/ca-password"
    printf '%s' "$password" > "$pw_file"
    chmod 600 "$pw_file"
    
    # Initialize CA
    log_step "Initializing CA: ${name}..."
    STEPPATH="${STEP_CA_PATH}" step ca init \
        --name "$name" \
        --address "${ip_only}:${port}" \
        --dns "$ip_only" \
        --provisioner "admin" \
        --password-file "$pw_file" \
        --provisioner-password-file "$pw_file"
    
    # Configure certificate duration
    log_step "Configuring certificate duration..."
    _configure_ca_duration "$cert_duration" "$max_duration"
    
    # Add ACME provisioner
    log_step "Adding ACME provisioner..."
    STEPPATH="${STEP_CA_PATH}" step ca provisioner add acme --type ACME
    
    # Create systemd service
    log_step "Creating systemd service..."
    _create_ca_service "$pw_file"
    
    # Get fingerprint
    local fingerprint
    fingerprint=$(step certificate fingerprint "${STEP_CA_PATH}/certs/root_ca.crt")
    
    # Save configuration
    log_step "Saving configuration..."
    cat > "${AUTO_SSL_CONFIG_DIR}/config.yaml" << EOF
ca:
  url: https://${address}
  fingerprint: ${fingerprint}
  name: ${name}
  steppath: ${STEP_CA_PATH}

defaults:
  cert_duration: ${cert_duration}
  max_cert_duration: ${max_duration}
EOF
    chmod 600 "${AUTO_SSL_CONFIG_DIR}/config.yaml"

    # Start the service
    log_step "Starting step-ca service..."
    systemctl daemon-reload
    systemctl enable step-ca
    systemctl start step-ca

    # Wait for CA to be ready (non-fatal; service may need extra time)
    if ! ui_spin_until "Waiting for CA to be ready" "curl -sk https://${address}/health" 45; then
        log_warning "CA health check did not become ready in time"
        log_info "Run 'auto-ssl ca status' in a few seconds to confirm service health"
    fi
    
    # Open firewall if firewalld is active
    if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
        log_step "Opening firewall port ${port}..."
        firewall-cmd --add-port="${port}/tcp" --permanent
        firewall-cmd --reload
    fi
    
    echo ""
    log_success "CA initialized successfully!"
    echo ""
    ui_box "Certificate Authority Information" "CA Name:        ${name}
CA URL:         https://${address}
Root CA:        ${STEP_CA_PATH}/certs/root_ca.crt
ACME Directory: https://${address}/acme/acme/directory

Root Fingerprint:
${fingerprint}

Save this fingerprint! You will need it for server enrollment.

Download root CA:
curl -k -o root_ca.crt https://${address}/roots.pem"
}

#--------------------------------------------------
# CA Status
#--------------------------------------------------

cmd_ca_status() {
    log_header "CA Status"

    # Recover config if CA exists but config.yaml is missing
    if [[ ! -f "${AUTO_SSL_CONFIG_DIR}/config.yaml" ]] && [[ -f "${STEP_CA_CONFIG}" ]] && [[ -f "${STEP_CA_PATH}/certs/root_ca.crt" ]]; then
        log_warning "Config file missing; attempting to recover from existing CA state..."

        local recovered_address=""
        if has_jq; then
            recovered_address=$(jq -r '.address // empty' "${STEP_CA_CONFIG}" 2>/dev/null || true)
        else
            recovered_address=$(grep -m1 '"address"' "${STEP_CA_CONFIG}" | sed 's/.*"address"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || true)
        fi

        local recovered_url=""
        [[ -n "$recovered_address" ]] && recovered_url="https://${recovered_address}"

        local recovered_fingerprint=""
        recovered_fingerprint=$(step certificate fingerprint "${STEP_CA_PATH}/certs/root_ca.crt" 2>/dev/null || true)

        local recovered_name="Internal CA"
        if command -v openssl &>/dev/null; then
            local subject
            subject=$(openssl x509 -in "${STEP_CA_PATH}/certs/root_ca.crt" -noout -subject 2>/dev/null || true)
            local cn
            cn=$(echo "$subject" | sed -n 's/.*CN[[:space:]]*=[[:space:]]*\([^,/]*\).*/\1/p')
            [[ -n "$cn" ]] && recovered_name="$cn"
        fi

        mkdir -p "${AUTO_SSL_CONFIG_DIR}"
        cat > "${AUTO_SSL_CONFIG_DIR}/config.yaml" << EOF
ca:
  url: ${recovered_url}
  fingerprint: ${recovered_fingerprint}
  name: ${recovered_name}
  steppath: ${STEP_CA_PATH}

defaults:
  cert_duration: 168h
  max_cert_duration: 720h
EOF
        chmod 600 "${AUTO_SSL_CONFIG_DIR}/config.yaml"
        log_success "Recovered CA config at ${AUTO_SSL_CONFIG_DIR}/config.yaml"
    fi
    
    # Check if CA is configured
    if [[ ! -f "${AUTO_SSL_CONFIG_DIR}/config.yaml" ]]; then
        log_warning "CA not configured on this machine"
        echo "Run 'auto-ssl ca init' to initialize a CA"
        return 1
    fi
    
    local ca_url
    ca_url=$(config_get "ca.url" "")
    
    # Check service status
    echo "Service Status:"
    if systemctl is-active step-ca &>/dev/null; then
        log_success "  step-ca is running"
    else
        log_error "  step-ca is not running"
    fi
    
    # Check health endpoint
    echo ""
    echo "Health Check:"
    if [[ -n "$ca_url" ]] && curl -sk "${ca_url}/health" &>/dev/null; then
        log_success "  CA is responding at ${ca_url}"
    else
        log_error "  CA is not responding"
    fi
    
    # Show configuration
    echo ""
    echo "Configuration:"
    echo "  CA URL:           $(config_get 'ca.url' 'not set')"
    echo "  CA Name:          $(config_get 'ca.name' 'not set')"
    echo "  Fingerprint:      $(config_get 'ca.fingerprint' 'not set')"
    echo "  Cert Duration:    $(config_get 'defaults.cert_duration' '168h')"
    echo "  Max Duration:     $(config_get 'defaults.max_cert_duration' '720h')"
    
    # Show certificate info
    if [[ -f "${STEP_CA_PATH}/certs/root_ca.crt" ]]; then
        echo ""
        echo "Root CA Certificate:"
        step certificate inspect "${STEP_CA_PATH}/certs/root_ca.crt" --short 2>/dev/null | sed 's/^/  /'
    fi
    
    # Show provisioners
    if has_step_cli && [[ -f "${STEP_CA_CONFIG}" ]]; then
        echo ""
        echo "Provisioners:"
        STEPPATH="${STEP_CA_PATH}" step ca provisioner list 2>/dev/null | sed 's/^/  /' || echo "  (unable to list)"
    fi
}

#--------------------------------------------------
# CA Backup
#--------------------------------------------------

cmd_ca_backup_help() {
    cat << 'HELP'
auto-ssl ca backup - Create encrypted backup of CA

USAGE
    auto-ssl ca backup [options]

OPTIONS
    --output FILE         Output file path (required)
    --passphrase-file F   Read encryption passphrase from file
    --dest-type TYPE      Destination type: local, rsync, s3 (default: local)
    --rsync-target HOST   rsync target (user@host:path)
    --s3-bucket BUCKET    S3/Wasabi bucket name
    --s3-endpoint URL     S3 endpoint URL (for Wasabi: https://s3.wasabisys.com)
    --s3-prefix PREFIX    S3 key prefix (default: auto-ssl/)
    -h, --help            Show this help

EXAMPLES
    # Local backup
    sudo auto-ssl ca backup --output /backup/ca-backup.enc

    # Backup to rsync target
    sudo auto-ssl ca backup \
        --output ca-backup.enc \
        --dest-type rsync \
        --rsync-target user@backup-server:/backups/

    # Backup to Wasabi S3
    sudo auto-ssl ca backup \
        --output ca-backup.enc \
        --dest-type s3 \
        --s3-bucket my-backups \
        --s3-endpoint https://s3.wasabisys.com

HELP
}

cmd_ca_backup() {
    local output=""
    local passphrase_file=""
    local dest_type="local"
    local rsync_target=""
    local s3_bucket=""
    local s3_endpoint=""
    local s3_prefix="auto-ssl/"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output)
                output="$2"
                shift 2
                ;;
            --passphrase-file)
                passphrase_file="$2"
                shift 2
                ;;
            --dest-type)
                dest_type="$2"
                shift 2
                ;;
            --rsync-target)
                rsync_target="$2"
                shift 2
                ;;
            --s3-bucket)
                s3_bucket="$2"
                shift 2
                ;;
            --s3-endpoint)
                s3_endpoint="$2"
                shift 2
                ;;
            --s3-prefix)
                s3_prefix="$2"
                shift 2
                ;;
            -h|--help)
                cmd_ca_backup_help
                return 0
                ;;
            *)
                die_with_help "Unknown option: $1" "ca backup"
                ;;
        esac
    done
    
    require_root
    
    [[ -z "$output" ]] && die "Output file required. Use --output FILE"
    require_dir "${STEP_CA_PATH}" "CA directory"
    
    log_header "Creating CA Backup"
    
    # Get passphrase
    local passphrase
    if [[ -n "$passphrase_file" ]]; then
        require_file "$passphrase_file" "Passphrase file"
        passphrase=$(cat "$passphrase_file")
    else
        passphrase=$(ui_password "Enter backup passphrase")
        local passphrase_confirm
        passphrase_confirm=$(ui_password "Confirm passphrase")
        
        if [[ "$passphrase" != "$passphrase_confirm" ]]; then
            die "Passphrases do not match"
        fi
    fi
    
    # Create temporary directory for backup
    local tmp_dir
    tmp_dir=$(mktemp -d)
    cleanup_add "rm -rf '$tmp_dir'"
    
    # Stop CA briefly for consistent backup
    log_step "Stopping CA for consistent backup..."
    systemctl stop step-ca || true
    
    # Create metadata
    log_step "Creating backup metadata..."
    cat > "${tmp_dir}/metadata.json" << EOF
{
    "version": "${AUTO_SSL_VERSION}",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "ca_url": "$(config_get 'ca.url' '')",
    "ca_name": "$(config_get 'ca.name' '')",
    "hostname": "$(hostname)",
    "ip_address": "$(get_primary_ip || echo 'unknown')"
}
EOF
    
    # Copy CA data
    log_step "Copying CA data..."
    cp -a "${STEP_CA_PATH}" "${tmp_dir}/step-ca"
    cp -a "${AUTO_SSL_CONFIG_DIR}" "${tmp_dir}/config"
    
    # Restart CA
    log_step "Restarting CA..."
    systemctl start step-ca
    
    # Create archive
    log_step "Creating archive..."
    local archive="${tmp_dir}/backup.tar.gz"
    tar -czf "$archive" -C "$tmp_dir" metadata.json step-ca config
    
    # Encrypt archive
    log_step "Encrypting backup..."
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "$archive" \
        -out "${tmp_dir}/backup.enc" \
        -pass "pass:${passphrase}"

    local size
    size=$(du -h "${tmp_dir}/backup.enc" | cut -f1)
    
    # Handle destination
    case "$dest_type" in
        local)
            local output_dir
            output_dir=$(dirname "$output")
            [[ -n "$output_dir" ]] && mkdir -p "$output_dir"
            log_step "Saving to ${output}..."
            mv "${tmp_dir}/backup.enc" "$output"
            chmod 600 "$output"
            ;;
        rsync)
            [[ -z "$rsync_target" ]] && die "rsync target required. Use --rsync-target"
            log_step "Uploading via rsync to ${rsync_target}..."
            rsync -avz "${tmp_dir}/backup.enc" "${rsync_target}/${output##*/}"
            ;;
        s3)
            [[ -z "$s3_bucket" ]] && die "S3 bucket required. Use --s3-bucket"
            require_command "aws" "Install AWS CLI: pip install awscli"
            log_step "Uploading to S3 bucket ${s3_bucket}..."
            local aws_args=()
            [[ -n "$s3_endpoint" ]] && aws_args+=(--endpoint-url "$s3_endpoint")
            aws "${aws_args[@]}" s3 cp "${tmp_dir}/backup.enc" "s3://${s3_bucket}/${s3_prefix}${output##*/}"
            ;;
        *)
            die "Unknown destination type: $dest_type"
            ;;
    esac
    
    echo ""
    log_success "Backup created successfully!"
    echo ""
    echo "  Destination: ${dest_type}"
    echo "  Output:      ${output}"
    echo "  Size:        ${size}"
    echo ""
    log_warning "Store this backup securely! It contains your CA private keys."
}

#--------------------------------------------------
# CA Restore
#--------------------------------------------------

cmd_ca_restore_help() {
    cat << 'HELP'
auto-ssl ca restore - Restore CA from backup

USAGE
    auto-ssl ca restore [options]

OPTIONS
    --input FILE          Input backup file (required)
    --passphrase-file F   Read decryption passphrase from file
    --new-address ADDR    Use new address (if CA IP changed)
    -h, --help            Show this help

EXAMPLES
    # Restore from local backup
    sudo auto-ssl ca restore --input /backup/ca-backup.enc

    # Restore with new IP address
    sudo auto-ssl ca restore \
        --input /backup/ca-backup.enc \
        --new-address 192.168.1.200:9000

HELP
}

cmd_ca_restore() {
    local input=""
    local passphrase_file=""
    local new_address=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input)
                input="$2"
                shift 2
                ;;
            --passphrase-file)
                passphrase_file="$2"
                shift 2
                ;;
            --new-address)
                new_address="$2"
                shift 2
                ;;
            -h|--help)
                cmd_ca_restore_help
                return 0
                ;;
            *)
                die_with_help "Unknown option: $1" "ca restore"
                ;;
        esac
    done
    
    require_root
    
    [[ -z "$input" ]] && die "Input file required. Use --input FILE"
    require_file "$input" "Backup file"
    
    log_header "Restoring CA from Backup"
    
    # Get passphrase
    local passphrase
    if [[ -n "$passphrase_file" ]]; then
        require_file "$passphrase_file" "Passphrase file"
        passphrase=$(cat "$passphrase_file")
    else
        passphrase=$(ui_password "Enter backup passphrase")
    fi
    
    # Check for existing CA
    if [[ -d "${STEP_CA_PATH}" ]]; then
        log_warning "Existing CA found at ${STEP_CA_PATH}"
        if ! ui_confirm "Overwrite existing CA?"; then
            log_info "Cancelled"
            return 1
        fi
        
        # Stop existing CA
        systemctl stop step-ca 2>/dev/null || true
    fi
    
    # Create temporary directory
    local tmp_dir
    tmp_dir=$(mktemp -d)
    cleanup_add "rm -rf '$tmp_dir'"
    
    # Decrypt backup
    log_step "Decrypting backup..."
    if ! openssl enc -d -aes-256-cbc -pbkdf2 \
        -in "$input" \
        -out "${tmp_dir}/backup.tar.gz" \
        -pass "pass:${passphrase}" 2>/dev/null; then
        die "Failed to decrypt backup. Wrong passphrase?"
    fi
    
    # Extract archive
    log_step "Extracting archive..."
    tar -xzf "${tmp_dir}/backup.tar.gz" -C "$tmp_dir"
    
    # Show metadata
    if [[ -f "${tmp_dir}/metadata.json" ]]; then
        echo ""
        echo "Backup Information:"
        cat "${tmp_dir}/metadata.json" | sed 's/^/  /'
        echo ""
    fi
    
    # Check for IP change
    local original_url
    original_url=$(grep -o '"ca_url": "[^"]*"' "${tmp_dir}/metadata.json" 2>/dev/null | cut -d'"' -f4 || echo "")
    local current_ip
    current_ip=$(get_primary_ip || echo "")
    
    if [[ -n "$original_url" ]] && [[ -z "$new_address" ]]; then
        local original_ip="${original_url#https://}"
        original_ip="${original_ip%:*}"
        
        if [[ "$original_ip" != "$current_ip" ]]; then
            log_warning "IP address has changed!"
            echo "  Original: ${original_ip}"
            echo "  Current:  ${current_ip}"
            echo ""
            
            if ui_confirm "Update CA to use current IP (${current_ip})?"; then
                new_address="${current_ip}:9000"
            fi
        fi
    fi
    
    # Restore files
    log_step "Restoring CA files..."
    rm -rf "${STEP_CA_PATH}"
    mv "${tmp_dir}/step-ca" "${STEP_CA_PATH}"
    chmod 700 "${STEP_CA_PATH}"
    
    rm -rf "${AUTO_SSL_CONFIG_DIR}"
    mv "${tmp_dir}/config" "${AUTO_SSL_CONFIG_DIR}"
    chmod 755 "${AUTO_SSL_CONFIG_DIR}"
    
    # Update address if needed
    if [[ -n "$new_address" ]]; then
        log_step "Updating CA address to ${new_address}..."
        local new_ip="${new_address%:*}"
        local new_port="${new_address##*:}"
        
        # Update ca.json
        if has_jq; then
            local tmp_config
            tmp_config=$(mktemp)
            jq ".address = \"${new_address}\" | .dnsNames = [\"${new_ip}\"]" \
                "${STEP_CA_CONFIG}" > "$tmp_config"
            mv "$tmp_config" "${STEP_CA_CONFIG}"
        else
            # Fallback: sed
            sed -i "s/\"address\": \"[^\"]*\"/\"address\": \"${new_address}\"/" "${STEP_CA_CONFIG}"
        fi
        
        # Update auto-ssl config
        config_set "ca.url" "https://${new_address}"
    fi
    
    # Recreate systemd service
    log_step "Setting up systemd service..."
    local pw_file="${AUTO_SSL_CONFIG_DIR}/ca-password"
    _create_ca_service "$pw_file"
    
    # Start CA
    log_step "Starting CA..."
    systemctl daemon-reload
    systemctl enable step-ca
    systemctl start step-ca
    
    # Wait for CA
    local ca_url
    ca_url=$(config_get "ca.url" "")
    ui_spin_until "Waiting for CA to be ready" "curl -sk ${ca_url}/health" 30
    
    echo ""
    log_success "CA restored successfully!"
    echo ""
    echo "  CA URL: ${ca_url}"
    echo ""
    
    if [[ -n "$new_address" ]]; then
        log_warning "CA address changed. Update enrolled servers with:"
        echo "  auto-ssl remote update-ca-url --new-url ${ca_url}"
    fi
}

#--------------------------------------------------
# Backup Schedule
#--------------------------------------------------

cmd_ca_backup_schedule_help() {
    cat << 'HELP'
auto-ssl ca backup-schedule - Configure automatic backups

USAGE
    auto-ssl ca backup-schedule [options]

OPTIONS
    --enable              Enable scheduled backups
    --disable             Disable scheduled backups
    --schedule SCHEDULE   Backup schedule: daily, weekly, monthly (default: weekly)
    --output DIR          Backup output directory (default: /var/backups/auto-ssl)
    --retention NUM       Number of backups to keep (default: 4)
    --passphrase-file F   Passphrase file for encryption
    -h, --help            Show this help

EXAMPLES
    # Enable weekly backups
    sudo auto-ssl ca backup-schedule --enable --schedule weekly

    # Enable daily backups with passphrase
    sudo auto-ssl ca backup-schedule --enable \
        --schedule daily \
        --passphrase-file /etc/auto-ssl/backup-passphrase

    # Disable backups
    sudo auto-ssl ca backup-schedule --disable

HELP
}

cmd_ca_backup_schedule() {
    local enable=false
    local disable=false
    local schedule="weekly"
    local output_dir="/var/backups/auto-ssl"
    local retention=4
    local passphrase_file=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --enable)
                enable=true
                shift
                ;;
            --disable)
                disable=true
                shift
                ;;
            --schedule)
                schedule="$2"
                shift 2
                ;;
            --output)
                output_dir="$2"
                shift 2
                ;;
            --retention)
                retention="$2"
                shift 2
                ;;
            --passphrase-file)
                passphrase_file="$2"
                shift 2
                ;;
            -h|--help)
                cmd_ca_backup_schedule_help
                return 0
                ;;
            *)
                die_with_help "Unknown option: $1" "ca backup-schedule"
                ;;
        esac
    done
    
    require_root
    
    if [[ "$disable" == true ]]; then
        _disable_backup_schedule
        return 0
    fi
    
    if [[ "$enable" != true ]]; then
        # Show current status
        _show_backup_schedule_status
        return 0
    fi
    
    # Enable backups
    log_header "Configuring Automatic Backups"
    
    # Validate schedule
    local calendar_spec
    case "$schedule" in
        daily)
            calendar_spec="*-*-* 02:00:00"
            ;;
        weekly)
            calendar_spec="Sun *-*-* 02:00:00"
            ;;
        monthly)
            calendar_spec="*-*-01 02:00:00"
            ;;
        *)
            die "Invalid schedule: $schedule. Use daily, weekly, or monthly."
            ;;
    esac
    
    # Create output directory
    log_step "Creating backup directory..."
    mkdir -p "$output_dir"
    chmod 700 "$output_dir"
    
    # Get or create passphrase
    if [[ -z "$passphrase_file" ]]; then
        passphrase_file="${AUTO_SSL_CONFIG_DIR}/backup-passphrase"
        if [[ ! -f "$passphrase_file" ]]; then
            log_step "Generating backup passphrase..."
            random_string 32 > "$passphrase_file"
            chmod 600 "$passphrase_file"
            log_warning "Passphrase saved to: ${passphrase_file}"
            log_warning "SAVE THIS FILE SECURELY! You'll need it to restore backups."
        fi
    else
        require_file "$passphrase_file" "Passphrase file"
    fi
    
    # Create backup script
    log_step "Creating backup script..."
    local backup_script="/usr/local/bin/auto-ssl-backup"
    cat > "$backup_script" << 'SCRIPT'
#!/usr/bin/env bash
# Auto-generated backup script for auto-ssl

set -euo pipefail

OUTPUT_DIR="__OUTPUT_DIR__"
RETENTION=__RETENTION__
PASSPHRASE_FILE="__PASSPHRASE_FILE__"

# Generate filename with timestamp
FILENAME="ca-backup-$(date +%Y%m%d-%H%M%S).enc"
OUTPUT="${OUTPUT_DIR}/${FILENAME}"

# Run backup
/usr/local/bin/auto-ssl ca backup \
    --output "$OUTPUT" \
    --passphrase-file "$PASSPHRASE_FILE"

# Rotate old backups
cd "$OUTPUT_DIR"
ls -t ca-backup-*.enc 2>/dev/null | tail -n +$((RETENTION + 1)) | xargs -r rm -f

echo "Backup complete: ${OUTPUT}"
SCRIPT
    
    # Replace placeholders
    sed -i "s|__OUTPUT_DIR__|${output_dir}|g" "$backup_script"
    sed -i "s|__RETENTION__|${retention}|g" "$backup_script"
    sed -i "s|__PASSPHRASE_FILE__|${passphrase_file}|g" "$backup_script"
    chmod 755 "$backup_script"
    
    # Create systemd service
    log_step "Creating systemd service..."
    cat > /etc/systemd/system/auto-ssl-backup.service << EOF
[Unit]
Description=auto-ssl CA backup
After=step-ca.service

[Service]
Type=oneshot
ExecStart=${backup_script}
StandardOutput=journal
StandardError=journal
EOF
    
    # Create systemd timer
    log_step "Creating systemd timer..."
    cat > /etc/systemd/system/auto-ssl-backup.timer << EOF
[Unit]
Description=Automatic CA backup for auto-ssl

[Timer]
OnCalendar=${calendar_spec}
# Add random delay up to 1 hour
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    # Enable and start timer
    log_step "Enabling backup timer..."
    systemctl daemon-reload
    systemctl enable auto-ssl-backup.timer
    systemctl start auto-ssl-backup.timer
    
    # Save configuration
    config_set "backup.enabled" "true"
    config_set "backup.schedule" "$schedule"
    config_set "backup.output_dir" "$output_dir"
    config_set "backup.retention" "$retention"
    config_set "backup.passphrase_file" "$passphrase_file"
    
    echo ""
    log_success "Automatic backups configured!"
    echo ""
    echo "  Schedule:      ${schedule} (${calendar_spec})"
    echo "  Output:        ${output_dir}"
    echo "  Retention:     ${retention} backups"
    echo "  Passphrase:    ${passphrase_file}"
    echo ""
    echo "Next backup:"
    systemctl list-timers auto-ssl-backup.timer --no-pager | tail -2
    echo ""
    log_warning "Make sure to securely store ${passphrase_file}!"
}

_disable_backup_schedule() {
    log_header "Disabling Automatic Backups"
    
    if systemctl is-active auto-ssl-backup.timer &>/dev/null; then
        log_step "Stopping backup timer..."
        systemctl stop auto-ssl-backup.timer
        systemctl disable auto-ssl-backup.timer
        log_success "Backup timer disabled"
    else
        log_info "Backup timer was not active"
    fi
    
    config_set "backup.enabled" "false"
}

_show_backup_schedule_status() {
    log_header "Backup Schedule Status"
    
    local enabled
    enabled=$(config_get "backup.enabled" "false")
    
    if [[ "$enabled" == "true" ]]; then
        log_success "Automatic backups: Enabled"
        echo ""
        echo "  Schedule:      $(config_get 'backup.schedule' 'weekly')"
        echo "  Output:        $(config_get 'backup.output_dir' '/var/backups/auto-ssl')"
        echo "  Retention:     $(config_get 'backup.retention' '4') backups"
        echo ""
        echo "Timer Status:"
        systemctl status auto-ssl-backup.timer --no-pager 2>/dev/null | head -5 | sed 's/^/  /'
        echo ""
        echo "Next backup:"
        systemctl list-timers auto-ssl-backup.timer --no-pager 2>/dev/null | tail -2 | sed 's/^/  /'
    else
        log_warning "Automatic backups: Disabled"
        echo ""
        echo "Enable with: sudo auto-ssl ca backup-schedule --enable"
    fi
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
            dnf install -y "./step-cli_${arch}.rpm" || yum install -y "./step-cli_${arch}.rpm"
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
    
    log_success "step CLI installed: $(step version | head -1)"
}

_install_step_ca() {
    local distro
    distro=$(detect_distro)
    local arch
    arch=$(detect_arch)
    
    case "$distro" in
        rhel)
            log_info "Installing step-ca for RHEL-based system..."
            local rpm_url="https://github.com/smallstep/certificates/releases/latest/download/step-ca_${arch}.rpm"
            curl -sLO "$rpm_url"
            dnf install -y "./step-ca_${arch}.rpm" || yum install -y "./step-ca_${arch}.rpm"
            rm -f "./step-ca_${arch}.rpm"
            ;;
        debian)
            log_info "Installing step-ca for Debian-based system..."
            local deb_url="https://github.com/smallstep/certificates/releases/latest/download/step-ca_${arch}.deb"
            curl -sLO "$deb_url"
            dpkg -i "./step-ca_${arch}.deb" || apt-get install -f -y
            rm -f "./step-ca_${arch}.deb"
            ;;
        *)
            die "Unsupported distribution: $distro. Install step-ca manually."
            ;;
    esac
    
    if ! has_step_ca; then
        die "Failed to install step-ca"
    fi
    
    log_success "step-ca installed: $(step-ca version | head -1)"
}

_configure_ca_duration() {
    local cert_duration="$1"
    local max_duration="$2"
    
    # Convert to Go duration format if needed
    # step-ca expects format like "168h0m0s"
    
    if has_jq; then
        local tmp_config
        tmp_config=$(mktemp)
        
        jq ".authority.claims.defaultTLSCertDuration = \"${cert_duration}\" | .authority.claims.maxTLSCertDuration = \"${max_duration}\"" \
            "${STEP_CA_CONFIG}" > "$tmp_config"
        mv "$tmp_config" "${STEP_CA_CONFIG}"
    else
        log_warning "jq not installed, skipping duration configuration"
        log_info "Install jq and rerun, or manually edit ${STEP_CA_CONFIG}"
    fi
}

_create_ca_service() {
    local password_file="$1"
    
    cat > /etc/systemd/system/step-ca.service << EOF
[Unit]
Description=Smallstep CA
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=STEPPATH=${STEP_CA_PATH}
ExecStart=/usr/bin/step-ca --password-file=${password_file} ${STEP_CA_CONFIG}
Restart=on-failure
RestartSec=5

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=${STEP_CA_PATH}
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF
}

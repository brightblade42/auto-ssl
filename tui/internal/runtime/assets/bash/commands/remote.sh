#!/usr/bin/env bash
# auto-ssl remote commands
# Commands for managing remote servers via SSH from the CA server

#--------------------------------------------------
# Help
#--------------------------------------------------

cmd_remote_help() {
    cat << 'HELP'
auto-ssl remote - Remote server management via SSH

These commands are run from the CA server to manage remote servers.

USAGE
    auto-ssl remote <subcommand> [options]

SUBCOMMANDS
    enroll          Enroll a remote server via SSH
    status          Check remote server certificate status
    update-ca-url   Update CA URL on enrolled servers (after CA migration)
    list            List enrolled servers

PREREQUISITES
    - SSH key-based authentication to target servers
    - sudo access on target servers
    - Network access from CA to target servers

EXAMPLES
    # Enroll a remote server
    auto-ssl remote enroll --host 192.168.1.50 --user ryan

    # Check status of remote server
    auto-ssl remote status --host 192.168.1.50 --user ryan

    # Update CA URL on all servers after migration
    auto-ssl remote update-ca-url --new-url https://192.168.1.200:9000

HELP
}

cmd_remote() {
    cmd_remote_help
}

#--------------------------------------------------
# Inventory helpers
#--------------------------------------------------

INVENTORY_FILE="${AUTO_SSL_CONFIG_DIR}/servers.yaml"

_inventory_add() {
    local host="$1"
    local name="$2"
    local user="$3"
    
    ensure_dirs
    
    # Simple YAML append/update (proper YAML library would be better)
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        echo "servers:" > "$INVENTORY_FILE"
    fi

    # Remove existing block for this host if present
    if grep -q "host: ${host}$" "$INVENTORY_FILE" 2>/dev/null; then
        log_info "Server ${host} already in inventory, updating..."
        local tmp_inventory
        tmp_inventory=$(mktemp)
        awk -v host="$host" '
            /^  - host: / {
                skip = ($0 ~ "^  - host: " host "$")
            }
            skip && /^  - host: / && $0 !~ "^  - host: " host "$" {
                skip = 0
            }
            !skip { print }
        ' "$INVENTORY_FILE" > "$tmp_inventory"
        mv "$tmp_inventory" "$INVENTORY_FILE"
    fi
    
    cat >> "$INVENTORY_FILE" << EOF
  - host: ${host}
    name: ${name}
    user: ${user}
    enrolled: true
    enrolled_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    chmod 600 "$INVENTORY_FILE"
}

_inventory_list() {
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        echo "No servers enrolled"
        return
    fi
    
    # Simple parsing (proper YAML library would be better)
    grep -E "^\s+-\s*host:|^\s+name:|^\s+enrolled:|^\s+user:" "$INVENTORY_FILE" | \
    paste - - - - | \
    sed 's/host:/\nHost:/g; s/name:/Name:/g; s/enrolled:/Enrolled:/g; s/user:/User:/g'
}

#--------------------------------------------------
# Remote Enroll
#--------------------------------------------------

cmd_remote_enroll_help() {
    cat << 'HELP'
auto-ssl remote enroll - Enroll a remote server via SSH

USAGE
    auto-ssl remote enroll [options]

OPTIONS
    --host HOST           Target server hostname or IP (required)
    --user USER           SSH username (required)
    --name NAME           Friendly name for the server (default: hostname)
    --port PORT           SSH port (default: 22)
    --san NAME            Additional SAN for the certificate (can repeat)
    --identity FILE       SSH identity file (default: ~/.ssh/id_rsa)
    -h, --help            Show this help

EXAMPLES
    # Basic enrollment
    auto-ssl remote enroll --host 192.168.1.50 --user ryan

    # With custom name and additional SANs
    auto-ssl remote enroll \
        --host 192.168.1.50 \
        --user ryan \
        --name web-server-1 \
        --san myserver.local

HELP
}

cmd_remote_enroll() {
    local host=""
    local user=""
    local name=""
    local port="22"
    local sans=()
    local identity=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)
                host="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            --name)
                name="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --san)
                sans+=("$2")
                shift 2
                ;;
            --identity)
                identity="$2"
                shift 2
                ;;
            -h|--help)
                cmd_remote_enroll_help
                return 0
                ;;
            *)
                die_with_help "Unknown option: $1" "remote enroll"
                ;;
        esac
    done
    
    # Validate
    [[ -z "$host" ]] && die "Host required. Use --host HOST"
    [[ -z "$user" ]] && die "User required. Use --user USER"
    [[ -z "$name" ]] && name="$host"
    
    # Check we're on the CA server
    if ! is_ca_server; then
        die "This command must be run from the CA server"
    fi
    
    # Get CA info
    local ca_url
    ca_url=$(config_get "ca.url" "")
    local fingerprint
    fingerprint=$(config_get "ca.fingerprint" "")
    
    [[ -z "$ca_url" ]] && die "CA URL not configured"
    [[ -z "$fingerprint" ]] && die "CA fingerprint not configured"
    
    log_header "Remote Enrollment: ${host}"
    
    # Build SSH command
    local ssh_opts=(-o "StrictHostKeyChecking=accept-new" -p "$port")
    [[ -n "$identity" ]] && ssh_opts+=(-i "$identity")
    
    local ssh_target="${user}@${host}"
    
    # Test SSH connection
    log_step "Testing SSH connection..."
    if ! ssh "${ssh_opts[@]}" "$ssh_target" "echo 'SSH OK'" &>/dev/null; then
        die "Cannot connect to ${ssh_target} via SSH"
    fi
    log_success "SSH connection successful"
    
    # Detect remote OS
    log_step "Detecting remote OS..."
    local remote_os
    remote_os=$(ssh "${ssh_opts[@]}" "$ssh_target" "cat /etc/os-release 2>/dev/null | grep ^ID= | cut -d= -f2 | tr -d '\"'" || echo "unknown")
    log_info "Remote OS: ${remote_os}"
    
    # Copy auto-ssl runtime to remote host
    log_step "Copying auto-ssl runtime to remote server..."
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    local bundle_dir
    bundle_dir=$(mktemp -d)
    cleanup_add "rm -rf '$bundle_dir'"

    mkdir -p "${bundle_dir}/auto-ssl-lib" "${bundle_dir}/auto-ssl-commands"
    cp "${script_dir}/../auto-ssl" "${bundle_dir}/auto-ssl"
    cp "${script_dir}/../lib/"*.sh "${bundle_dir}/auto-ssl-lib/"
    cp "${script_dir}/"*.sh "${bundle_dir}/auto-ssl-commands/"
    chmod 755 "${bundle_dir}/auto-ssl"

    local tmp_tar
    tmp_tar=$(mktemp)
    cleanup_add "rm -f '$tmp_tar'"
    tar -C "$bundle_dir" -czf "$tmp_tar" .

    scp "${ssh_opts[@]}" "$tmp_tar" "${ssh_target}:/tmp/auto-ssl-runtime.tgz"
    ssh "${ssh_opts[@]}" "$ssh_target" "rm -rf /tmp/auto-ssl-runtime && mkdir -p /tmp/auto-ssl-runtime && tar -xzf /tmp/auto-ssl-runtime.tgz -C /tmp/auto-ssl-runtime && chmod +x /tmp/auto-ssl-runtime/auto-ssl"
    
    # Build SAN arguments
    local san_args=""
    for san in "${sans[@]}"; do
        san_args+=" --san $san"
    done
    
    # Get provisioner password
    local pw_file="${AUTO_SSL_CONFIG_DIR}/ca-password"
    local password=""
    if [[ -f "$pw_file" ]]; then
        password=$(cat "$pw_file")
    else
        password=$(ui_password "Enter provisioner password")
    fi
    
    # Run enrollment on remote server
    log_step "Running enrollment on remote server..."
    
    # More secure: pass password via stdin to enrollment command
    # Create enrollment command that reads password from stdin
    local enroll_cmd="sudo /tmp/auto-ssl-runtime/auto-ssl server enroll \
        --ca-url '${ca_url}' \
        --fingerprint '${fingerprint}' \
        --password-file /dev/stdin \
        --non-interactive \
        ${san_args}"
    
    # Pass password securely through stdin
    if echo "$password" | ssh "${ssh_opts[@]}" "$ssh_target" "$enroll_cmd"; then
        log_success "Remote enrollment successful"
    else
        ssh "${ssh_opts[@]}" "$ssh_target" "rm -rf /tmp/auto-ssl-runtime /tmp/auto-ssl-runtime.tgz" 2>/dev/null || true
        die "Remote enrollment failed"
    fi
    
    # Install runtime to permanent location
    log_step "Installing auto-ssl on remote server..."
    ssh "${ssh_opts[@]}" "$ssh_target" "sudo install -d /usr/local/bin/auto-ssl-lib /usr/local/bin/auto-ssl-commands && sudo install -m 755 /tmp/auto-ssl-runtime/auto-ssl /usr/local/bin/auto-ssl && sudo install -m 644 /tmp/auto-ssl-runtime/auto-ssl-lib/*.sh /usr/local/bin/auto-ssl-lib/ && sudo install -m 644 /tmp/auto-ssl-runtime/auto-ssl-commands/*.sh /usr/local/bin/auto-ssl-commands/ && rm -rf /tmp/auto-ssl-runtime /tmp/auto-ssl-runtime.tgz"
    
    # Add to inventory
    log_step "Adding to inventory..."
    _inventory_add "$host" "$name" "$user"
    
    echo ""
    log_success "Server ${host} enrolled successfully!"
    echo ""
    echo "  Name:     ${name}"
    echo "  Host:     ${host}"
    echo "  User:     ${user}"
    echo ""
    echo "The server now has valid certificates and automatic renewal configured."
}

#--------------------------------------------------
# Remote Status
#--------------------------------------------------

cmd_remote_status_help() {
    cat << 'HELP'
auto-ssl remote status - Check remote server certificate status

USAGE
    auto-ssl remote status [options]

OPTIONS
    --host HOST           Target server (required unless --all)
    --user USER           SSH username (required unless --all)
    --all                 Check all enrolled servers
    --port PORT           SSH port (default: 22)
    -h, --help            Show this help

EXAMPLES
    # Check single server
    auto-ssl remote status --host 192.168.1.50 --user ryan

    # Check all enrolled servers
    auto-ssl remote status --all

HELP
}

cmd_remote_status() {
    local host=""
    local user=""
    local all=false
    local port="22"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)
                host="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            --all)
                all=true
                shift
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            -h|--help)
                cmd_remote_status_help
                return 0
                ;;
            *)
                die_with_help "Unknown option: $1" "remote status"
                ;;
        esac
    done
    
    if [[ "$all" == true ]]; then
        log_header "All Enrolled Servers"
        
        if [[ ! -f "$INVENTORY_FILE" ]]; then
            echo "No servers enrolled"
            return
        fi
        
        # Parse inventory and check each server
        # (simplified - proper YAML parsing would be better)
        while IFS= read -r line; do
            if [[ "$line" =~ host:\ *(.+) ]]; then
                local h="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ user:\ *(.+) ]]; then
                local u="${BASH_REMATCH[1]}"
                if [[ -n "$h" ]] && [[ -n "$u" ]]; then
                    echo ""
                    echo "Checking ${h}..."
                    _check_remote_status "$h" "$u" "$port" || true
                fi
            fi
        done < "$INVENTORY_FILE"
    else
        [[ -z "$host" ]] && die "Host required. Use --host HOST or --all"
        [[ -z "$user" ]] && die "User required. Use --user USER"
        
        log_header "Remote Status: ${host}"
        _check_remote_status "$host" "$user" "$port"
    fi
}

_check_remote_status() {
    local host="$1"
    local user="$2"
    local port="$3"
    
    local ssh_opts=(-o "ConnectTimeout=5" -o "StrictHostKeyChecking=accept-new" -p "$port")
    local ssh_target="${user}@${host}"
    
    if ! ssh "${ssh_opts[@]}" "$ssh_target" "true" &>/dev/null; then
        log_error "Cannot connect to ${host}"
        return 1
    fi
    
    # Check certificate
    local cert_info
    cert_info=$(ssh "${ssh_opts[@]}" "$ssh_target" \
        "sudo cat /etc/ssl/auto-ssl/server.crt 2>/dev/null | openssl x509 -noout -subject -enddate 2>/dev/null" || echo "")
    
    if [[ -z "$cert_info" ]]; then
        log_warning "No certificate found on ${host}"
        return 1
    fi
    
    echo "$cert_info" | sed 's/^/  /'
    
    # Check renewal timer
    local timer_status
    timer_status=$(ssh "${ssh_opts[@]}" "$ssh_target" \
        "systemctl is-active auto-ssl-renew.timer 2>/dev/null" || echo "inactive")
    
    if [[ "$timer_status" == "active" ]]; then
        log_success "  Renewal timer: active"
    else
        log_warning "  Renewal timer: ${timer_status}"
    fi
}

#--------------------------------------------------
# Remote Update CA URL
#--------------------------------------------------

cmd_remote_update_ca_url_help() {
    cat << 'HELP'
auto-ssl remote update-ca-url - Update CA URL on enrolled servers

Use this after migrating the CA to a new IP address.

USAGE
    auto-ssl remote update-ca-url [options]

OPTIONS
    --new-url URL         New CA URL (required)
    --host HOST           Update single host (default: all enrolled)
    --user USER           SSH username (required if --host)
    -h, --help            Show this help

EXAMPLES
    # Update all servers
    auto-ssl remote update-ca-url --new-url https://192.168.1.200:9000

    # Update single server
    auto-ssl remote update-ca-url \
        --new-url https://192.168.1.200:9000 \
        --host 192.168.1.50 \
        --user ryan

HELP
}

cmd_remote_update_ca_url() {
    local new_url=""
    local host=""
    local user=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --new-url)
                new_url="$2"
                shift 2
                ;;
            --host)
                host="$2"
                shift 2
                ;;
            --user)
                user="$2"
                shift 2
                ;;
            -h|--help)
                cmd_remote_update_ca_url_help
                return 0
                ;;
            *)
                die_with_help "Unknown option: $1" "remote update-ca-url"
                ;;
        esac
    done
    
    [[ -z "$new_url" ]] && die "New URL required. Use --new-url URL"
    
    log_header "Updating CA URL on Servers"
    log_info "New CA URL: ${new_url}"
    
    # Get new fingerprint
    local new_fp
    log_step "Fetching new CA fingerprint..."
    local tmp_cert
    tmp_cert=$(mktemp)
    cleanup_add "rm -f '$tmp_cert'"
    
    if curl -sk "${new_url}/roots.pem" -o "$tmp_cert"; then
        new_fp=$(step certificate fingerprint "$tmp_cert" 2>/dev/null || \
                 openssl x509 -in "$tmp_cert" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':')
        log_success "New fingerprint: ${new_fp}"
    else
        die "Cannot fetch root CA from ${new_url}"
    fi
    
    if [[ -n "$host" ]]; then
        [[ -z "$user" ]] && die "User required when specifying host"
        _update_server_ca_url "$host" "$user" "$new_url" "$new_fp"
    else
        # Update all enrolled servers
        if [[ ! -f "$INVENTORY_FILE" ]]; then
            die "No servers enrolled"
        fi
        
        log_warning "This will update CA URL on ALL enrolled servers"
        if ! ui_confirm "Continue?"; then
            log_info "Cancelled"
            return 1
        fi
        
        # Parse inventory
        while IFS= read -r line; do
            if [[ "$line" =~ host:\ *(.+) ]]; then
                local h="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ user:\ *(.+) ]]; then
                local u="${BASH_REMATCH[1]}"
                if [[ -n "$h" ]] && [[ -n "$u" ]]; then
                    echo ""
                    _update_server_ca_url "$h" "$u" "$new_url" "$new_fp" || true
                fi
            fi
        done < "$INVENTORY_FILE"
    fi
    
    echo ""
    log_success "CA URL update complete"
}

_update_server_ca_url() {
    local host="$1"
    local user="$2"
    local new_url="$3"
    local new_fp="$4"
    
    log_step "Updating ${host}..."
    
    local ssh_opts=(-o "ConnectTimeout=10" -o "StrictHostKeyChecking=accept-new")
    local ssh_target="${user}@${host}"
    
    if ! ssh "${ssh_opts[@]}" "$ssh_target" "true" &>/dev/null; then
        log_error "Cannot connect to ${host}"
        return 1
    fi
    
    # Re-bootstrap with new CA
    local cmd="step ca bootstrap --ca-url '${new_url}' --fingerprint '${new_fp}' --force"
    
    if ssh "${ssh_opts[@]}" "$ssh_target" "$cmd" &>/dev/null; then
        log_success "Updated ${host}"
    else
        log_error "Failed to update ${host}"
        return 1
    fi
}

#--------------------------------------------------
# Remote List
#--------------------------------------------------

cmd_remote_list() {
    log_header "Enrolled Servers"
    
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        echo "No servers enrolled"
        echo ""
        echo "Enroll a server with:"
        echo "  auto-ssl remote enroll --host IP --user USER"
        return
    fi
    
    _inventory_list
}

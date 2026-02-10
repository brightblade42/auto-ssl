#!/usr/bin/env bash
set -euo pipefail

BINARY="${BINARY:-./bin/auto-ssl}"
CA_NAME="${CA_NAME:-Validation CA}"
CA_ADDRESS="${CA_ADDRESS:-}"
REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_USER="${REMOTE_USER:-}"
WORK_DIR="${WORK_DIR:-/tmp/auto-ssl-validation}"

log() {
    printf "\n[validate] %s\n" "$1"
}

die() {
    printf "\n[validate] ERROR: %s\n" "$1" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

run() {
    printf "[cmd] %s\n" "$*"
    "$@"
}

run_tools() {
    if [[ "$(basename "$BINARY")" == "auto-ssl" ]]; then
        run "$BINARY" tools "$@"
    else
        run "$BINARY" "$@"
    fi
}

main() {
    [[ "$(uname -s)" == "Linux" ]] || die "This validation script is Linux-only"

    need_cmd sudo
    need_cmd mktemp
    need_cmd grep

    [[ -x "$BINARY" ]] || die "Binary not executable: $BINARY"

    mkdir -p "$WORK_DIR"

    if [[ -z "$CA_ADDRESS" ]]; then
        local_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
        [[ -n "$local_ip" ]] || local_ip="127.0.0.1"
        CA_ADDRESS="${local_ip}:9000"
    fi

    CA_URL="https://${CA_ADDRESS}"
    CA_PW_FILE="$(mktemp)"
    BACKUP_PW_FILE="$(mktemp)"
    BACKUP_OUT="${WORK_DIR}/ca-backup-$(date +%Y%m%d-%H%M%S).enc"
    DUMP_DIR="${WORK_DIR}/dump-bash"

    trap 'rm -f "$CA_PW_FILE" "$BACKUP_PW_FILE"' EXIT

    printf 'validation-ca-password' > "$CA_PW_FILE"
    chmod 600 "$CA_PW_FILE"
    printf 'validation-backup-passphrase' > "$BACKUP_PW_FILE"
    chmod 600 "$BACKUP_PW_FILE"

    log "Companion CLI smoke"
    run "$BINARY" --version
    run_tools doctor
    run_tools doctor --json
    run "$BINARY" exec -- version

    log "Dependency bootstrap"
    run_tools install-deps --yes

    log "Dump embedded bash runtime"
    run_tools dump-bash --output "$DUMP_DIR" --force --checksum --print-path
    [[ -x "${DUMP_DIR}/auto-ssl" ]] || die "Dumped auto-ssl is not executable"
    [[ -f "${DUMP_DIR}/CHECKSUMS.txt" ]] || die "Checksum manifest missing"

    log "Initialize CA"
    run sudo "$BINARY" exec -- ca init --name "$CA_NAME" --address "$CA_ADDRESS" --password-file "$CA_PW_FILE" --non-interactive
    run "$BINARY" exec -- ca status
    run curl -sk "${CA_URL}/health"

    FP="$(sudo awk '/fingerprint:/ {print $2; exit}' /etc/auto-ssl/config.yaml)"
    [[ -n "$FP" ]] || die "Failed to read CA fingerprint from /etc/auto-ssl/config.yaml"

    log "Enroll local server"
    run sudo "$BINARY" exec -- server enroll --ca-url "$CA_URL" --fingerprint "$FP" --password-file "$CA_PW_FILE" --non-interactive
    run "$BINARY" exec -- server status

    log "Renew certificate"
    run sudo "$BINARY" exec -- server renew --force

    log "Client trust flow"
    run sudo "$BINARY" exec -- client trust --ca-url "$CA_URL" --fingerprint "$FP"
    run "$BINARY" exec -- client status

    log "Backup flow"
    run sudo "$BINARY" exec -- ca backup --output "$BACKUP_OUT" --passphrase-file "$BACKUP_PW_FILE"
    [[ -s "$BACKUP_OUT" ]] || die "Backup file was not created"

    if [[ -n "$REMOTE_HOST" && -n "$REMOTE_USER" ]]; then
        log "Remote enrollment flow"
        run "$BINARY" exec -- remote enroll --host "$REMOTE_HOST" --user "$REMOTE_USER"
        run "$BINARY" exec -- remote status --host "$REMOTE_HOST" --user "$REMOTE_USER"
    else
        log "Skipping remote enrollment (set REMOTE_HOST and REMOTE_USER to enable)"
    fi

    log "Validation completed successfully"
}

main "$@"

#compdef auto-ssl

_auto_ssl() {
    local -a commands ca_commands server_commands remote_commands client_commands

    commands=(
        'ca:Certificate Authority management'
        'server:Server certificate management'
        'remote:Remote server management'
        'client:Client trust management'
        'info:Show environment information'
        'version:Show version'
        'help:Show help'
    )

    ca_commands=(
        'init:Initialize this machine as the CA server'
        'status:Show CA health and configuration'
        'backup:Create encrypted backup of CA'
        'restore:Restore CA from backup'
        'backup-schedule:Configure automatic backups'
    )

    server_commands=(
        'enroll:Enroll this server'
        'status:Show certificate status'
        'renew:Force immediate renewal'
        'suspend:Disable automatic renewal'
        'resume:Re-enable automatic renewal'
        'revoke:Revoke certificate'
        'remove:Remove server enrollment'
    )

    remote_commands=(
        'enroll:Enroll a server via SSH'
        'status:Check remote server status'
        'update-ca-url:Update CA URL on enrolled servers'
        'list:List enrolled servers'
    )

    client_commands=(
        'trust:Install root CA into system trust store'
        'status:Verify root CA is trusted'
    )

    _arguments -C \
        '1: :->command' \
        '2: :->subcommand' \
        '*:: :->options'

    case $state in
        command)
            _describe 'command' commands
            ;;
        subcommand)
            case $words[2] in
                ca)
                    _describe 'ca command' ca_commands
                    ;;
                server)
                    _describe 'server command' server_commands
                    ;;
                remote)
                    _describe 'remote command' remote_commands
                    ;;
                client)
                    _describe 'client command' client_commands
                    ;;
            esac
            ;;
        options)
            case $words[2]:$words[3] in
                ca:init)
                    _arguments \
                        '--name[CA name]:name:' \
                        '--address[Listen address]:address:' \
                        '--cert-duration[Certificate duration]:duration:' \
                        '--max-duration[Maximum duration]:duration:' \
                        '--password-file[Password file]:file:_files' \
                        '--non-interactive[Non-interactive mode]' \
                        {-h,--help}'[Show help]'
                    ;;
                server:enroll)
                    _arguments \
                        '--ca-url[CA URL]:url:' \
                        '--fingerprint[CA fingerprint]:fingerprint:' \
                        '--san[Subject Alternative Name]:san:' \
                        '--duration[Certificate duration]:duration:' \
                        '--cert-path[Certificate path]:path:_files' \
                        '--key-path[Key path]:path:_files' \
                        '--provisioner[Provisioner name]:name:' \
                        '--password-file[Password file]:file:_files' \
                        '--no-renewal[Skip renewal setup]' \
                        '--non-interactive[Non-interactive mode]' \
                        {-h,--help}'[Show help]'
                    ;;
            esac
            ;;
    esac
}

_auto_ssl

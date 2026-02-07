# auto-ssl bash completion

_auto_ssl() {
    local cur prev words cword
    _init_completion || return

    local commands="ca server remote client info version help"
    local ca_commands="init status backup restore backup-schedule"
    local server_commands="enroll status renew suspend resume revoke remove"
    local remote_commands="enroll status update-ca-url list"
    local client_commands="trust status"

    case ${cword} in
        1)
            COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
            ;;
        2)
            case ${prev} in
                ca)
                    COMPREPLY=($(compgen -W "${ca_commands}" -- "${cur}"))
                    ;;
                server)
                    COMPREPLY=($(compgen -W "${server_commands}" -- "${cur}"))
                    ;;
                remote)
                    COMPREPLY=($(compgen -W "${remote_commands}" -- "${cur}"))
                    ;;
                client)
                    COMPREPLY=($(compgen -W "${client_commands}" -- "${cur}"))
                    ;;
            esac
            ;;
        *)
            # Complete options for specific commands
            case ${words[1]} in
                ca)
                    case ${words[2]} in
                        init)
                            COMPREPLY=($(compgen -W "--name --address --cert-duration --max-duration --password-file --non-interactive --help" -- "${cur}"))
                            ;;
                        backup)
                            COMPREPLY=($(compgen -W "--output --passphrase-file --dest-type --rsync-target --s3-bucket --s3-endpoint --s3-prefix --help" -- "${cur}"))
                            ;;
                        restore)
                            COMPREPLY=($(compgen -W "--input --passphrase-file --new-address --help" -- "${cur}"))
                            ;;
                        backup-schedule)
                            COMPREPLY=($(compgen -W "--enable --disable --schedule --output --retention --passphrase-file --help" -- "${cur}"))
                            ;;
                    esac
                    ;;
                server)
                    case ${words[2]} in
                        enroll)
                            COMPREPLY=($(compgen -W "--ca-url --fingerprint --san --duration --cert-path --key-path --provisioner --password-file --no-renewal --non-interactive --help" -- "${cur}"))
                            ;;
                        renew)
                            COMPREPLY=($(compgen -W "--force --exec --help" -- "${cur}"))
                            ;;
                        suspend)
                            COMPREPLY=($(compgen -W "--reason --help" -- "${cur}"))
                            ;;
                        revoke)
                            COMPREPLY=($(compgen -W "--reason --serial --help" -- "${cur}"))
                            ;;
                        remove)
                            COMPREPLY=($(compgen -W "--reason --keep-certs --help" -- "${cur}"))
                            ;;
                    esac
                    ;;
                remote)
                    case ${words[2]} in
                        enroll)
                            COMPREPLY=($(compgen -W "--host --user --name --port --san --identity --help" -- "${cur}"))
                            ;;
                        status)
                            COMPREPLY=($(compgen -W "--host --user --all --port --help" -- "${cur}"))
                            ;;
                        update-ca-url)
                            COMPREPLY=($(compgen -W "--new-url --host --user --help" -- "${cur}"))
                            ;;
                    esac
                    ;;
                client)
                    case ${words[2]} in
                        trust)
                            COMPREPLY=($(compgen -W "--ca-url --fingerprint --cert-file --help" -- "${cur}"))
                            ;;
                    esac
                    ;;
            esac
            ;;
    esac

    return 0
}

complete -F _auto_ssl auto-ssl

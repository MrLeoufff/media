#!/usr/bin/env bash

source "${MEDIASTACK_HOME}/lib/docker/services.sh"
source "${MEDIASTACK_HOME}/lib/docker/dashboard.sh"
source "${MEDIASTACK_HOME}/lib/system/doctor.sh"
source "${MEDIASTACK_HOME}/lib/security/audit.sh"
source "${MEDIASTACK_HOME}/lib/security/firewall.sh"
source "${MEDIASTACK_HOME}/lib/security/fail2ban.sh"
source "${MEDIASTACK_HOME}/lib/security/updates.sh"
source "${MEDIASTACK_HOME}/lib/security/ssh.sh"
source "${MEDIASTACK_HOME}/lib/security/security.sh"
source "${MEDIASTACK_HOME}/lib/backup/create.sh"
source "${MEDIASTACK_HOME}/lib/backup/restore.sh"
source "${MEDIASTACK_HOME}/lib/backup/backup.sh"
source "${MEDIASTACK_HOME}/lib/web/homepage.sh"
source "${MEDIASTACK_HOME}/lib/web/domain.sh"
source "${MEDIASTACK_HOME}/lib/services/manager.sh"
source "${MEDIASTACK_HOME}/lib/modules/commands.sh"

media_help() {
    cat <<EOF
MediaStack ${MEDIASTACK_VERSION}

Services Docker
  media start
  media stop
  media restart
  media status
  media logs [service]
  media update
  media dashboard

Gestion des services
  media service list
  media service status <service>
  media service start <service|all>
  media service stop <service|all>
  media service restart <service>
  media service logs <service>
  media service update <service|all>
  media service remove <service>

Gestion des modules
  media module list
  media module info <module>
  media module enable <module>
  media module disable <module>
  media module doctor <module>

Sécurité
  media security audit
  media security fix
  media security firewall
  media security fail2ban
  media security updates
  media security ssh-audit

Sauvegardes
  media backup create
  media backup list
  media backup verify [archive]
  media backup restore [archive]

Web
  media homepage install
  media homepage status
  media homepage update
  media homepage remove
  media domain configure <domaine>
  media domain status

Diagnostic
  media doctor
  media version
  media help
EOF
}

media_version() {
    media_header
    printf "MediaStack       %s\n" "${MEDIASTACK_VERSION}"
    printf "Système          %s\n" "$(. /etc/os-release && echo "${PRETTY_NAME}")"
    printf "Docker           %s\n" "$(docker --version)"
    printf "Compose          %s\n" "$(docker compose version)"
}

media_main() {
    check_mediastack_environment

    case "${1:-help}" in
        start) stack_start ;;
        stop) stack_stop ;;
        restart) stack_restart ;;
        status) stack_status ;;
        logs) stack_logs "${2:-}" ;;
        update) stack_update ;;
        dashboard) show_dashboard ;;
        service)
            case "${2:-help}" in
                list)
                    service_list
                    ;;
                status)
                    service_status "${3:-}"
                    ;;
                start)
                    if [[ "${3:-}" == "all" ]]; then
                        service_start_all
                    else
                        service_start "${3:-}"
                    fi
                    ;;
                stop)
                    if [[ "${3:-}" == "all" ]]; then
                        service_stop_all
                    else
                        service_stop "${3:-}"
                    fi
                    ;;
                restart)
                    service_restart "${3:-}"
                    ;;
                logs)
                    service_logs "${3:-}"
                    ;;
                update)
                    if [[ "${3:-}" == "all" ]]; then
                        service_update_all
                    else
                        service_update "${3:-}"
                    fi
                    ;;
                remove)
                    service_remove "${3:-}"
                    ;;
                help|-h|--help)
                    cat <<'SERVICE_HELP'
Utilisation :
  media service list
  media service status <service>
  media service start <service|all>
  media service stop <service|all>
  media service restart <service>
  media service logs <service>
  media service update <service|all>
  media service remove <service>
SERVICE_HELP
                    ;;
                *)
                    media_error "Commande service inconnue : ${2}"
                    return 1
                    ;;
            esac
            ;;
        module)
            module_command_main "${@:2}"
            ;;
        doctor) run_doctor ;;
        security) security_command "${2:-audit}" "${@:3}" ;;
        backup) backup_command "${2:-list}" "${@:3}" ;;
        homepage) homepage_command "${2:-status}" ;;
        domain) domain_command "${2:-status}" "${@:3}" ;;
        version|-v|--version) media_version ;;
        help|-h|--help) media_help ;;
        *)
            media_error "Commande inconnue : ${1}"
            media_help
            exit 1
            ;;
    esac
}

#!/usr/bin/env bash

stack_start() {
    require_root
    service_start_all
}

stack_stop() {
    require_root
    service_stop_all
}

stack_restart() {
    require_root

    service_stop_all || return 1
    service_start_all || return 1

    media_success "MediaStack redémarrée."
}

stack_status() {
    if ! declare -F show_status >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "${MEDIASTACK_HOME}/lib/system/status.sh"
    fi

    show_status "${1:-text}"
}

stack_logs() {
    local service_name=""
    local follow=false
    local since=""
    local arg
    local compose_file
    local docker_args=()

    for arg in "$@"; do
        case "${arg}" in
            --follow|-f)
                follow=true
                ;;
            --since=*)
                since="${arg#--since=}"
                ;;
            --since)
                media_die "Usage : media logs [module] --since <durée>"
                ;;
            -*)
                media_die "Option logs inconnue : ${arg}"
                ;;
            *)
                if [[ -z "${service_name}" ]]; then
                    service_name="${arg}"
                else
                    media_die "Argument inattendu : ${arg}"
                fi
                ;;
        esac
    done

    if [[ -z "${service_name}" ]]; then
        media_error "Le nom du service est requis."
        printf 'Exemple : media logs jellyfin --follow --since 30m\n'
        printf 'Services disponibles :\n'
        service_names | sed 's/^/  - /'
        return 1
    fi

    if ! declare -F service_compose_file >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "${MEDIASTACK_HOME}/lib/services/manager.sh"
    fi

    service_require "${service_name}" || return 1
    compose_file="$(service_compose_file "${service_name}")"

    docker_args=(logs --tail=100)
    [[ "${follow}" == true ]] && docker_args+=(-f)
    [[ -n "${since}" ]] && docker_args+=(--since "${since}")

    docker compose -f "${compose_file}" "${docker_args[@]}"
}

stack_update() {
    require_root
    service_update_all
}

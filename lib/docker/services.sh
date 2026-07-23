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
    media_header
    service_list
}

stack_logs() {
    local service_name="${1:-}"

    if [[ -n "${service_name}" ]]; then
        service_logs "${service_name}"
        return
    fi

    media_error "Le nom du service est requis."
    printf 'Exemple : media logs jellyfin\n'
    printf 'Services disponibles :\n'
    service_names | sed 's/^/  - /'
    return 1
}

stack_update() {
    require_root
    service_update_all
}

#!/usr/bin/env bash

require_root() {
    [[ "${EUID}" -eq 0 ]] || media_die "Cette commande doit être lancée avec sudo."
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || media_die "Commande manquante : $1"
}

check_mediastack_environment() {
    require_command docker
    require_command systemctl
    require_command awk
    require_command grep
    require_command sed
    require_command tar

    docker compose version >/dev/null 2>&1 ||
        media_die "Docker Compose est indisponible."

    local compose_found=false
    local module

    if compgen -G "${MEDIASTACK_COMPOSE_DIR}/*.yml" >/dev/null; then
        compose_found=true
    fi

    if [[ -d "${MEDIASTACK_ENABLED_DIR}" ]]; then
        for module in "${MEDIASTACK_ENABLED_DIR}"/*; do
            [[ -e "${module}" ]] || continue

            if [[ -f "${module}/compose.yml" ]]; then
                compose_found=true
                break
            fi
        done
    fi

    [[ "${compose_found}" == true ]] ||
        media_die "Aucun service Compose configuré ou module activé."
}

confirm_action() {
    local answer
    read -r -p "$1 [o/N] " answer
    [[ "${answer}" =~ ^([oO]|oui|OUI|[yY]|yes|YES)$ ]]
}

primary_ip() {
    hostname -I | awk '{print $1}'
}

backup_existing_file() {
    local path="$1"
    [[ -e "${path}" ]] || return 0
    cp -a "${path}" "${path}.mediastack.$(date '+%Y%m%d-%H%M%S').bak"
}

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
    local modules_available=false

    if [[ -d "${MEDIASTACK_MODULES_DIR}" ]]; then
        for module in "${MEDIASTACK_MODULES_DIR}"/*; do
            [[ -d "${module}" ]] || continue
            if [[ -f "${module}/module.yml" && -f "${module}/compose.yml" ]]; then
                modules_available=true
                break
            fi
        done
    fi

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

    # modules/ suffit pour media module install (zero-touch) même sans enabled/
    [[ "${compose_found}" == true || "${modules_available}" == true ]] ||
        media_die "Aucun module MediaStack trouvé dans ${MEDIASTACK_MODULES_DIR}."
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

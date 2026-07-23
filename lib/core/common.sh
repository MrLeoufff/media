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

    [[ -d "${MEDIASTACK_HOME}/compose" ]] ||
        media_die "Répertoire Compose introuvable : ${MEDIASTACK_HOME}/compose"

    compgen -G "${MEDIASTACK_HOME}/compose/*.yml" >/dev/null ||
        media_die "Aucun fichier Compose trouvé dans ${MEDIASTACK_HOME}/compose"
}

compose() {
    media_die "La fonction compose() historique n'est plus disponible. Utilisez le gestionnaire de services."
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

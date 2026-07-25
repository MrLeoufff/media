#!/usr/bin/env bash

module_doctor() {
    local container="jellyfin"

    if ! docker inspect "${container}" >/dev/null 2>&1; then
        doctor_error "Conteneur Jellyfin introuvable."
        return 1
    fi

    if ! docker inspect \
        --format '{{.State.Running}}' \
        "${container}" 2>/dev/null | grep -qx true; then
        doctor_error "Le conteneur Jellyfin n'est pas actif."
        return 1
    fi

    if docker exec caddy sh -c \
        'wget -q -O /dev/null -T 10 http://jellyfin:8096/System/Info/Public' \
        >/dev/null 2>&1; then
        doctor_ok "Caddy peut joindre l'API Jellyfin."
    else
        doctor_error "Caddy ne peut pas joindre l'API Jellyfin."
    fi

    if [[ -d /opt/media/jellyfin/config ]]; then
        doctor_ok "Configuration Jellyfin accessible."
    else
        doctor_error "Configuration Jellyfin absente : /opt/media/jellyfin/config"
    fi

    if [[ -d /opt/media/jellyfin/cache ]]; then
        doctor_ok "Cache Jellyfin accessible."
    else
        doctor_error "Cache Jellyfin absent : /opt/media/jellyfin/cache"
    fi

    if declare -F check_local_http >/dev/null 2>&1; then
        check_local_http \
            "Accès public Jellyfin" \
            "https://media.dwg-dev.fr"
    fi
}

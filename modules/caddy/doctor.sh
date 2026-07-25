#!/usr/bin/env bash

module_doctor() {
    local container="caddy"
    local caddyfile="${MEDIASTACK_HOME}/conf/Caddyfile"

    if ! docker inspect "${container}" >/dev/null 2>&1; then
        doctor_error "Conteneur Caddy introuvable."
        return 1
    fi

    if ! docker inspect \
        --format '{{.State.Running}}' \
        "${container}" 2>/dev/null | grep -qx true; then
        doctor_error "Le conteneur Caddy n'est pas actif."
        return 1
    fi

    if [[ -f "${caddyfile}" ]]; then
        doctor_ok "Caddyfile présent."
    else
        doctor_error "Caddyfile absent : ${caddyfile}"
        return 1
    fi

    if docker exec "${container}" \
        caddy validate \
        --config /etc/caddy/Caddyfile \
        --adapter caddyfile >/dev/null 2>&1; then
        doctor_ok "Configuration Caddy valide."
    else
        doctor_error "Configuration Caddy invalide."
    fi

    if declare -F check_local_http >/dev/null 2>&1; then
        check_local_http \
            "Caddy local pour media.dwg-dev.fr" \
            "http://127.0.0.1" \
            "media.dwg-dev.fr"
    fi

    if [[ -d /opt/media/caddy/data ]]; then
        doctor_ok "Données Caddy accessibles."
    else
        doctor_error "Données Caddy absentes : /opt/media/caddy/data"
    fi

    if [[ -d /opt/media/caddy/config ]]; then
        doctor_ok "Configuration persistante Caddy accessible."
    else
        doctor_error "Configuration persistante Caddy absente : /opt/media/caddy/config"
    fi
}

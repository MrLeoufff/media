#!/usr/bin/env bash

module_doctor() {
    local container="homepage"
    local container_ip

    if ! docker inspect "${container}" >/dev/null 2>&1; then
        doctor_error "Conteneur Homepage introuvable."
        return 1
    fi

    if ! docker inspect \
        --format '{{.State.Running}}' \
        "${container}" 2>/dev/null | grep -qx true; then
        doctor_error "Le conteneur Homepage n'est pas actif."
        return 1
    fi

    container_ip="$(
        docker inspect \
            --format '{{with index .NetworkSettings.Networks "mediastack_proxy"}}{{.IPAddress}}{{end}}' \
            "${container}"
    )"

    if [[ -z "${container_ip}" ]]; then
        doctor_error "Adresse IP Docker Homepage introuvable."
        return 1
    fi

    if curl \
        --silent \
        --fail \
        --connect-timeout 3 \
        --max-time 5 \
        "http://${container_ip}:3000/" \
        >/dev/null 2>&1; then
        doctor_ok "Homepage répond en HTTP."
    else
        doctor_error "Homepage ne répond pas."
    fi

    if [[ -d /opt/media/homepage ]]; then
        doctor_ok "Configuration Homepage accessible."
    else
        doctor_error "Configuration Homepage absente."
    fi
}

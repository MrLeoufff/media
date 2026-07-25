#!/usr/bin/env bash

module_doctor() {
    local container="portainer"
    local container_ip

    if ! docker inspect "${container}" >/dev/null 2>&1; then
        doctor_error "Conteneur Portainer introuvable."
        return 1
    fi

    if ! docker inspect \
        --format '{{.State.Running}}' \
        "${container}" 2>/dev/null | grep -qx true; then
        doctor_error "Le conteneur Portainer n'est pas actif."
        return 1
    fi

    container_ip="$(
        docker inspect \
            --format '{{with index .NetworkSettings.Networks "mediastack_proxy"}}{{.IPAddress}}{{end}}' \
            "${container}" 2>/dev/null
    )"

    if [[ -z "${container_ip}" ]]; then
        doctor_error "Adresse IP Docker de Portainer introuvable."
        return 1
    fi

    if curl \
        --silent \
        --show-error \
        --fail \
        --insecure \
        --connect-timeout 3 \
        --max-time 5 \
        "https://${container_ip}:9443/api/status" \
        >/dev/null 2>&1; then
        doctor_ok "Portainer répond sur son API HTTPS."
        return 0
    fi

    if curl \
        --silent \
        --show-error \
        --fail \
        --connect-timeout 3 \
        --max-time 5 \
        "http://${container_ip}:9000/api/status" \
        >/dev/null 2>&1; then
        doctor_ok "Portainer répond sur son API HTTP."
        return 0
    fi

    doctor_error "L'API Portainer ne répond pas."
    return 1
}

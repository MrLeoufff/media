#!/usr/bin/env bash

module_doctor() {
    local container="jellyfin"
    local domain=""
    local public_url
    local status

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

    if ! docker inspect caddy >/dev/null 2>&1; then
        doctor_error "Conteneur Caddy introuvable (requis pour joindre Jellyfin)."
        return 1
    fi

    if ! docker inspect \
        --format '{{.State.Running}}' \
        caddy 2>/dev/null | grep -qx true; then
        doctor_error "Conteneur Caddy arrêté (requis pour joindre Jellyfin)."
        return 1
    fi

    if ! docker exec caddy true >/dev/null 2>&1; then
        doctor_error "Impossible d'exécuter une commande dans Caddy (docker exec)."
        return 1
    fi

    if ! docker exec caddy sh -c 'command -v wget >/dev/null' >/dev/null 2>&1; then
        doctor_warning "wget absent dans l'image Caddy — test réseau Jellyfin sauté."
    else
        if docker exec caddy sh -c \
            'wget -q -O /dev/null -T 10 http://jellyfin:8096/System/Info/Public' \
            >/dev/null 2>&1; then
            doctor_ok "Caddy joint l'API Jellyfin via le réseau Docker."
        else
            if docker network inspect mediastack_proxy >/dev/null 2>&1 &&
                docker inspect \
                    --format '{{json .NetworkSettings.Networks}}' \
                    jellyfin 2>/dev/null | grep -q mediastack_proxy &&
                docker inspect \
                    --format '{{json .NetworkSettings.Networks}}' \
                    caddy 2>/dev/null | grep -q mediastack_proxy; then
                doctor_error \
                    "Caddy et Jellyfin sont sur mediastack_proxy, mais l'API Jellyfin ne répond pas."
            else
                doctor_error \
                    "Caddy ne joint pas Jellyfin — vérifiez l'appartenance au réseau mediastack_proxy."
            fi
            return 1
        fi
    fi

    if [[ -d /opt/media/jellyfin/config ]]; then
        doctor_ok "Configuration Jellyfin accessible."
    else
        doctor_error "Configuration Jellyfin absente : /opt/media/jellyfin/config"
        return 1
    fi

    if [[ -d /opt/media/jellyfin/cache ]]; then
        doctor_ok "Cache Jellyfin accessible."
    else
        doctor_error "Cache Jellyfin absent : /opt/media/jellyfin/cache"
        return 1
    fi

    if declare -F domain_get >/dev/null 2>&1; then
        domain="$(domain_get || true)"
    fi

    # Contrôle public en warning : dépend du reverse-proxy amont / DNS.
    if [[ -n "${domain}" ]]; then
        public_url="https://${domain}"
        status="$(
            curl \
                --silent \
                --output /dev/null \
                --write-out '%{http_code}' \
                --max-time 10 \
                "${public_url}" 2>/dev/null || true
        )"

        if [[ "${status}" =~ ^(200|204|301|302|307|308)$ ]]; then
            doctor_ok "Accès public Jellyfin répond (${status}) via ${public_url}."
        else
            doctor_warning \
                "Accès public Jellyfin pas encore prêt (${public_url}, code=${status:-000}). Vérifiez DNS / reverse-proxy amont."
        fi
    fi

    return 0
}

#!/usr/bin/env bash

if ! declare -F proxy_regenerate >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/web/proxy.sh"
fi

configure_domain() {
    require_root
    local domain="${1:-}"

    [[ -n "${domain}" ]] ||
        media_die "Usage : media domain configure media.example.fr"

    proxy_regenerate "${domain}"
    media_success "Domaine configuré : ${domain}"
    media_info "Caddyfile régénéré automatiquement (aucune édition manuelle)."
}

domain_status() {
    local domain

    domain="$(domain_get)"

    if [[ -n "${domain}" ]]; then
        echo "Domaine mémorisé : ${domain}"
    else
        media_warning "Aucun domaine mémorisé (mode LAN / :80)."
    fi

    echo
    if [[ -f "${CADDYFILE}" ]]; then
        cat "${CADDYFILE}"
    else
        media_warning "Aucun Caddyfile MediaStack trouvé."
    fi
}

domain_command() {
    case "${1:-status}" in
        configure) configure_domain "${2:-}" ;;
        status) domain_status ;;
        *) media_die "Commande domain inconnue : $1" ;;
    esac
}

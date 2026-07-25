#!/usr/bin/env bash

if ! declare -F proxy_regenerate >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/web/proxy.sh"
fi

configure_domain() {
    require_root
    local domain=""
    local tls_mode=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tls)
                shift
                tls_mode="${1:-}"
                [[ -n "${tls_mode}" ]] ||
                    media_die "Usage : media domain configure <domaine> [--tls off|auto]"
                ;;
            --tls=*)
                tls_mode="${1#--tls=}"
                ;;
            -*)
                media_die "Option inconnue : $1"
                ;;
            *)
                if [[ -z "${domain}" ]]; then
                    domain="$1"
                else
                    media_die "Argument inattendu : $1"
                fi
                ;;
        esac
        shift
    done

    [[ -n "${domain}" ]] ||
        media_die "Usage : media domain configure media.example.fr [--tls off|auto]"

    if [[ -z "${tls_mode}" ]]; then
        tls_mode="$(tls_mode_prompt)"
    fi

    proxy_regenerate "${domain}" "${tls_mode}"
    media_success "Domaine configuré : ${domain} (tls=$(tls_mode_get))"
    if [[ "$(tls_mode_get)" == "off" ]]; then
        media_info "Mode HTTP backend : le TLS doit être terminé en amont (ex. m710q)."
    else
        media_info "Mode HTTPS auto : Caddy gère Let's Encrypt sur ce serveur."
    fi
}

domain_status() {
    local domain

    domain="$(domain_get)"

    if [[ -n "${domain}" ]]; then
        echo "Domaine mémorisé : ${domain}"
    else
        media_warning "Aucun domaine mémorisé (mode LAN / :80)."
    fi

    echo "Mode TLS        : $(tls_mode_get)"
    echo

    if [[ -f "${CADDYFILE}" ]]; then
        cat "${CADDYFILE}"
    else
        media_warning "Aucun Caddyfile MediaStack trouvé."
    fi
}

domain_command() {
    case "${1:-status}" in
        configure) shift; configure_domain "$@" ;;
        status) domain_status ;;
        *) media_die "Commande domain inconnue : $1" ;;
    esac
}

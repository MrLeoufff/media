#!/usr/bin/env bash

configure_domain() {
    require_root
    local domain="${1:-}"

    [[ -n "${domain}" ]] ||
        media_die "Usage : media domain configure media.dwg-dev.fr"

    mkdir -p "${CONFIG_DIR}"
    backup_existing_file "${CADDYFILE}"

    cat > "${CADDYFILE}" <<EOF
${domain} {
    encode zstd gzip

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        Referrer-Policy "strict-origin-when-cross-origin"
    }

    reverse_proxy jellyfin:8096
}
EOF

    media_success "Caddyfile créé : ${CADDYFILE}"
    media_warning "Vérifie que le conteneur Caddy monte ce fichier."
    media_warning "Vérifie aussi le DNS et les redirections 80/443 de la box."
}

domain_status() {
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

#!/usr/bin/env bash

homepage_install() {
    require_root
    mkdir -p "${HOMEPAGE_DIR}"

    cat > "${HOMEPAGE_COMPOSE_FILE}" <<'EOF'
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - /opt/media/homepage:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
EOF

    compose up -d homepage
    media_success "Homepage installé."
}

homepage_status() {
    compose ps homepage
}

homepage_update() {
    require_root
    compose pull homepage
    compose up -d homepage
    media_success "Homepage mis à jour."
}

homepage_remove() {
    require_root
    compose stop homepage || true
    compose rm -f homepage || true
    rm -f "${HOMEPAGE_COMPOSE_FILE}"
    media_success "Homepage supprimé."
}

homepage_command() {
    case "${1:-status}" in
        install) homepage_install ;;
        status) homepage_status ;;
        update) homepage_update ;;
        remove) homepage_remove ;;
        *) media_die "Commande homepage inconnue : $1" ;;
    esac
}

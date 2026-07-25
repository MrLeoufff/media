#!/usr/bin/env bash

homepage_install() {
    require_root

    mkdir -p "${HOMEPAGE_DIR}"
    service_start homepage

    media_success "Homepage installé et démarré."
}

homepage_status() {
    service_status homepage
}

homepage_update() {
    require_root

    service_update homepage

    media_success "Homepage mis à jour."
}

homepage_remove() {
    require_root

    service_remove homepage

    media_success "Homepage arrêté et supprimé."
    media_warning "La configuration ${HOMEPAGE_DIR} a été conservée."
}

homepage_command() {
    case "${1:-status}" in
        install)
            homepage_install
            ;;
        status)
            homepage_status
            ;;
        update)
            homepage_update
            ;;
        remove)
            homepage_remove
            ;;
        *)
            media_die "Commande homepage inconnue : ${1:-}"
            ;;
    esac
}

#!/usr/bin/env bash

resolve_backup_archive() {
    local requested="${1:-}"

    if [[ -n "${requested}" ]]; then
        [[ -f "${requested}" ]] && readlink -f "${requested}" && return
        [[ -f "${BACKUP_DIR}/${requested}" ]] &&
            readlink -f "${BACKUP_DIR}/${requested}" &&
            return
        media_die "Archive introuvable : ${requested}"
    fi

    find "${BACKUP_DIR}" \
        -maxdepth 1 \
        -type f \
        -name 'mediastack_*.tar.gz' \
        -printf '%T@ %p\n' 2>/dev/null |
        sort -nr |
        head -1 |
        cut -d' ' -f2-
}

verify_backup() {
    local archive
    archive="$(resolve_backup_archive "${1:-}")"

    [[ -n "${archive}" ]] || media_die "Aucune archive disponible."

    tar -tzf "${archive}" >/dev/null

    local unsafe_path
    unsafe_path="$(
        tar -tzf "${archive}" |
        awk '/^\// || /(^|\/)\.\.(\/|$)/ {print; exit}'
    )"

    [[ -z "${unsafe_path}" ]] ||
        media_die "Chemin dangereux détecté : ${unsafe_path}"

    media_success "Archive valide : ${archive}"
}

restore_backup() {
    require_root

    local archive
    archive="$(resolve_backup_archive "${1:-}")"

    [[ -n "${archive}" ]] || media_die "Aucune archive disponible."

    verify_backup "${archive}"

    media_warning "La configuration actuelle sera remplacée."
    confirm_action "Continuer ?" || media_die "Restauration annulée."

    service_stop_all
    tar -xzf "${archive}" -C /
    service_start_all
    systemctl restart smbd || true

    media_success "Restauration terminée."
}

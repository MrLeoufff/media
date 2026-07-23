#!/usr/bin/env bash

create_backup() {
    require_root
    mkdir -p "${BACKUP_DIR}"

    local archive
    archive="${BACKUP_DIR}/mediastack_$(date '+%Y-%m-%d_%H-%M-%S').tar.gz"

    tar \
        --exclude="${BACKUP_DIR}" \
        --exclude="${RESTORE_DIR}" \
        --exclude="${MEDIA_DIR}" \
        --exclude="${JELLYFIN_DIR}/cache" \
        -czf "${archive}" \
        "${STACK_DIR}" \
        "${JELLYFIN_DIR}/config" \
        "${PORTAINER_DIR}" \
        "${CADDY_DIR}" \
        "${HOMEPAGE_DIR}" \
        /etc/samba/smb.conf

    media_success "Sauvegarde créée : ${archive}"
}

list_backups() {
    media_header
    find "${BACKUP_DIR}" \
        -maxdepth 1 \
        -type f \
        -name 'mediastack_*.tar.gz' \
        -printf '%TY-%Tm-%Td %TH:%TM  %10s  %f\n' 2>/dev/null |
        sort -r || true
}

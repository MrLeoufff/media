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
        \( -name 'mediastack-backup-*.tar.gz' -o -name 'mediastack_*.tar.gz' \) \
        -printf '%T@ %p\n' 2>/dev/null |
        sort -nr |
        head -1 |
        cut -d' ' -f2-
}

verify_backup() {
    local archive
    local checksum_file
    local expected
    local actual

    archive="$(resolve_backup_archive "${1:-}")"
    [[ -n "${archive}" ]] || media_die "Aucune archive disponible."

    checksum_file="${archive}.sha256"
    if [[ -f "${checksum_file}" ]]; then
        expected="$(awk '{print $1}' "${checksum_file}")"
        actual="$(sha256sum "${archive}" | awk '{print $1}')"
        [[ "${expected}" == "${actual}" ]] ||
            media_die "Checksum SHA-256 invalide pour ${archive}"
        media_success "Checksum SHA-256 valide."
    else
        media_warning "Fichier checksum absent : ${checksum_file}"
    fi

    tar -tzf "${archive}" >/dev/null

    local unsafe_path
    unsafe_path="$(
        tar -tzf "${archive}" |
            awk '/^\// || /(^|\/)\.\.(\/|$)/ {print; exit}'
    )"

    [[ -z "${unsafe_path}" ]] ||
        media_die "Chemin dangereux détecté : ${unsafe_path}"

    if tar -tzf "${archive}" | grep -qx './manifest.json\|manifest.json'; then
        media_success "Manifeste présent."
    else
        media_warning "Manifeste absent (archive legacy)."
    fi

    media_success "Archive valide : ${archive}"
}

restore_backup() {
    require_root
    require_command tar

    if ! declare -F service_stop_all >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "${MEDIASTACK_HOME}/lib/services/manager.sh"
    fi

    if ! declare -F module_enable >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "${MEDIASTACK_HOME}/lib/modules/manager.sh"
    fi

    if ! declare -F proxy_regenerate >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "${MEDIASTACK_HOME}/lib/web/proxy.sh"
    fi

    local archive
    local stage_dir
    local module_name

    archive="$(resolve_backup_archive "${1:-}")"
    [[ -n "${archive}" ]] || media_die "Aucune archive disponible."

    verify_backup "${archive}"

    media_warning "La configuration et les données applicatives seront remplacées."
    confirm_action "Continuer la restauration ?" || media_die "Restauration annulée."

    stage_dir="$(mktemp -d /tmp/mediastack-restore.XXXXXX)"
    tar -xzf "${archive}" -C "${stage_dir}"

    media_info "Arrêt des services..."
    service_stop_all || true

    mkdir -p \
        "${MEDIASTACK_CONFIG_DIR}" \
        "${MEDIASTACK_ENABLED_DIR}" \
        "${JELLYFIN_DIR}/config" \
        "${PORTAINER_DIR}/data" \
        "${CADDY_DIR}" \
        "${HOMEPAGE_DIR}"

    if [[ -d "${stage_dir}/conf" ]]; then
        cp -a "${stage_dir}/conf/." "${MEDIASTACK_CONFIG_DIR}/"
    fi

    if [[ -d "${stage_dir}/data/jellyfin/config" ]]; then
        cp -a "${stage_dir}/data/jellyfin/config/." "${JELLYFIN_DIR}/config/"
    fi

    if [[ -d "${stage_dir}/data/portainer/data" ]]; then
        cp -a "${stage_dir}/data/portainer/data/." "${PORTAINER_DIR}/data/"
    fi

    if [[ -d "${stage_dir}/data/caddy" ]]; then
        cp -a "${stage_dir}/data/caddy/." "${CADDY_DIR}/"
    fi

    if [[ -d "${stage_dir}/data/homepage" ]]; then
        cp -a "${stage_dir}/data/homepage/." "${HOMEPAGE_DIR}/"
    fi

    # Réactiver les modules listés dans l'archive
    if [[ -f "${stage_dir}/enabled/modules.txt" ]]; then
        find "${MEDIASTACK_ENABLED_DIR}" -mindepth 1 ! -name '.gitkeep' -exec rm -rf {} +
        while IFS= read -r module_name; do
            [[ -n "${module_name}" ]] || continue
            if module_exists "${module_name}"; then
                module_enable "${module_name}" || true
            else
                media_warning "Module absent du dépôt, non réactivé : ${module_name}"
            fi
        done < "${stage_dir}/enabled/modules.txt"
    fi

    rm -rf "${stage_dir}"

    proxy_regenerate "$(domain_get)" || true

    media_info "Redémarrage des services..."
    service_start_all || true

    media_success "Restauration terminée depuis : ${archive}"
    media_info "Exécutez : media doctor"
}

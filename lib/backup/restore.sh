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

backup_has_manifest() {
    local archive="$1"

    tar -tzf "${archive}" ./manifest.json >/dev/null 2>&1 ||
        tar -tzf "${archive}" manifest.json >/dev/null 2>&1
}

# Restauration fidèle : remplace le contenu et supprime les fichiers obsolètes.
backup_sync_dir() {
    local source_dir="$1"
    local dest_dir="$2"
    local dry_run="${3:-false}"
    local -a rsync_args

    [[ -d "${source_dir}" ]] || return 0

    mkdir -p "${dest_dir}"

    rsync_args=(-a --delete)
    if [[ "${dry_run}" == true ]]; then
        rsync_args+=(--dry-run --itemize-changes)
        media_info "dry-run rsync : ${source_dir}/ -> ${dest_dir}/"
    fi

    rsync "${rsync_args[@]}" "${source_dir}/" "${dest_dir}/"
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

    if backup_has_manifest "${archive}"; then
        media_success "Manifeste présent."
    else
        media_warning "Manifeste absent (archive legacy)."
    fi

    media_success "Archive valide : ${archive}"
}

restore_backup() {
    require_root
    require_command tar
    require_command rsync

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

    local archive=""
    local dry_run=false
    local stage_dir=""
    local module_name
    local arg

    for arg in "$@"; do
        case "${arg}" in
            --dry-run)
                dry_run=true
                ;;
            -*)
                media_die "Option restore inconnue : ${arg}"
                ;;
            *)
                if [[ -z "${archive}" ]]; then
                    archive="${arg}"
                else
                    media_die "Argument inattendu : ${arg}"
                fi
                ;;
        esac
    done

    # Si archive vide, resolve_backup_archive prendra la plus récente
    archive="$(resolve_backup_archive "${archive}")"
    [[ -n "${archive}" ]] || media_die "Aucune archive disponible."

    verify_backup "${archive}"

    if [[ "${dry_run}" == true ]]; then
        media_info "Mode dry-run : aucune modification ne sera appliquée."
    else
        media_warning "La configuration et les données applicatives seront remplacées (rsync --delete)."
        confirm_action "Continuer la restauration ?" || media_die "Restauration annulée."
    fi

    stage_dir="$(mktemp -d /tmp/mediastack-restore.XXXXXX)"
    # Expansion immédiate : évite unbound variable au RETURN sous set -u.
    # shellcheck disable=SC2064
    trap "rm -rf '${stage_dir}'" RETURN

    tar -xzf "${archive}" -C "${stage_dir}"

    if [[ "${dry_run}" != true ]]; then
        media_info "Arrêt des services..."
        service_stop_all ||
            media_die "Impossible d'arrêter tous les services."
    else
        media_info "dry-run : arrêt des services ignoré."
    fi

    mkdir -p \
        "${MEDIASTACK_CONFIG_DIR}" \
        "${MEDIASTACK_ENABLED_DIR}" \
        "${JELLYFIN_DIR}/config" \
        "${PORTAINER_DIR}/data" \
        "${CADDY_DIR}" \
        "${HOMEPAGE_DIR}"

    backup_sync_dir "${stage_dir}/conf" "${MEDIASTACK_CONFIG_DIR}" "${dry_run}"
    backup_sync_dir "${stage_dir}/data/jellyfin/config" "${JELLYFIN_DIR}/config" "${dry_run}"
    backup_sync_dir "${stage_dir}/data/portainer/data" "${PORTAINER_DIR}/data" "${dry_run}"
    backup_sync_dir "${stage_dir}/data/caddy" "${CADDY_DIR}" "${dry_run}"
    backup_sync_dir "${stage_dir}/data/homepage" "${HOMEPAGE_DIR}" "${dry_run}"

    if [[ -f "${stage_dir}/enabled/modules.txt" ]]; then
        if [[ "${dry_run}" == true ]]; then
            media_info "dry-run : modules à réactiver :"
            sed 's/^/  - /' "${stage_dir}/enabled/modules.txt"
        else
            find "${MEDIASTACK_ENABLED_DIR}" -mindepth 1 ! -name '.gitkeep' -exec rm -rf {} +
            while IFS= read -r module_name; do
                [[ -n "${module_name}" ]] || continue
                if module_exists "${module_name}"; then
                    module_enable "${module_name}" ||
                        media_die "Impossible d'activer le module : ${module_name}"
                else
                    media_warning "Module absent du dépôt, non réactivé : ${module_name}"
                fi
            done < "${stage_dir}/enabled/modules.txt"
        fi
    fi

    if [[ "${dry_run}" == true ]]; then
        media_success "Dry-run terminé pour : ${archive}"
        media_info "Aucune modification n'a été appliquée."
        return 0
    fi

    proxy_regenerate "$(domain_get)" ||
        media_die "Échec de régénération du proxy."

    media_info "Redémarrage des services..."
    service_start_all ||
        media_die "Certains services n'ont pas redémarré."

    media_success "Restauration terminée depuis : ${archive}"
    media_info "Exécutez : media doctor"
}

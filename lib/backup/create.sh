#!/usr/bin/env bash

backup_timestamp() {
    date '+%Y-%m-%d_%H%M%S'
}

backup_archive_basename() {
    printf 'mediastack-backup-%s\n' "$(backup_timestamp)"
}

backup_write_manifest() {
    local stage_dir="$1"
    local created_at
    local commit
    local domain
    local tls_mode
    local modules_json

    created_at="$(date -Iseconds)"
    commit="$(
        git -C "${MEDIASTACK_HOME}" rev-parse --short HEAD 2>/dev/null || echo unknown
    )"
    domain="$(domain_get 2>/dev/null || true)"
    tls_mode="$(tls_mode_get 2>/dev/null || echo off)"
    modules_json="$(
        module_enabled_names |
            python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'
    )"

    cat > "${stage_dir}/manifest.json" <<EOF
{
  "apiVersion": "mediastack/backup/v1",
  "mediaStackVersion": "${MEDIASTACK_VERSION}",
  "gitCommit": "${commit}",
  "createdAt": "${created_at}",
  "hostname": "$(hostname)",
  "domain": "${domain}",
  "tlsMode": "${tls_mode}",
  "enabledModules": ${modules_json},
  "includes": [
    "conf/",
    "enabled/",
    "data/jellyfin/config/",
    "data/portainer/data/",
    "data/caddy/",
    "data/homepage/"
  ],
  "excludes": [
    "data/jellyfin/cache/",
    "media libraries under /opt/media"
  ]
}
EOF

    module_enabled_names > "${stage_dir}/enabled/modules.txt"
}

backup_stage_tree() {
    local stage_dir="$1"

    mkdir -p \
        "${stage_dir}/conf" \
        "${stage_dir}/enabled" \
        "${stage_dir}/data/jellyfin/config" \
        "${stage_dir}/data/portainer/data" \
        "${stage_dir}/data/caddy" \
        "${stage_dir}/data/homepage"

    if [[ -d "${MEDIASTACK_CONFIG_DIR}" ]]; then
        cp -a "${MEDIASTACK_CONFIG_DIR}/." "${stage_dir}/conf/" 2>/dev/null || true
    fi

    if [[ -d "${JELLYFIN_DIR}/config" ]]; then
        cp -a "${JELLYFIN_DIR}/config/." \
            "${stage_dir}/data/jellyfin/config/" 2>/dev/null || true
    fi

    if [[ -d "${PORTAINER_DIR}/data" ]]; then
        cp -a "${PORTAINER_DIR}/data/." \
            "${stage_dir}/data/portainer/data/" 2>/dev/null || true
    elif [[ -d "${PORTAINER_DIR}" ]]; then
        cp -a "${PORTAINER_DIR}/." \
            "${stage_dir}/data/portainer/data/" 2>/dev/null || true
    fi

    if [[ -d "${CADDY_DIR}" ]]; then
        cp -a "${CADDY_DIR}/." "${stage_dir}/data/caddy/" 2>/dev/null || true
    fi

    if [[ -d "${HOMEPAGE_DIR}" ]]; then
        cp -a "${HOMEPAGE_DIR}/." "${stage_dir}/data/homepage/" 2>/dev/null || true
    fi

    backup_write_manifest "${stage_dir}"
}

create_backup() {
    require_root
    require_command tar
    require_command sha256sum
    require_command python3

    if ! declare -F module_enabled_names >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "${MEDIASTACK_HOME}/lib/modules/manager.sh"
    fi

    if ! declare -F domain_get >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "${MEDIASTACK_HOME}/lib/web/proxy.sh"
    fi

    mkdir -p "${BACKUP_DIR}"

    local basename archive checksum stage_dir
    basename="$(backup_archive_basename)"
    archive="${BACKUP_DIR}/${basename}.tar.gz"
    checksum="${archive}.sha256"
    stage_dir="$(mktemp -d "${BACKUP_DIR}/.stage.XXXXXX")"
    # Expansion immédiate : évite unbound variable au RETURN sous set -u.
    # shellcheck disable=SC2064
    trap "rm -rf '${stage_dir}'" RETURN

    media_info "Préparation de la sauvegarde..."
    backup_stage_tree "${stage_dir}"

    tar -czf "${archive}" -C "${stage_dir}" .
    (
        cd "${BACKUP_DIR}" || exit 1
        sha256sum "$(basename "${archive}")" > "$(basename "${checksum}")"
    )

    media_success "Sauvegarde créée : ${archive}"
    media_success "Checksum         : ${checksum}"
}

list_backups() {
    media_header
    printf '%-36s %12s  %s\n' "ARCHIVE" "TAILLE" "CHECKSUM"
    printf '%-36s %12s  %s\n' "------------------------------------" "------------" "--------"

    local archive size sum_state
    while IFS= read -r archive; do
        [[ -n "${archive}" ]] || continue
        size="$(du -h "${archive}" | awk '{print $1}')"
        if [[ -f "${archive}.sha256" ]]; then
            sum_state="sha256"
        else
            sum_state="missing"
        fi
        printf '%-36s %12s  %s\n' \
            "$(basename "${archive}")" \
            "${size}" \
            "${sum_state}"
    done < <(
        find "${BACKUP_DIR}" \
            -maxdepth 1 \
            -type f \
            \( -name 'mediastack-backup-*.tar.gz' -o -name 'mediastack_*.tar.gz' \) \
            -printf '%T@ %p\n' 2>/dev/null |
            sort -nr |
            awk '{print $2}'
    )
}

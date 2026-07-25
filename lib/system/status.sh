#!/usr/bin/env bash

if ! declare -F module_enabled_names >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/manager.sh"
fi

if ! declare -F module_metadata_get_or_default >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/metadata.sh"
fi

if ! declare -F domain_get >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/web/proxy.sh"
fi

if ! declare -F service_container_status >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/services/manager.sh"
fi

status_health() {
    local container="$1"
    local running
    local health

    if ! docker inspect "${container}" >/dev/null 2>&1; then
        printf 'absent\n'
        return
    fi

    running="$(
        docker inspect --format '{{.State.Running}}' "${container}" 2>/dev/null || echo false
    )"

    if [[ "${running}" != "true" ]]; then
        docker inspect --format '{{.State.Status}}' "${container}" 2>/dev/null || echo stopped
        return
    fi

    health="$(
        docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
            "${container}" 2>/dev/null || echo none
    )"

    case "${health}" in
        healthy) printf 'OK\n' ;;
        unhealthy) printf 'unhealthy\n' ;;
        starting) printf 'starting\n' ;;
        none) printf 'running\n' ;;
        *) printf '%s\n' "${health}" ;;
    esac
}

status_module_url() {
    local module_name="$1"
    local domain
    local tls_mode
    local proxy_enabled

    domain="$(domain_get)"
    tls_mode="$(tls_mode_get)"
    proxy_enabled="$(
        module_metadata_get_or_default "${module_name}" proxy.enabled false
    )"

    if [[ "${proxy_enabled}" != "true" || -z "${domain}" ]]; then
        printf '%s\n' '-'
        return
    fi

    if [[ "${tls_mode}" == "auto" ]]; then
        printf 'https://%s\n' "${domain}"
    else
        # TLS souvent terminé en amont (ex. m710q)
        printf 'https://%s\n' "${domain}"
    fi
}

status_backup_summary() {
    local latest

    latest="$(
        find "${BACKUP_DIR}" \
            -maxdepth 1 \
            -type f \
            \( -name 'mediastack-backup-*.tar.gz' -o -name 'mediastack_*.tar.gz' \) \
            -printf '%T@ %f\n' 2>/dev/null |
            sort -nr |
            head -1 |
            cut -d' ' -f2-
    )"

    if [[ -z "${latest}" ]]; then
        printf 'aucune\n'
    else
        printf '%s\n' "${latest}"
    fi
}

status_disk_usage() {
    df -P "${MEDIASTACK_DATA}" 2>/dev/null |
        awk 'NR==2 {gsub("%","",$5); print $5}'
}

show_status() {
    local format="${1:-text}"
    local module_name
    local state
    local health
    local url
    local disk
    local docker_ok="OK"
    local backup_summary

    if ! docker info >/dev/null 2>&1; then
        docker_ok="KO"
    fi

    disk="$(status_disk_usage)"
    backup_summary="$(status_backup_summary)"

    if [[ "${format}" == "--json" || "${format}" == "json" ]]; then
        python3 - "${MEDIASTACK_VERSION}" "${docker_ok}" "${disk:-}" "${backup_summary}" <<'PY'
import json, os, subprocess, sys

version, docker_ok, disk, backup = sys.argv[1:5]
home = os.environ.get("MEDIASTACK_HOME", "/opt/mediastack")

def enabled_modules():
    enabled = os.path.join(home, "enabled")
    names = []
    if os.path.isdir(enabled):
        for name in sorted(os.listdir(enabled)):
            if name.startswith("."):
                continue
            path = os.path.join(enabled, name)
            if os.path.islink(path) or os.path.isdir(path):
                names.append(name)
    return names

modules = []
for name in enabled_modules():
    try:
        running = subprocess.check_output(
            ["docker", "inspect", "--format", "{{.State.Running}}", name],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        running = "false"
    try:
        health = subprocess.check_output(
            ["docker", "inspect", "--format",
             "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}", name],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        health = "absent"
    modules.append({
        "name": name,
        "running": running == "true",
        "health": health,
    })

print(json.dumps({
    "version": version,
    "docker": docker_ok,
    "diskPercent": disk,
    "backup": backup,
    "modules": modules,
}, indent=2))
PY
        return
    fi

    media_header
    printf "MediaStack %s\n\n" "${MEDIASTACK_VERSION}"
    printf '%-12s %-10s %-12s %s\n' "MODULE" "ÉTAT" "SANTÉ" "URL"
    printf '%-12s %-10s %-12s %s\n' "------------" "----------" "------------" "----"

    while IFS= read -r module_name; do
        [[ -n "${module_name}" ]] || continue
        if docker inspect "${module_name}" >/dev/null 2>&1 &&
            docker inspect --format '{{.State.Running}}' "${module_name}" 2>/dev/null | grep -qx true; then
            state="actif"
        else
            state="inactif"
        fi
        health="$(status_health "${module_name}")"
        url="$(status_module_url "${module_name}")"
        printf '%-12s %-10s %-12s %s\n' \
            "${module_name}" \
            "${state}" \
            "${health}" \
            "${url}"
    done < <(module_enabled_names)

    echo
    printf "Disque       %s %%\n" "${disk:-?}"
    printf "Docker       %s\n" "${docker_ok}"
    printf "Sauvegarde   %s\n" "${backup_summary}"
}

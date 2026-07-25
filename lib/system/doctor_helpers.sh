#!/usr/bin/env bash

doctor_section() {
    echo
    echo "[$1]"
    printf '%*s\n' 60 '' | tr ' ' '-'
}

doctor_ok() {
    checks=$(( ${checks:-0} + 1 ))
    echo "[OK] $1"
}

doctor_warning() {
    checks=$(( ${checks:-0} + 1 ))
    warnings=$(( ${warnings:-0} + 1 ))
    echo "[WARN] $1"
}

doctor_error() {
    checks=$(( ${checks:-0} + 1 ))
    errors=$(( ${errors:-0} + 1 ))
    echo "[ERROR] $1"
}

doctor_title() {
    echo
    printf '%*s\n' 60 '' | tr ' ' '-'
    printf '%25s\n' "MediaStack Doctor"
    printf '%*s\n' 60 '' | tr ' ' '-'
}

check_command() {
    local command_name="$1"
    local label="$2"

    if command -v "$command_name" >/dev/null 2>&1; then
        doctor_ok "${label} installé."
    else
        doctor_error "${label} absent."
    fi
}

check_container() {
    local container="$1"

    if ! docker inspect "$container" >/dev/null 2>&1; then
        doctor_error "Conteneur ${container} introuvable."
        return
    fi

    local state

    state="$(
        docker inspect \
            --format '{{.State.Status}}' \
            "$container" 2>/dev/null
    )"

    if [[ "$state" == "running" ]]; then
        doctor_ok "Conteneur ${container} actif."
    else
        doctor_error "Conteneur ${container} dans l'état : ${state}."
    fi
}

check_container_health() {
    local container="$1"
    local health

    health="$(
        docker inspect \
            --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
            "$container" 2>/dev/null || true
    )"

    case "$health" in
        healthy)
            doctor_ok "Healthcheck ${container} valide."
            ;;
        unhealthy)
            doctor_error "Healthcheck ${container} en échec."
            ;;
        starting)
            doctor_warning "Healthcheck ${container} en cours."
            ;;
        none|"")
            doctor_warning "Aucun healthcheck défini pour ${container}."
            ;;
    esac
}

check_compose_file() {
    local compose_file="$1"
    local service_name

    service_name="$(basename "${compose_file}" .yml)"

    if [[ "${service_name}" == "compose" ]]; then
        service_name="$(basename "$(dirname "${compose_file}")")"
    fi

    if docker compose \
        -f "$compose_file" \
        config --quiet >/dev/null 2>&1; then
        doctor_ok "Compose ${service_name} valide."
    else
        doctor_error "Compose ${service_name} invalide : ${compose_file}"
    fi
}

check_network_membership() {
    local container="$1"
    local network="$2"

    if ! docker inspect "$container" >/dev/null 2>&1; then
        return
    fi

    if docker inspect \
        --format '{{json .NetworkSettings.Networks}}' \
        "$container" 2>/dev/null |
        grep -q "\"${network}\""; then
        doctor_ok "${container} connecté à ${network}."
    else
        doctor_error "${container} absent du réseau ${network}."
    fi
}

check_local_http() {
    local name="$1"
    local url="$2"
    local host_header="${3:-}"
    local status

    if [[ -n "$host_header" ]]; then
        status="$(
            curl \
                --silent \
                --output /dev/null \
                --write-out '%{http_code}' \
                --max-time 10 \
                --header "Host: ${host_header}" \
                "$url" 2>/dev/null || true
        )"
    else
        status="$(
            curl \
                --silent \
                --output /dev/null \
                --write-out '%{http_code}' \
                --max-time 10 \
                "$url" 2>/dev/null || true
        )"
    fi

    if [[ "$status" =~ ^(200|204|301|302|307|308)$ ]]; then
        doctor_ok "${name} répond en HTTP (${status})."
    elif [[ "$status" == "000" || -z "$status" ]]; then
        doctor_error "${name} ne répond pas."
    else
        doctor_warning "${name} répond avec le code HTTP ${status}."
    fi
}

check_disk() {
    local mount_point="$1"
    local usage

    usage="$(
        df -P "$mount_point" 2>/dev/null |
            awk 'NR == 2 {gsub("%", "", $5); print $5}'
    )"

    if [[ -z "$usage" ]]; then
        doctor_warning \
            "Impossible de contrôler l'espace disque de ${mount_point}."
    elif (( usage >= 95 )); then
        doctor_error "Disque ${mount_point} utilisé à ${usage}%."
    elif (( usage >= 85 )); then
        doctor_warning "Disque ${mount_point} utilisé à ${usage}%."
    else
        doctor_ok \
            "Espace disque ${mount_point} correct (${usage}% utilisé)."
    fi
}

check_directory() {
    local directory="$1"

    if [[ ! -d "$directory" ]]; then
        doctor_error "Dossier absent : ${directory}"
    elif [[ ! -r "$directory" ]]; then
        doctor_error "Dossier non lisible : ${directory}"
    elif [[ ! -w "$directory" ]]; then
        doctor_warning "Dossier non inscriptible : ${directory}"
    else
        doctor_ok "Dossier accessible : ${directory}"
    fi
}

check_port() {
    local port="$1"
    local protocol="${2:-tcp}"

    if ss -lnH 2>/dev/null |
        grep -qE "[:.]${port}[[:space:]]"; then
        doctor_ok "Port ${port}/${protocol} en écoute."
    else
        doctor_warning "Port ${port}/${protocol} non détecté."
    fi
}

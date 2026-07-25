#!/usr/bin/env bash

if ! declare -F module_compose_file >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/manager.sh"
fi

service_error() {
    echo "[ERREUR] $*" >&2
}

service_success() {
    echo "[OK] $*"
}

service_warning() {
    echo "[ATTENTION] $*"
}

service_compose_file() {
    local service_name="$1"

    if module_is_enabled "${service_name}" &&
        module_has_compose "${service_name}"; then
        module_compose_file "${service_name}"
        return
    fi

    printf '%s/%s.yml\n' \
        "${MEDIASTACK_COMPOSE_DIR}" \
        "${service_name}"
}

service_exists() {
    local service_name="$1"
    [[ -f "$(service_compose_file "$service_name")" ]]
}

service_require() {
    local service_name="$1"

    if [[ -z "$service_name" ]]; then
        service_error "Nom du service manquant."
        return 1
    fi

    if ! service_exists "$service_name"; then
        service_error "Service inconnu : ${service_name}"
        service_error "Utilisez : media-service list"
        return 1
    fi
}

service_names() {
    local file

    shopt -s nullglob

    {
        for file in "${MEDIASTACK_COMPOSE_DIR}"/*.yml; do
            basename "${file}" .yml
        done

        module_enabled_names
    } | sort -u

    shopt -u nullglob
}

service_container_status() {
    local service_name="$1"

    if ! docker inspect "$service_name" >/dev/null 2>&1; then
        echo "absent"
        return
    fi

    docker inspect \
        --format '{{if .State.Running}}{{if .State.Health}}{{.State.Status}} ({{.State.Health.Status}}){{else}}{{.State.Status}}{{end}}{{else}}{{.State.Status}}{{end}}' \
        "$service_name" 2>/dev/null
}

service_is_running() {
    local service_name="$1"

    docker inspect \
        --format '{{.State.Running}}' \
        "$service_name" 2>/dev/null | grep -qx true
}

service_ports() {
    local service_name="$1"
    local ports

    ports="$(
        docker inspect \
            --format '{{range $port, $bindings := .NetworkSettings.Ports}}{{$port}}{{if $bindings}} -> {{range $bindings}}{{.HostIp}}:{{.HostPort}} {{end}}{{end}}{{println}}{{end}}' \
            "$service_name" 2>/dev/null
    )"

    if [[ -z "$ports" ]]; then
        echo "-"
    else
        echo "$ports" | paste -sd ',' -
    fi
}

service_list() {
    local service_name
    local status
    local ports

    printf '%-15s %-25s %s\n' "SERVICE" "STATUT" "PORTS"
    printf '%-15s %-25s %s\n' "---------------" "-------------------------" "------------------------------"

    while IFS= read -r service_name; do
        status="$(service_container_status "$service_name")"
        ports="$(service_ports "$service_name")"

        printf '%-15s %-25s %s\n' "$service_name" "$status" "$ports"
    done < <(service_names)
}

service_start() {
    local service_name="$1"
    local compose_file

    service_require "$service_name" || return 1
    compose_file="$(service_compose_file "$service_name")"

    docker compose -f "$compose_file" up -d
}

service_stop() {
    local service_name="$1"
    local compose_file

    service_require "$service_name" || return 1
    compose_file="$(service_compose_file "$service_name")"

    docker compose -f "$compose_file" stop
}

service_restart() {
    local service_name="$1"
    local compose_file

    service_require "$service_name" || return 1
    compose_file="$(service_compose_file "$service_name")"

    docker compose -f "$compose_file" restart
}

service_remove() {
    local service_name="$1"
    local compose_file

    service_require "$service_name" || return 1
    compose_file="$(service_compose_file "$service_name")"

    docker compose -f "$compose_file" down
}

service_logs() {
    local service_name="$1"
    local compose_file

    service_require "$service_name" || return 1
    compose_file="$(service_compose_file "$service_name")"

    docker compose -f "$compose_file" logs -f --tail=100
}

service_update() {
    local service_name="$1"
    local compose_file

    service_require "$service_name" || return 1
    compose_file="$(service_compose_file "$service_name")"

    echo "Téléchargement de la dernière image de ${service_name}..."
    docker compose -f "$compose_file" pull || return 1

    echo "Recréation de ${service_name}..."
    docker compose -f "$compose_file" up -d --force-recreate || return 1

    service_success "Service ${service_name} mis à jour."
}

service_status() {
    local service_name="$1"

    service_require "$service_name" || return 1

    echo "Service : ${service_name}"
    echo "Statut  : $(service_container_status "$service_name")"
    echo "Ports   : $(service_ports "$service_name")"

    if docker inspect "$service_name" >/dev/null 2>&1; then
        echo
        docker inspect \
            --format 'Image    : {{.Config.Image}}
Réseaux  : {{range $name, $_ := .NetworkSettings.Networks}}{{$name}} {{end}}
Démarré  : {{.State.StartedAt}}
Redémarrages : {{.RestartCount}}' \
            "$service_name"
    fi
}

service_start_all() {
    local service_name

    while IFS= read -r service_name; do
        echo
        echo "Démarrage de ${service_name}..."
        service_start "$service_name" || return 1
    done < <(service_names)

    service_success "Tous les services sont démarrés."
}

service_stop_all() {
    local services=()
    local index

    mapfile -t services < <(service_names)

    for ((index=${#services[@]} - 1; index>=0; index--)); do
        echo
        echo "Arrêt de ${services[$index]}..."
        service_stop "${services[$index]}" || return 1
    done

    service_success "Tous les services sont arrêtés."
}

service_update_all() {
    local service_name

    while IFS= read -r service_name; do
        echo
        echo "Mise à jour de ${service_name}..."
        service_update "$service_name" || return 1
    done < <(service_names)

    service_success "Tous les services sont à jour."
}

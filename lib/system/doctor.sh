#!/usr/bin/env bash

run_doctor() {
    local errors=0
    local warnings=0
    local checks=0

    doctor_section() {
        echo
        echo "[$1]"
        printf '%*s\n' 60 '' | tr ' ' '-'
    }

    doctor_ok() {
        checks=$((checks + 1))
        echo "[OK] $1"
    }

    doctor_warning() {
        checks=$((checks + 1))
        warnings=$((warnings + 1))
        echo "[WARN] $1"
    }

    doctor_error() {
        checks=$((checks + 1))
        errors=$((errors + 1))
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
        state="$(docker inspect \
            --format '{{.State.Status}}' \
            "$container" 2>/dev/null)"

        if [[ "$state" == "running" ]]; then
            doctor_ok "Conteneur ${container} actif."
        else
            doctor_error "Conteneur ${container} dans l'état : ${state}."
        fi
    }

    check_container_health() {
        local container="$1"
        local health

        health="$(docker inspect \
            --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
            "$container" 2>/dev/null || true)"

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
            status="$(curl \
                --silent \
                --output /dev/null \
                --write-out '%{http_code}' \
                --max-time 10 \
                --header "Host: ${host_header}" \
                "$url" 2>/dev/null || true)"
        else
            status="$(curl \
                --silent \
                --output /dev/null \
                --write-out '%{http_code}' \
                --max-time 10 \
                "$url" 2>/dev/null || true)"
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

        usage="$(df -P "$mount_point" 2>/dev/null |
            awk 'NR == 2 {gsub("%", "", $5); print $5}')"

        if [[ -z "$usage" ]]; then
            doctor_warning "Impossible de contrôler l'espace disque de ${mount_point}."
        elif (( usage >= 95 )); then
            doctor_error "Disque ${mount_point} utilisé à ${usage}%."
        elif (( usage >= 85 )); then
            doctor_warning "Disque ${mount_point} utilisé à ${usage}%."
        else
            doctor_ok "Espace disque ${mount_point} correct (${usage}% utilisé)."
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

    doctor_title

    doctor_section "Système"

    check_command docker "Docker"
    check_command curl "Curl"
    check_command ss "IpRoute2"

    if docker info >/dev/null 2>&1; then
        doctor_ok "Docker répond."
    else
        doctor_error "Docker ne répond pas."

        echo
        echo "Diagnostic interrompu : Docker est indispensable."
        return 1
    fi

    if docker compose version >/dev/null 2>&1; then
        doctor_ok "Docker Compose répond."
    else
        doctor_error "Docker Compose ne répond pas."
    fi

    doctor_section "Configuration"

    if [[ -d "${MEDIASTACK_HOME}/compose" ]]; then
        doctor_ok "Dossier Compose présent."
    else
        doctor_error "Dossier Compose absent : ${MEDIASTACK_HOME}/compose"
    fi

    local compose_files=()
    local compose_file
    local configured_service

    while IFS= read -r configured_service; do
        [[ -n "${configured_service}" ]] || continue
        compose_files+=(
            "$(service_compose_file "${configured_service}")"
        )
    done < <(service_names)

    if (( ${#compose_files[@]} == 0 )); then
        doctor_error "Aucun fichier Compose trouvé."
    else
        doctor_ok "${#compose_files[@]} fichier(s) Compose trouvé(s)."

        for compose_file in "${compose_files[@]}"; do
            check_compose_file "${compose_file}"
        done
    fi

    doctor_section "Réseau Docker"

    if docker network inspect mediastack_proxy >/dev/null 2>&1; then
        doctor_ok "Réseau mediastack_proxy présent."
    else
        doctor_error "Réseau mediastack_proxy absent."
    fi

    doctor_section "Services"

    local expected_services=()
    local service
    local module_doctor_script

    mapfile -t expected_services < <(service_names)

    for service in "${expected_services[@]}"; do
        check_container "${service}"

        if ! docker inspect "${service}" >/dev/null 2>&1; then
            continue
        fi

        check_network_membership             "${service}"             mediastack_proxy

        if module_is_enabled "${service}" &&
            module_has_doctor "${service}"; then

            module_doctor_script="$(
                module_doctor_file "${service}"
            )"

            unset -f module_doctor 2>/dev/null || true

            # shellcheck source=/dev/null
            source "${module_doctor_script}"

            if declare -F module_doctor >/dev/null 2>&1; then
                module_doctor
            else
                doctor_warning                     "Doctor du module ${service} invalide : fonction module_doctor absente."
            fi

            unset -f module_doctor 2>/dev/null || true
        else
            check_container_health "${service}"
        fi
    done

    doctor_section "Connectivité"


    doctor_section "Ports"

    check_port 80 tcp
    check_port 443 tcp

    doctor_section "Stockage"

    check_directory /opt/mediastack
    check_directory /opt/mediastack/compose
    check_directory /opt/mediastack/conf
    check_directory /opt/media

    check_disk /
    check_disk /opt/media

    doctor_section "Sécurité"

    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null |
            grep -q '^Status: active'; then
            doctor_ok "UFW actif."
        else
            doctor_warning "UFW installé mais inactif."
        fi
    else
        doctor_warning "UFW absent."
    fi

    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        doctor_ok "Fail2ban actif."
    else
        doctor_warning "Fail2ban inactif."
    fi

    if systemctl is-active --quiet unattended-upgrades 2>/dev/null; then
        doctor_ok "Mises à jour automatiques actives."
    else
        doctor_warning "Mises à jour automatiques inactives."
    fi

    local sshd_configuration

    sshd_configuration="$(
        /usr/sbin/sshd -T 2>/dev/null || true
    )"

    if grep -i '^passwordauthentication no$' \
        <<< "$sshd_configuration" >/dev/null; then
        doctor_ok "Authentification SSH par mot de passe désactivée."
    else
        doctor_warning "Authentification SSH par mot de passe potentiellement active."
    fi

    if grep -i '^permitrootlogin no$' \
        <<< "$sshd_configuration" >/dev/null; then
        doctor_ok "Connexion SSH root désactivée."
    else
        doctor_warning "Connexion SSH root non totalement désactivée."
    fi

    doctor_section "Résumé"

    echo "Contrôles     : ${checks}"
    echo "Avertissements: ${warnings}"
    echo "Erreurs       : ${errors}"

    echo

    if (( errors > 0 )); then
        echo "[ERROR] MediaStack présente ${errors} erreur(s)."
        return 1
    elif (( warnings > 0 )); then
        echo "[WARN] MediaStack fonctionne avec ${warnings} avertissement(s)."
        return 0
    else
        echo "[OK] MediaStack est pleinement opérationnel."
        return 0
    fi
}

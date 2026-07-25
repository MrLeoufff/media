#!/usr/bin/env bash

source "${MEDIASTACK_HOME}/lib/system/doctor_helpers.sh"

if ! declare -F module_enabled_names >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/manager.sh"
fi

if ! declare -F module_metadata_list >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/metadata.sh"
fi

if ! declare -F domain_get >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/web/proxy.sh"
fi

doctor_check_docker_versions() {
    local docker_version
    local compose_version
    local docker_major

    docker_version="$(docker --version 2>/dev/null || true)"
    compose_version="$(docker compose version 2>/dev/null || true)"

    if [[ -n "${docker_version}" ]]; then
        doctor_ok "Docker : ${docker_version}"
        docker_major="$(
            sed -n 's/.*version \([0-9]\+\).*/\1/p' <<< "${docker_version}"
        )"
        if [[ -n "${docker_major}" && "${docker_major}" -lt 24 ]]; then
            doctor_warning "Docker < 24 détecté ; MediaStack recommande Docker 24+."
        fi
    else
        doctor_error "Impossible de lire la version Docker."
    fi

    if [[ -n "${compose_version}" ]]; then
        doctor_ok "Compose : ${compose_version}"
    else
        doctor_error "Impossible de lire la version Docker Compose."
    fi
}

doctor_check_fail2ban() {
    local ignoreip_line
    local jail_file="/etc/fail2ban/jail.d/mediastack.conf"

    if ! command -v fail2ban-client >/dev/null 2>&1; then
        doctor_warning "Fail2ban absent."
        return
    fi

    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        doctor_ok "Fail2ban actif."
    else
        doctor_warning "Fail2ban inactif."
        return
    fi

    if fail2ban-client status sshd >/dev/null 2>&1; then
        doctor_ok "Jail sshd Fail2ban active."
    else
        doctor_warning "Jail sshd Fail2ban indisponible."
    fi

    if [[ -f "${jail_file}" ]]; then
        ignoreip_line="$(
            grep -E '^[[:space:]]*ignoreip[[:space:]]*=' "${jail_file}" || true
        )"
        if [[ -n "${ignoreip_line}" ]]; then
            doctor_ok "ignoreip configuré (${ignoreip_line#*= })."
            if grep -Eq '0\.0\.0\.0/0|::/0' <<< "${ignoreip_line}"; then
                doctor_warning "ignoreip trop permissif (0.0.0.0/0)."
            fi
        else
            doctor_warning "ignoreip absent de ${jail_file}."
        fi
    else
        doctor_warning "Fichier jail MediaStack absent : ${jail_file}"
    fi
}

doctor_check_backups() {
    local latest
    local age_days

    if [[ ! -d "${MEDIASTACK_BACKUP_DIR}" ]]; then
        doctor_ok "Aucune sauvegarde pour l'instant (dossier absent, normal)."
        return
    fi

    latest="$(
        find "${MEDIASTACK_BACKUP_DIR}" -maxdepth 1 -type f -name '*.tar.gz' \
            -printf '%T@ %p\n' 2>/dev/null |
            sort -nr |
            head -n1 |
            awk '{print $2}'
    )"

    if [[ -z "${latest}" ]]; then
        doctor_ok "Aucune archive de sauvegarde (normal tant qu'aucune n'a été créée)."
        return
    fi

    age_days="$(( ( $(date +%s) - $(stat -c %Y "${latest}") ) / 86400 ))"
    doctor_ok "Dernière sauvegarde : $(basename "${latest}") (${age_days} j)."

    if (( age_days > 14 )); then
        doctor_warning "Dernière sauvegarde âgée de plus de 14 jours."
    fi
}

doctor_check_proxy_coherence() {
    if [[ ! -f "${MEDIASTACK_CADDYFILE}" ]]; then
        doctor_warning "Caddyfile absent."
        return
    fi

    doctor_ok "Caddyfile présent."

    if grep -q 'Généré automatiquement par MediaStack\|Généré par MediaStack' \
        "${MEDIASTACK_CADDYFILE}" 2>/dev/null; then
        doctor_ok "Caddyfile géré par MediaStack."
    else
        doctor_warning "Caddyfile non généré par MediaStack (édition manuelle possible)."
    fi

    if [[ -n "$(domain_get)" ]]; then
        doctor_ok "Domaine mémorisé : $(domain_get)"
    else
        doctor_warning "Aucun domaine mémorisé (mode LAN)."
    fi

    doctor_ok "Mode TLS local : $(tls_mode_get)"
}

run_doctor() {
    local errors=0
    local warnings=0
    local checks=0

    doctor_title

    doctor_section "Système"

    check_command docker "Docker"
    check_command curl "Curl"
    check_command ss "IpRoute2"
    check_command python3 "Python 3"

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

    doctor_check_docker_versions

    doctor_section "Configuration"

    if [[ -d "${MEDIASTACK_MODULES_DIR}" ]]; then
        doctor_ok "Dossier modules présent."
    else
        doctor_error "Dossier modules absent : ${MEDIASTACK_MODULES_DIR}"
    fi

    if [[ -d "${MEDIASTACK_ENABLED_DIR}" ]]; then
        doctor_ok "Dossier enabled présent."
    else
        doctor_error "Dossier enabled absent : ${MEDIASTACK_ENABLED_DIR}"
    fi

    local compose_files=()
    local compose_file
    local configured_service
    local enabled_count=0

    while IFS= read -r configured_service; do
        [[ -n "${configured_service}" ]] || continue
        enabled_count=$((enabled_count + 1))
        compose_files+=(
            "$(service_compose_file "${configured_service}")"
        )
    done < <(service_names)

    if (( ${#compose_files[@]} == 0 )); then
        doctor_warning "Aucun module activé (utilisez media module install)."
    else
        doctor_ok "${enabled_count} module(s) activé(s)."

        for compose_file in "${compose_files[@]}"; do
            check_compose_file "${compose_file}"
        done
    fi

    doctor_check_proxy_coherence

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

        check_network_membership \
            "${service}" \
            mediastack_proxy

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
                doctor_warning \
                    "Doctor du module ${service} invalide : fonction module_doctor absente."
            fi

            unset -f module_doctor 2>/dev/null || true
        else
            check_container_health "${service}"
        fi
    done

    doctor_section "Connectivité"

    if getent hosts github.com >/dev/null 2>&1; then
        doctor_ok "Résolution DNS github.com OK."
    else
        doctor_warning "Impossible de résoudre github.com."
    fi

    # /v2/ sans auth renvoie souvent 401 : le registry est joignable.
    local docker_hub_status
    docker_hub_status="$(
        curl -sS -o /dev/null -w '%{http_code}' \
            --connect-timeout 5 \
            --max-time 10 \
            https://registry-1.docker.io/v2/ 2>/dev/null || true
    )"

    case "${docker_hub_status}" in
        200|401)
            doctor_ok "Accès au registry Docker Hub OK (${docker_hub_status})."
            ;;
        *)
            doctor_warning \
                "Registry Docker Hub injoignable (code=${docker_hub_status:-000})."
            ;;
    esac

    if [[ -n "$(domain_get)" ]]; then
        if getent hosts "$(domain_get)" >/dev/null 2>&1; then
            doctor_ok "Résolution DNS du domaine MediaStack OK."
        else
            doctor_warning "Domaine MediaStack non résolu : $(domain_get)"
        fi
    fi

    doctor_section "Ports"

    check_port 80 tcp
    check_port 443 tcp

    doctor_section "Stockage"

    check_directory "${MEDIASTACK_HOME}"
    check_directory "${MEDIASTACK_MODULES_DIR}"
    check_directory "${MEDIASTACK_ENABLED_DIR}"
    check_directory "${MEDIASTACK_CONFIG_DIR}"
    check_directory "${MEDIASTACK_DATA}"

    local storage_path
    local enabled_module

    while IFS= read -r enabled_module; do
        [[ -n "${enabled_module}" ]] || continue
        while IFS= read -r storage_path; do
            [[ -n "${storage_path}" ]] || continue
            [[ "${storage_path}" == *.sock ]] && continue
            [[ "${storage_path}" == */Caddyfile ]] && continue
            check_directory "${storage_path}"
        done < <(module_metadata_list "${enabled_module}" storage 2>/dev/null || true)
    done < <(module_enabled_names)

    check_disk /
    check_disk "${MEDIASTACK_DATA}"

    doctor_check_backups

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

    doctor_check_fail2ban

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

    local permit_root_login
    permit_root_login="$(
        awk 'tolower($1)=="permitrootlogin" {print tolower($2); exit}' \
            <<< "${sshd_configuration}"
    )"

    case "${permit_root_login}" in
        no)
            doctor_ok "Connexion SSH root désactivée."
            ;;
        prohibit-password|without-password)
            doctor_ok "Connexion SSH root par clé uniquement (prohibit-password)."
            ;;
        yes|"")
            doctor_warning \
                "Connexion SSH root autorisée par mot de passe (${permit_root_login:-inconnue})."
            ;;
        *)
            doctor_warning \
                "Paramètre PermitRootLogin inattendu : ${permit_root_login}."
            ;;
    esac

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

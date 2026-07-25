#!/usr/bin/env bash

source "${MEDIASTACK_HOME}/lib/system/doctor_helpers.sh"

run_doctor() {
    local errors=0
    local warnings=0
    local checks=0

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

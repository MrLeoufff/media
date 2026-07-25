#!/usr/bin/env bash

# ==============================================================================
# MediaStack - Install / uninstall zero-touch des modules
# ==============================================================================

if ! declare -F module_names >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/manager.sh"
fi

if ! declare -F module_metadata_get >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/metadata.sh"
fi

if ! declare -F service_start >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/services/manager.sh"
fi

if ! declare -F proxy_regenerate >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/web/proxy.sh"
fi

module_lifecycle_run_doctor() {
    local module_name="$1"
    local doctor_file
    local doctor_rc=0

    module_has_doctor "${module_name}" || return 0

    if ! declare -F doctor_error >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        source "${MEDIASTACK_HOME}/lib/system/doctor_helpers.sh"
    fi

    # Compteurs utilisés par doctor_ok / doctor_warning / doctor_error
    checks=0
    warnings=0
    errors=0

    doctor_file="$(module_doctor_file "${module_name}")"
    unset -f module_doctor 2>/dev/null || true
    # shellcheck source=/dev/null
    source "${doctor_file}"

    if ! declare -F module_doctor >/dev/null 2>&1; then
        module_lifecycle_error \
            "Le fichier ${doctor_file} ne définit pas module_doctor()."
        return 1
    fi

    echo "Diagnostic du module ${module_name}"
    echo "------------------------------------------------------------"
    module_doctor || doctor_rc=$?
    unset -f module_doctor 2>/dev/null || true

    if (( errors > 0 || doctor_rc != 0 )); then
        module_lifecycle_error \
            "Diagnostic critique en échec pour ${module_name} (errors=${errors}, rc=${doctor_rc})."
        return 1
    fi

    if (( warnings > 0 )); then
        module_lifecycle_info \
            "Diagnostic avec ${warnings} avertissement(s) — installation poursuivie."
    fi

    return 0
}

module_lifecycle_error() {
    echo "[ERREUR] $*" >&2
}

module_lifecycle_info() {
    echo "[INFO] $*"
}

module_lifecycle_ok() {
    echo "[OK] $*"
}

module_is_host_dependency() {
    local dependency="$1"

    case "${dependency}" in
        docker|python3|curl)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

module_check_host_dependency() {
    local dependency="$1"

    case "${dependency}" in
        docker)
            command -v docker >/dev/null 2>&1 || {
                module_lifecycle_error "Dépendance hôte manquante : docker"
                return 1
            }
            docker compose version >/dev/null 2>&1 || {
                module_lifecycle_error "Docker Compose est indisponible."
                return 1
            }
            ;;
        python3)
            command -v python3 >/dev/null 2>&1 || {
                module_lifecycle_error "Dépendance hôte manquante : python3"
                return 1
            }
            ;;
        curl)
            command -v curl >/dev/null 2>&1 || {
                module_lifecycle_error "Dépendance hôte manquante : curl"
                return 1
            }
            ;;
    esac
}

module_ensure_network() {
    local network_name="${1:-mediastack_proxy}"

    if docker network inspect "${network_name}" >/dev/null 2>&1; then
        module_lifecycle_ok "Réseau ${network_name} déjà présent."
        return 0
    fi

    docker network create "${network_name}" >/dev/null
    module_lifecycle_ok "Réseau ${network_name} créé."
}

module_ensure_storage_path() {
    local path="$1"

    [[ -n "${path}" ]] || return 0

    # Socket Docker ou autre fichier spécial : ne pas créer.
    if [[ "${path}" == *.sock ]]; then
        if [[ ! -e "${path}" ]]; then
            module_lifecycle_error "Socket introuvable : ${path}"
            return 1
        fi
        return 0
    fi

    # Fichier de configuration attendu (ex. Caddyfile) : créer le parent.
    if [[ "${path}" == */Caddyfile || "${path}" == *.yml || "${path}" == *.yaml || "${path}" == *.conf ]]; then
        mkdir -p "$(dirname "${path}")"
        return 0
    fi

    mkdir -p "${path}"
}

module_ensure_storage() {
    local module_name="$1"
    local path

    while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        module_ensure_storage_path "${path}" || return 1
        module_lifecycle_ok "Stockage prêt : ${path}"
    done < <(module_metadata_list "${module_name}" storage 2>/dev/null || true)
}

module_run_optional_script() {
    local module_name="$1"
    local script_kind="$2"
    local script_file

    case "${script_kind}" in
        install) script_file="$(module_install_file "${module_name}")" ;;
        uninstall) script_file="$(module_uninstall_file "${module_name}")" ;;
        *) return 0 ;;
    esac

    if [[ -x "${script_file}" ]]; then
        module_lifecycle_info "Exécution de ${script_kind}.sh pour ${module_name}..."
        # shellcheck source=/dev/null
        source "${script_file}"
    fi
}

module_dependents() {
    local target_module="$1"
    local module_name
    local dependency

    while IFS= read -r module_name; do
        [[ -n "${module_name}" ]] || continue
        module_is_enabled "${module_name}" || continue
        [[ "${module_name}" == "${target_module}" ]] && continue

        while IFS= read -r dependency; do
            [[ -n "${dependency}" ]] || continue
            if [[ "${dependency}" == "${target_module}" ]]; then
                printf '%s\n' "${module_name}"
            fi
        done < <(module_metadata_list "${module_name}" dependencies 2>/dev/null || true)
    done < <(module_names)
}

module_install_dependencies() {
    local module_name="$1"
    local domain="${2:-}"
    local tls_mode="${3:-}"
    local dependency

    while IFS= read -r dependency; do
        [[ -n "${dependency}" ]] || continue

        if module_is_host_dependency "${dependency}"; then
            module_check_host_dependency "${dependency}" || return 1
            module_lifecycle_ok "Dépendance hôte OK : ${dependency}"
            continue
        fi

        if ! module_exists "${dependency}"; then
            module_lifecycle_error \
                "Dépendance introuvable pour ${module_name} : ${dependency}"
            return 1
        fi

        if module_is_enabled "${dependency}" &&
            service_is_running "${dependency}"; then
            module_lifecycle_ok "Dépendance déjà active : ${dependency}"
            continue
        fi

        module_lifecycle_info "Installation de la dépendance : ${dependency}"
        module_install "${dependency}" "${domain}" "${tls_mode}" || return 1
    done < <(module_metadata_list "${module_name}" dependencies 2>/dev/null || true)
}

module_install_summary() {
    local module_name="$1"
    local domain
    local container_name
    local state
    local site

    domain="$(domain_get)"
    container_name="$(
        module_metadata_get_or_default \
            "${module_name}" \
            container.name \
            "${module_name}"
    )"
    state="$(service_container_status "${container_name}")"
    site="$(proxy_site_address "${domain}")"

    echo
    echo "------------------------------------------------------------"
    echo " Résumé d'installation : ${module_name}"
    echo "------------------------------------------------------------"
    echo "Module     : ${module_name}"
    echo "Conteneur  : ${container_name} (${state})"
    echo "Domaine    : ${domain:-'(mode LAN / :80)'}"
    echo "URL proxy  : ${site}"
    echo "Caddyfile  : ${MEDIASTACK_CADDYFILE}"
    echo "Données    : ${MEDIASTACK_DATA}"
    echo "------------------------------------------------------------"
    echo
}

module_install() {
    local module_name="$1"
    local domain="${2:-}"
    local tls_mode="${3:-}"
    local network_name
    local container_name

    if [[ -z "${module_name}" ]]; then
        module_lifecycle_error "Nom du module manquant."
        return 1
    fi

    if ! module_exists "${module_name}"; then
        module_lifecycle_error "Module inconnu : ${module_name}"
        return 1
    fi

    if ! module_is_complete "${module_name}"; then
        module_lifecycle_error "Module incomplet : ${module_name}"
        return 1
    fi

    require_root
    require_command docker
    require_command python3

    # Choix utilisateur si non fournis en CLI (--domain / --tls).
    if [[ -z "${domain}" ]]; then
        domain="$(domain_prompt)"
    fi

    if [[ -z "${tls_mode}" ]]; then
        tls_mode="$(tls_mode_prompt)"
    fi

    tls_mode_set "${tls_mode}" || return 1

    if [[ -n "${domain}" ]]; then
        domain_set "${domain}"
    fi

    module_lifecycle_info \
        "Installation du module ${module_name} (domaine=${domain:-LAN}, tls=${tls_mode})..."

    module_install_dependencies "${module_name}" "$(domain_get)" "${tls_mode}" || return 1

    network_name="$(
        module_metadata_get_or_default \
            "${module_name}" \
            network.name \
            "mediastack_proxy"
    )"
    module_ensure_network "${network_name}" || return 1
    module_ensure_storage "${module_name}" || return 1

    module_enable "${module_name}" || return 1
    module_lifecycle_ok "Module activé : ${module_name}"

    proxy_regenerate "$(domain_get)" || return 1

    module_run_optional_script "${module_name}" install

    container_name="$(
        module_metadata_get_or_default \
            "${module_name}" \
            container.name \
            "${module_name}"
    )"

    module_lifecycle_info "Démarrage Docker Compose (${module_name})..."
    service_start "${module_name}" || return 1
    module_lifecycle_ok "Conteneur démarré : ${container_name}"

    module_lifecycle_info "Diagnostic du module..."
    if ! module_lifecycle_run_doctor "${module_name}"; then
        module_lifecycle_error \
            "Installation de ${module_name} annulée : échec du diagnostic."
        return 1
    fi

    module_install_summary "${module_name}"
    module_lifecycle_ok "Installation terminée : ${module_name}"
}

module_uninstall() {
    local module_name="$1"
    shift || true

    local purge=false
    local assume_yes=false
    local arg
    local dependent
    local dependents=()
    local path
    local container_name

    if [[ -z "${module_name}" ]]; then
        module_lifecycle_error "Nom du module manquant."
        return 1
    fi

    if ! module_exists "${module_name}"; then
        module_lifecycle_error "Module inconnu : ${module_name}"
        return 1
    fi

    for arg in "$@"; do
        case "${arg}" in
            --purge)
                purge=true
                ;;
            --keep-data)
                purge=false
                ;;
            --yes|-y)
                assume_yes=true
                ;;
            *)
                module_lifecycle_error "Option inconnue : ${arg}"
                return 1
                ;;
        esac
    done

    require_root

    mapfile -t dependents < <(module_dependents "${module_name}")

    if (( ${#dependents[@]} > 0 )); then
        module_lifecycle_error \
            "Impossible de désinstaller ${module_name} : requis par ${dependents[*]}"
        return 1
    fi

    if [[ "${purge}" == true && "${assume_yes}" != true ]]; then
        if ! confirm_action \
            "Purger les données de ${module_name} (irréversible) ?"; then
            module_lifecycle_info "Désinstallation annulée."
            return 1
        fi
    fi

    module_lifecycle_info "Désinstallation du module ${module_name}..."

    if module_is_enabled "${module_name}" ||
        docker inspect "${module_name}" >/dev/null 2>&1; then
        service_remove "${module_name}" 2>/dev/null || \
            docker rm -f "${module_name}" >/dev/null 2>&1 || true
        module_lifecycle_ok "Conteneur arrêté : ${module_name}"
    fi

    module_run_optional_script "${module_name}" uninstall

    module_disable "${module_name}" 2>/dev/null || true
    module_lifecycle_ok "Module désactivé : ${module_name}"

    proxy_regenerate "$(domain_get)" || true

    if [[ "${purge}" == true ]]; then
        while IFS= read -r path; do
            [[ -n "${path}" ]] || continue
            [[ "${path}" == *.sock ]] && continue
            [[ "${path}" == */Caddyfile ]] && continue
            [[ "${path}" == "${MEDIASTACK_DATA}" ]] && continue
            [[ "${path}" == "${MEDIASTACK_HOME}"* ]] && continue

            if [[ -e "${path}" ]]; then
                rm -rf "${path}"
                module_lifecycle_ok "Données supprimées : ${path}"
            fi
        done < <(module_metadata_list "${module_name}" storage 2>/dev/null || true)
    else
        module_lifecycle_ok "Données conservées (--keep-data)."
    fi

    container_name="$(
        module_metadata_get_or_default \
            "${module_name}" \
            container.name \
            "${module_name}"
    )"

    echo
    echo "------------------------------------------------------------"
    echo " Résumé de désinstallation : ${module_name}"
    echo "------------------------------------------------------------"
    echo "Module     : ${module_name}"
    echo "Conteneur  : ${container_name}"
    echo "Données    : $([[ "${purge}" == true ]] && echo purgées || echo conservées)"
    echo "------------------------------------------------------------"
    echo

    module_lifecycle_ok "Désinstallation terminée : ${module_name}"
}

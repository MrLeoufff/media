#!/usr/bin/env bash

if ! declare -F module_names >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/manager.sh"
fi

if ! declare -F module_metadata_get >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/metadata.sh"
fi

if ! declare -F doctor_ok >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/system/doctor_helpers.sh"
fi

if ! declare -F module_install >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/lifecycle.sh"
fi

module_command_error() {
    echo "[ERREUR] $*" >&2
}

# Résout l'argument utilisateur vers un id canonique (stdout).
module_command_resolve() {
    local input="${1:-}"
    local resolved

    resolved="$(module_resolve_name "${input}")" || return 1
    printf '%s\n' "${resolved}"
}

module_command_list() {
    local module_name
    local display_name
    local version
    local category
    local state

    printf '%-15s %-22s %-12s %-15s %s\n' \
        "MODULE" \
        "NOM" \
        "VERSION" \
        "CATÉGORIE" \
        "ÉTAT"

    printf '%-15s %-22s %-12s %-15s %s\n' \
        "---------------" \
        "----------------------" \
        "------------" \
        "---------------" \
        "----------"

    while IFS= read -r module_name; do
        [[ -n "${module_name}" ]] || continue

        display_name="$(
            module_metadata_get_or_default \
                "${module_name}" \
                displayName \
                "${module_name}"
        )"

        version="$(
            module_metadata_get_or_default \
                "${module_name}" \
                version \
                "-"
        )"

        category="$(
            module_metadata_get_or_default \
                "${module_name}" \
                category \
                "-"
        )"

        if module_is_enabled "${module_name}"; then
            state="activé"
        else
            state="désactivé"
        fi

        printf '%-15s %-22s %-12s %-15s %s\n' \
            "${module_name}" \
            "${display_name}" \
            "${version}" \
            "${category}" \
            "${state}"
    done < <(module_names)
}

module_command_info() {
    local module_name="${1:-}"
    local metadata_file
    local display_name
    local version
    local description
    local category
    local container_name
    local container_image
    local homepage
    local state
    local dependencies

    if [[ -z "${module_name}" ]]; then
        cat <<'USAGE' >&2
Utilisation : media module info <module>

Exemples :
  media module info jellyfin
  media module info Jellyfin

Liste des modules : media module list
Recherche         : media search [query]
USAGE
        return 1
    fi

    module_name="$(module_command_resolve "${module_name}")" || return 1

    metadata_file="$(module_metadata_file "${module_name}")"

    display_name="$(
        module_metadata_get_or_default \
            "${module_name}" \
            displayName \
            "${module_name}"
    )"

    version="$(
        module_metadata_get_or_default \
            "${module_name}" \
            version \
            "-"
    )"

    description="$(
        module_metadata_get_or_default \
            "${module_name}" \
            description \
            "-"
    )"

    category="$(
        module_metadata_get_or_default \
            "${module_name}" \
            category \
            "-"
    )"

    container_name="$(
        module_metadata_get_or_default \
            "${module_name}" \
            container.name \
            "-"
    )"

    container_image="$(
        module_metadata_get_or_default \
            "${module_name}" \
            container.image \
            "-"
    )"

    homepage="$(
        module_metadata_get_or_default \
            "${module_name}" \
            homepage \
            "-"
    )"

    if module_is_enabled "${module_name}"; then
        state="activé"
    else
        state="désactivé"
    fi

    dependencies="$(
        module_metadata_list \
            "${module_name}" \
            dependencies 2>/dev/null |
            paste -sd ', ' -
    )"

    [[ -n "${dependencies}" ]] || dependencies="-"

    echo "Module       : ${module_name}"
    echo "Nom          : ${display_name}"
    echo "Version      : ${version}"
    echo "Description  : ${description}"
    echo "Catégorie    : ${category}"
    echo "État         : ${state}"
    echo "Conteneur    : ${container_name}"
    echo "Image        : ${container_image}"
    echo "Dépendances  : ${dependencies}"
    echo "Site         : ${homepage}"
    echo "Manifeste    : ${metadata_file}"
}

module_command_enable() {
    local module_name="${1:-}"

    if [[ -z "${module_name}" ]]; then
        module_command_error "Nom du module manquant."
        return 1
    fi

    module_name="$(module_command_resolve "${module_name}")" || return 1

    if module_is_enabled "${module_name}"; then
        echo "[OK] Module déjà activé : ${module_name}"
        return 0
    fi

    module_enable "${module_name}"
    echo "[OK] Module activé : ${module_name}"
}

module_command_disable() {
    local module_name="${1:-}"

    if [[ -z "${module_name}" ]]; then
        module_command_error "Nom du module manquant."
        return 1
    fi

    module_name="$(module_command_resolve "${module_name}")" || return 1

    if ! module_is_enabled "${module_name}"; then
        echo "[OK] Module déjà désactivé : ${module_name}"
        return 0
    fi

    module_disable "${module_name}"
    echo "[OK] Module désactivé : ${module_name}"
}

module_command_doctor() {
    local module_name="${1:-}"
    local doctor_file

    if [[ -z "${module_name}" ]]; then
        module_command_error "Nom du module manquant."
        return 1
    fi

    module_name="$(module_command_resolve "${module_name}")" || return 1

    if ! module_has_doctor "${module_name}"; then
        module_command_error \
            "Aucun diagnostic disponible pour le module ${module_name}."
        return 1
    fi

    doctor_file="$(module_doctor_file "${module_name}")"

    unset -f module_doctor 2>/dev/null || true
    # shellcheck source=/dev/null
    source "${doctor_file}"

    if ! declare -F module_doctor >/dev/null 2>&1; then
        module_command_error \
            "Le fichier ${doctor_file} ne définit pas module_doctor()."
        return 1
    fi

    echo "Diagnostic du module ${module_name}"
    echo "------------------------------------------------------------"

    module_doctor
}

module_command_install() {
    local module_name=""
    local domain=""
    local tls_mode=""
    local access_mode=""
    local want_local=false
    local want_domain=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --local)
                want_local=true
                ;;
            --domain)
                shift
                domain="${1:-}"
                [[ -n "${domain}" ]] || {
                    module_command_error "Usage : --domain <fqdn>"
                    return 1
                }
                want_domain=true
                ;;
            --domain=*)
                domain="${1#--domain=}"
                [[ -n "${domain}" ]] || {
                    module_command_error "Usage : --domain=<fqdn>"
                    return 1
                }
                want_domain=true
                ;;
            --tls)
                shift
                tls_mode="${1:-}"
                [[ -n "${tls_mode}" ]] || {
                    module_command_error "Usage : --tls off|auto"
                    return 1
                }
                ;;
            --tls=*)
                tls_mode="${1#--tls=}"
                ;;
            -*)
                module_command_error "Option inconnue : $1"
                return 1
                ;;
            *)
                if [[ -z "${module_name}" ]]; then
                    module_name="$1"
                else
                    module_command_error "Argument inattendu : $1"
                    return 1
                fi
                ;;
        esac
        shift
    done

    if [[ "${want_local}" == true && "${want_domain}" == true ]]; then
        module_command_error "--local est incompatible avec --domain."
        return 1
    fi

    if [[ -z "${module_name}" ]]; then
        module_command_error "Nom du module manquant."
        return 1
    fi

    # Module absent localement : tenter le catalogue (source distante).
    if ! module_resolve_name "${module_name}" >/dev/null 2>&1; then
        if ! declare -F catalog_ensure_module >/dev/null 2>&1; then
            # shellcheck source=/dev/null
            source "${MEDIASTACK_HOME}/lib/catalog/index.sh" 2>/dev/null || true
        fi
        if declare -F catalog_ensure_module >/dev/null 2>&1; then
            catalog_ensure_module "${module_name}" >/dev/null || true
        fi
    fi

    module_name="$(module_command_resolve "${module_name}")" || return 1

    if [[ "${want_local}" == true ]]; then
        access_mode="local"
    elif [[ "${want_domain}" == true ]]; then
        access_mode="internet"
    fi

    MEDIASTACK_ACCESS_MODE="${access_mode}" \
        module_install "${module_name}" "${domain}" "${tls_mode}"
}

module_command_uninstall() {
    local module_name=""
    local opts=()
    local arg

    for arg in "$@"; do
        case "${arg}" in
            --purge|--keep-data|--yes|-y)
                opts+=("${arg}")
                ;;
            -*)
                module_command_error "Option inconnue : ${arg}"
                return 1
                ;;
            *)
                if [[ -z "${module_name}" ]]; then
                    module_name="${arg}"
                else
                    module_command_error "Argument inattendu : ${arg}"
                    return 1
                fi
                ;;
        esac
    done

    if [[ -z "${module_name}" ]]; then
        module_command_error "Nom du module manquant."
        return 1
    fi

    module_name="$(module_command_resolve "${module_name}")" || return 1
    module_uninstall "${module_name}" "${opts[@]}"
}

module_command_help() {
    cat <<'HELP'
Utilisation :
  media module list
  media module info <module>
  media module enable <module>
  media module disable <module>
  media module install <module> [--local|--domain <fqdn>] [--tls off|auto]
  media module uninstall <module> [--keep-data|--purge] [--yes]
  media module doctor <module>

Installation zero-touch :
  # Interactif : choix local (LAN) ou internet (domaine + TLS)
  media module install jellyfin

  # Local uniquement (pas de domaine, :80)
  media module install jellyfin --local

  # Internet / explicite
  media module install jellyfin --domain media.example.fr --tls off
  media module install jellyfin --domain media.example.fr --tls auto
HELP
}

module_command_main() {
    local command_name="${1:-help}"
    shift || true

    case "${command_name}" in
        list)
            module_command_list
            ;;
        info)
            module_command_info "${1:-}"
            ;;
        enable)
            module_command_enable "${1:-}"
            ;;
        disable)
            module_command_disable "${1:-}"
            ;;
        install)
            module_command_install "$@"
            ;;
        uninstall)
            module_command_uninstall "$@"
            ;;
        doctor)
            module_command_doctor "${1:-}"
            ;;
        help|-h|--help)
            module_command_help
            ;;
        *)
            module_command_error \
                "Commande de module inconnue : ${command_name}"
            echo
            module_command_help
            return 1
            ;;
    esac
}

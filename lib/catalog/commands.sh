#!/usr/bin/env bash

if ! declare -F catalog_entries >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${MEDIASTACK_HOME}/lib/catalog/index.sh"
fi

if ! declare -F module_command_info >/dev/null 2>&1; then
    # shellcheck source=/dev/null
    source "${MEDIASTACK_HOME}/lib/modules/commands.sh"
fi

catalog_command_error() {
    echo "[ERREUR] $*" >&2
}

catalog_command_search() {
    local query=""
    local refresh=false
    local arg
    local name
    local display
    local version
    local category
    local description
    local source
    local count=0

    for arg in "$@"; do
        case "${arg}" in
            --refresh)
                refresh=true
                ;;
            -*)
                catalog_command_error "Option inconnue : ${arg}"
                return 1
                ;;
            *)
                if [[ -z "${query}" ]]; then
                    query="${arg}"
                else
                    query="${query} ${arg}"
                fi
                ;;
        esac
    done

    if [[ "${refresh}" == true ]]; then
        catalog_refresh || return 1
    fi

    printf '%-14s %-18s %-10s %-14s %s\n' \
        "MODULE" "NOM" "VERSION" "CATÉGORIE" "DESCRIPTION"
    printf '%-14s %-18s %-10s %-14s %s\n' \
        "--------------" "------------------" "----------" "--------------" "-----------"

    while IFS='|' read -r name display version category description source; do
        [[ -n "${name}" ]] || continue
        printf '%-14s %-18s %-10s %-14s %s\n' \
            "${name}" \
            "${display}" \
            "${version}" \
            "${category}" \
            "${description}"
        count=$((count + 1))
    done < <(catalog_entries_query "${query}")

    if (( count == 0 )); then
        echo "(aucun résultat)"
        return 0
    fi
}

catalog_command_refresh() {
    catalog_refresh "$@"
}

catalog_command_help() {
    cat <<'HELP'
Utilisation :
  media search [query] [--refresh]
  media catalog refresh [url]
  media catalog search [query]

  media list
  media info <module>
  media install <module> [--local|--domain <fqdn>] [--tls off|auto]

Le catalogue local est catalog/index.yml.
media search --refresh télécharge l'index distant dans conf/catalog-cache.yml.
HELP
}

catalog_command_main() {
    local command_name="${1:-help}"
    shift || true

    case "${command_name}" in
        search)
            catalog_command_search "$@"
            ;;
        refresh)
            catalog_command_refresh "$@"
            echo "[OK] Catalogue actualisé."
            ;;
        help|-h|--help)
            catalog_command_help
            ;;
        *)
            catalog_command_error "Commande catalogue inconnue : ${command_name}"
            catalog_command_help
            return 1
            ;;
    esac
}

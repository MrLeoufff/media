#!/usr/bin/env bash

# ==============================================================================
# MediaStack - Génération automatique du reverse-proxy (Caddy)
# ==============================================================================

if ! declare -F module_enabled_names >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/manager.sh"
fi

if ! declare -F module_metadata_get_or_default >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/metadata.sh"
fi

: "${MEDIASTACK_DOMAIN_FILE:=${MEDIASTACK_CONFIG_DIR}/domain}"
: "${MEDIASTACK_TLS_MODE_FILE:=${MEDIASTACK_CONFIG_DIR}/tls-mode}"

domain_file_path() {
    printf '%s\n' "${MEDIASTACK_DOMAIN_FILE}"
}

tls_mode_file_path() {
    printf '%s\n' "${MEDIASTACK_TLS_MODE_FILE}"
}

domain_normalize() {
    local domain="${1:-}"

    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%/*}"

    printf '%s\n' "${domain}"
}

# Mode TLS du Caddy local MediaStack :
#   off  (défaut) — HTTP backend, TLS terminé en amont (ex. m710q)
#   auto          — HTTPS automatique Let's Encrypt (MediaStack = edge)
tls_mode_get() {
    local mode_file
    local mode

    if [[ -n "${MEDIASTACK_TLS_MODE:-}" ]]; then
        mode="${MEDIASTACK_TLS_MODE}"
    else
        mode_file="$(tls_mode_file_path)"
        if [[ -f "${mode_file}" ]]; then
            mode="$(tr -d '[:space:]' < "${mode_file}")"
        else
            mode="off"
        fi
    fi

    case "${mode}" in
        off|auto)
            printf '%s\n' "${mode}"
            ;;
        *)
            printf 'off\n'
            ;;
    esac
}

tls_mode_set() {
    local mode="${1:-off}"
    local mode_file

    case "${mode}" in
        off|auto)
            ;;
        *)
            echo "[ERREUR] Mode TLS invalide : ${mode} (off|auto)" >&2
            return 1
            ;;
    esac

    mode_file="$(tls_mode_file_path)"
    mkdir -p "$(dirname "${mode_file}")"
    printf '%s\n' "${mode}" > "${mode_file}"
}

# Demande interactive du mode TLS si non fourni en CLI.
# Non interactif (pas de TTY) => conserve le mode mémorisé, sinon off.
tls_mode_prompt() {
    local current
    local choice

    current="$(tls_mode_get)"

    if [[ ! -t 0 ]]; then
        printf '%s\n' "${current}"
        return 0
    fi

    echo
    echo "Mode TLS du Caddy local MediaStack"
    echo "------------------------------------------------------------"
    echo "  1) off  — HTTP backend (TLS terminé en amont, ex. m710q)"
    echo "  2) auto — HTTPS automatique Let's Encrypt (MediaStack = edge)"
    echo
    echo "Mode actuel : ${current}"
    read -r -p "Choix [1/2] (Entrée = conserver ${current}) : " choice

    case "${choice}" in
        "" )
            printf '%s\n' "${current}"
            ;;
        1|off|OFF)
            printf 'off\n'
            ;;
        2|auto|AUTO)
            printf 'auto\n'
            ;;
        *)
            echo "[ATTENTION] Choix invalide, conservation de : ${current}" >&2
            printf '%s\n' "${current}"
            ;;
    esac
}

# Demande interactive du domaine si absent.
# Entrée vide => conserve le domaine mémorisé ou mode LAN.
domain_prompt() {
    local current
    local answer

    current="$(domain_get)"

    if [[ ! -t 0 ]]; then
        printf '%s\n' "${current}"
        return 0
    fi

    echo
    echo "Domaine public MediaStack"
    echo "------------------------------------------------------------"
    if [[ -n "${current}" ]]; then
        echo "Domaine actuel : ${current}"
        read -r -p "Nouveau domaine (Entrée = conserver) : " answer
    else
        read -r -p "Domaine (ex. media.example.fr, Entrée = mode LAN :80) : " answer
    fi

    if [[ -n "${answer}" ]]; then
        domain_normalize "${answer}"
    else
        printf '%s\n' "${current}"
    fi
}

domain_get() {
    local domain_file
    domain_file="$(domain_file_path)"

    if [[ -f "${domain_file}" ]]; then
        domain_normalize "$(tr -d '[:space:]' < "${domain_file}")"
    fi
}

domain_set() {
    local domain
    local domain_file

    domain="$(domain_normalize "$1")"
    domain_file="$(domain_file_path)"
    mkdir -p "$(dirname "${domain_file}")"
    printf '%s\n' "${domain}" > "${domain_file}"
}

# Adresse de site Caddy selon le mode TLS.
# - tls off  + domaine => http://domaine  (derrière reverse-proxy amont)
# - tls auto + domaine => domaine nu      (HTTPS auto Caddy)
# - sans domaine       => :80
proxy_site_address() {
    local domain="${1:-}"
    local tls_mode

    [[ -n "${domain}" ]] || domain="$(domain_get)"
    tls_mode="$(tls_mode_get)"

    if [[ -z "${domain}" ]]; then
        printf ':80\n'
        return
    fi

    if [[ "${domain}" == http://* || "${domain}" == https://* ]]; then
        printf '%s\n' "${domain}"
        return
    fi

    domain="$(domain_normalize "${domain}")"

    if [[ "${tls_mode}" == "auto" ]]; then
        printf '%s\n' "${domain}"
    else
        printf 'http://%s\n' "${domain}"
    fi
}

proxy_module_enabled() {
    local module_name="$1"
    local enabled

    enabled="$(
        module_metadata_get_or_default \
            "${module_name}" \
            proxy.enabled \
            "false"
    )"

    [[ "${enabled}" == "true" ]]
}

proxy_is_root_path() {
    local path="${1:-/}"

    [[ -z "${path}" || "${path}" == "/" || "${path}" == "/*" ]]
}

proxy_emit_route() {
    local module_name="$1"
    local target
    local path

    if ! proxy_module_enabled "${module_name}"; then
        return 0
    fi

    target="$(
        module_metadata_get_or_default \
            "${module_name}" \
            proxy.target \
            ""
    )"

    [[ -n "${target}" ]] || return 0

    path="$(
        module_metadata_get_or_default \
            "${module_name}" \
            proxy.path \
            "/"
    )"

    printf '%s\t%s\t%s\n' "${module_name}" "${path}" "${target}"
}

# Collecte les routes des modules enabled.
# Argument optionnel : module candidat (pas encore enabled) à inclure.
proxy_collect_routes() {
    local candidate_module="${1:-}"
    local module_name
    local seen=""

    while IFS= read -r module_name; do
        [[ -n "${module_name}" ]] || continue
        proxy_emit_route "${module_name}"
        seen="${seen}|${module_name}|"
    done < <(module_enabled_names)

    if [[ -n "${candidate_module}" && "${seen}" != *"|${candidate_module}|"* ]]; then
        proxy_emit_route "${candidate_module}"
    fi
}

# Valide les routes avant activation d'un module (évite enabled/ orphelin).
proxy_validate_module_routes() {
    local module_name="$1"
    local routes=()
    local line

    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        routes+=("${line}")
    done < <(proxy_collect_routes "${module_name}")

    if (( ${#routes[@]} == 0 )); then
        return 0
    fi

    proxy_validate_routes "${routes[@]}"
}

# Refuse plusieurs modules sur le même path (dont /).
proxy_validate_routes() {
    local routes=("$@")
    local line
    local module_name
    local path
    local target
    local seen_paths=()
    local seen_modules=()
    local idx
    local root_modules=()

    for line in "${routes[@]}"; do
        IFS=$'\t' read -r module_name path target <<< "${line}"
        [[ -n "${path}" ]] || path="/"

        if proxy_is_root_path "${path}"; then
            root_modules+=("${module_name}")
            path="/"
        fi

        for idx in "${!seen_paths[@]}"; do
            if [[ "${seen_paths[$idx]}" == "${path}" ]]; then
                echo "[ERREUR] Conflit de route proxy '${path}' entre ${seen_modules[$idx]} et ${module_name}." >&2
                echo "[ERREUR] Utilisez un sous-domaine, un path distinct, ou un seul module sur '/'." >&2
                return 1
            fi
        done

        seen_paths+=("${path}")
        seen_modules+=("${module_name}")
    done

    if (( ${#root_modules[@]} > 1 )); then
        echo "[ERREUR] Plusieurs modules proxy sur path=/ : ${root_modules[*]}" >&2
        return 1
    fi

    return 0
}

proxy_write_caddyfile() {
    local domain="${1:-}"
    local site_address
    local routes=()
    local line
    local module_name
    local path
    local target
    local default_target=""
    local default_module=""
    local has_path_routes=false

    site_address="$(proxy_site_address "${domain}")"
    mkdir -p "${MEDIASTACK_CONFIG_DIR}"

    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        routes+=("${line}")
    done < <(proxy_collect_routes)

    if (( ${#routes[@]} > 0 )); then
        proxy_validate_routes "${routes[@]}" || return 1
    fi

    if (( ${#routes[@]} == 0 )); then
        cat > "${MEDIASTACK_CADDYFILE}" <<EOF
# Généré par MediaStack — aucun module proxy actif
${site_address} {
    respond "MediaStack proxy prêt" 200
}
EOF
        return 0
    fi

    for line in "${routes[@]}"; do
        IFS=$'\t' read -r module_name path target <<< "${line}"
        if proxy_is_root_path "${path}"; then
            default_target="${target}"
            default_module="${module_name}"
        else
            has_path_routes=true
        fi
    done

    {
        printf '# Généré automatiquement par MediaStack — ne pas éditer à la main\n'
        printf '%s {\n' "${site_address}"
        printf '    encode zstd gzip\n\n'
        printf '    header {\n'
        printf '        Strict-Transport-Security "max-age=31536000; includeSubDomains"\n'
        printf '        X-Content-Type-Options "nosniff"\n'
        printf '        X-Frame-Options "SAMEORIGIN"\n'
        printf '        Referrer-Policy "strict-origin-when-cross-origin"\n'
        printf '    }\n\n'

        if [[ "${has_path_routes}" == true ]]; then
            for line in "${routes[@]}"; do
                IFS=$'\t' read -r module_name path target <<< "${line}"
                if proxy_is_root_path "${path}"; then
                    continue
                fi
                printf '    handle %s {\n' "${path}"
                printf '        reverse_proxy %s\n' "${target}"
                printf '    }\n\n'
            done

            if [[ -n "${default_target}" ]]; then
                printf '    handle {\n'
                printf '        reverse_proxy %s\n' "${default_target}"
                printf '    }\n'
            fi
        else
            if [[ -z "${default_target}" ]]; then
                IFS=$'\t' read -r default_module _ default_target <<< "${routes[0]}"
            fi
            printf '    reverse_proxy %s\n' "${default_target}"
        fi

        printf '}\n'
    } > "${MEDIASTACK_CADDYFILE}"
}

proxy_reload_caddy() {
    if docker inspect caddy >/dev/null 2>&1 &&
        docker inspect --format '{{.State.Running}}' caddy 2>/dev/null | grep -qx true; then
        if docker exec caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
            media_success "Caddy rechargé."
        else
            media_warning "Impossible de recharger Caddy à chaud, redémarrage..."
            docker restart caddy >/dev/null
        fi
    fi
}

proxy_regenerate() {
    local domain="${1:-}"
    local tls_mode="${2:-}"

    if [[ -n "${tls_mode}" ]]; then
        tls_mode_set "${tls_mode}" || return 1
    fi

    if [[ -n "${domain}" ]]; then
        domain_set "${domain}"
    fi

    proxy_write_caddyfile "$(domain_get)" || return 1
    media_success "Caddyfile généré : ${MEDIASTACK_CADDYFILE} (tls=$(tls_mode_get))"
    proxy_reload_caddy
}

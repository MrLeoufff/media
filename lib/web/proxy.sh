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

domain_file_path() {
    printf '%s\n' "${MEDIASTACK_DOMAIN_FILE}"
}

domain_normalize() {
    local domain="${1:-}"

    domain="${domain#http://}"
    domain="${domain#https://}"
    domain="${domain%%/*}"

    printf '%s\n' "${domain}"
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

# Adresse de site Caddy.
# Domaine nu => HTTPS automatique (Let's Encrypt).
# Préfixe http(s):// conservé si fourni explicitement.
# Sans domaine => écoute LAN :80.
proxy_site_address() {
    local domain="${1:-}"

    [[ -n "${domain}" ]] || domain="$(domain_get)"

    if [[ -z "${domain}" ]]; then
        printf ':80\n'
        return
    fi

    if [[ "${domain}" == http://* || "${domain}" == https://* ]]; then
        printf '%s\n' "${domain}"
        return
    fi

    printf '%s\n' "$(domain_normalize "${domain}")"
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

proxy_collect_routes() {
    local module_name
    local target
    local path

    while IFS= read -r module_name; do
        [[ -n "${module_name}" ]] || continue

        if ! proxy_module_enabled "${module_name}"; then
            continue
        fi

        target="$(
            module_metadata_get_or_default \
                "${module_name}" \
                proxy.target \
                ""
        )"

        [[ -n "${target}" ]] || continue

        path="$(
            module_metadata_get_or_default \
                "${module_name}" \
                proxy.path \
                "/"
        )"

        printf '%s\t%s\t%s\n' "${module_name}" "${path}" "${target}"
    done < <(module_enabled_names)
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

    if [[ -n "${domain}" ]]; then
        domain_set "${domain}"
    fi

    proxy_write_caddyfile "$(domain_get)" || return 1
    media_success "Caddyfile généré : ${MEDIASTACK_CADDYFILE}"
    proxy_reload_caddy
}

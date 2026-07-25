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

domain_get() {
    local domain_file
    domain_file="$(domain_file_path)"

    if [[ -f "${domain_file}" ]]; then
        tr -d '[:space:]' < "${domain_file}"
    fi
}

domain_set() {
    local domain="$1"
    local domain_file

    domain_file="$(domain_file_path)"
    mkdir -p "$(dirname "${domain_file}")"
    printf '%s\n' "${domain}" > "${domain_file}"
}

proxy_site_address() {
    local domain="${1:-}"

    if [[ -z "${domain}" ]]; then
        domain="$(domain_get)"
    fi

    if [[ -n "${domain}" ]]; then
        if [[ "${domain}" == http://* || "${domain}" == https://* ]]; then
            printf '%s\n' "${domain}"
        else
            printf 'http://%s\n' "${domain}"
        fi
        return
    fi

    printf ':80\n'
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

proxy_write_caddyfile() {
    local domain="${1:-}"
    local site_address
    local routes=()
    local line
    local module_name
    local path
    local target
    local default_target=""
    local has_path_routes=false

    site_address="$(proxy_site_address "${domain}")"
    mkdir -p "${MEDIASTACK_CONFIG_DIR}"

    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        routes+=("${line}")
    done < <(proxy_collect_routes)

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
        if [[ "${path}" == "/" || "${path}" == "/*" || -z "${path}" ]]; then
            default_target="${target}"
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
                if [[ "${path}" == "/" || "${path}" == "/*" || -z "${path}" ]]; then
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
                IFS=$'\t' read -r _ _ default_target <<< "${routes[0]}"
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

    proxy_write_caddyfile "$(domain_get)"
    media_success "Caddyfile généré : ${MEDIASTACK_CADDYFILE}"
    proxy_reload_caddy
}

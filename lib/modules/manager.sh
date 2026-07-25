#!/usr/bin/env bash

# ==============================================================================
# MediaStack - Gestion des modules
# ==============================================================================

module_path() {
    local module_name="$1"

    printf '%s/%s\n' \
        "${MEDIASTACK_MODULES_DIR}" \
        "${module_name}"
}

module_exists() {
    local module_name="$1"

    [[ -d "$(module_path "${module_name}")" ]]
}

module_metadata_file() {
    local module_name="$1"

    printf '%s/module.yml\n' \
        "$(module_path "${module_name}")"
}

module_compose_file() {
    local module_name="$1"

    printf '%s/compose.yml\n' \
        "$(module_path "${module_name}")"
}

module_doctor_file() {
    local module_name="$1"

    printf '%s/doctor.sh\n' \
        "$(module_path "${module_name}")"
}

module_install_file() {
    local module_name="$1"

    printf '%s/install.sh\n' \
        "$(module_path "${module_name}")"
}

module_uninstall_file() {
    local module_name="$1"

    printf '%s/uninstall.sh\n' \
        "$(module_path "${module_name}")"
}

module_has_metadata() {
    local module_name="$1"

    [[ -f "$(module_metadata_file "${module_name}")" ]]
}

module_has_compose() {
    local module_name="$1"

    [[ -f "$(module_compose_file "${module_name}")" ]]
}

module_has_doctor() {
    local module_name="$1"

    [[ -f "$(module_doctor_file "${module_name}")" ]]
}

module_has_install() {
    local module_name="$1"

    [[ -x "$(module_install_file "${module_name}")" ]]
}

module_has_uninstall() {
    local module_name="$1"

    [[ -x "$(module_uninstall_file "${module_name}")" ]]
}

module_is_complete() {
    local module_name="$1"

    module_has_metadata "${module_name}" &&
        module_has_compose "${module_name}"
}

module_names() {
    local module_dir
    local module_name

    shopt -s nullglob

    for module_dir in "${MEDIASTACK_MODULES_DIR}"/*; do
        [[ -d "${module_dir}" ]] || continue

        module_name="$(basename "${module_dir}")"

        if module_is_complete "${module_name}"; then
            printf '%s\n' "${module_name}"
        fi
    done | sort

    shopt -u nullglob
}

module_enabled_path() {
    local module_name="$1"

    printf '%s/%s\n' \
        "${MEDIASTACK_ENABLED_DIR}" \
        "${module_name}"
}

module_is_enabled() {
    local module_name="$1"

    [[ -L "$(module_enabled_path "${module_name}")" ]] ||
        [[ -d "$(module_enabled_path "${module_name}")" ]]
}

module_enable() {
    local module_name="$1"
    local enabled_path

    if ! module_is_complete "${module_name}"; then
        printf 'Module incomplet ou introuvable : %s\n' "${module_name}" >&2
        return 1
    fi

    mkdir -p "${MEDIASTACK_ENABLED_DIR}"

    enabled_path="$(module_enabled_path "${module_name}")"

    if module_is_enabled "${module_name}"; then
        return 0
    fi

    ln -s "../modules/${module_name}" "${enabled_path}"
}

module_disable() {
    local module_name="$1"
    local enabled_path

    enabled_path="$(module_enabled_path "${module_name}")"

    if [[ -L "${enabled_path}" ]]; then
        rm "${enabled_path}"
        return
    fi

    if [[ -d "${enabled_path}" ]]; then
        printf 'Refus de supprimer un dossier réel : %s\n' "${enabled_path}" >&2
        return 1
    fi
}

module_enabled_names() {
    local enabled_entry
    local module_name

    shopt -s nullglob

    for enabled_entry in "${MEDIASTACK_ENABLED_DIR}"/*; do
        [[ -e "${enabled_entry}" || -L "${enabled_entry}" ]] || continue

        module_name="$(basename "${enabled_entry}")"

        if module_is_enabled "${module_name}" &&
            module_is_complete "${module_name}"; then
            printf '%s\n' "${module_name}"
        fi
    done | sort

    shopt -u nullglob
}

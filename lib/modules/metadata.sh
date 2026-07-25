#!/usr/bin/env bash

if ! declare -F module_metadata_file >/dev/null 2>&1; then
    source "${MEDIASTACK_HOME}/lib/modules/manager.sh"
fi

module_metadata_error() {
    echo "[ERREUR] $*" >&2
}

module_metadata_require() {
    local module_name="$1"
    local metadata_file

    if [[ -z "${module_name}" ]]; then
        module_metadata_error "Nom du module manquant."
        return 1
    fi

    if ! module_exists "${module_name}"; then
        module_metadata_error "Module inconnu : ${module_name}"
        return 1
    fi

    metadata_file="$(module_metadata_file "${module_name}")"

    if [[ ! -f "${metadata_file}" ]]; then
        module_metadata_error \
            "Manifeste absent pour le module ${module_name} : ${metadata_file}"
        return 1
    fi
}

module_metadata_get() {
    local module_name="$1"
    local requested_key="$2"
    local metadata_file

    module_metadata_require "${module_name}" || return 1

    if [[ -z "${requested_key}" ]]; then
        module_metadata_error "Clé de manifeste manquante."
        return 1
    fi

    metadata_file="$(module_metadata_file "${module_name}")"

    python3 - "${metadata_file}" "${requested_key}" <<'PY'
import re
import sys
from pathlib import Path

metadata_file = Path(sys.argv[1])
requested_key = sys.argv[2]

lines = metadata_file.read_text(encoding="utf-8").splitlines()
stack = []

for raw_line in lines:
    if not raw_line.strip():
        continue

    stripped = raw_line.lstrip()

    if stripped.startswith("#") or stripped.startswith("- "):
        continue

    indent = len(raw_line) - len(stripped)

    match = re.match(r"^([A-Za-z0-9_-]+)\s*:\s*(.*)$", stripped)
    if not match:
        continue

    key, value = match.groups()

    while stack and stack[-1][0] >= indent:
        stack.pop()

    full_key = ".".join([item[1] for item in stack] + [key])

    if value == "":
        stack.append((indent, key))
        continue

    if full_key != requested_key:
        continue

    value = value.strip()

    if (
        len(value) >= 2
        and value[0] == value[-1]
        and value[0] in {"'", '"'}
    ):
        value = value[1:-1]

    lowered = value.lower()

    if lowered == "null":
        value = ""
    elif lowered == "true":
        value = "true"
    elif lowered == "false":
        value = "false"

    print(value)
    sys.exit(0)

sys.exit(1)
PY
}

module_metadata_get_or_default() {
    local module_name="$1"
    local requested_key="$2"
    local default_value="${3:-}"
    local value

    if value="$(module_metadata_get \
        "${module_name}" \
        "${requested_key}" 2>/dev/null)"; then
        printf '%s\n' "${value}"
    else
        printf '%s\n' "${default_value}"
    fi
}

module_metadata_has() {
    local module_name="$1"
    local requested_key="$2"

    module_metadata_get \
        "${module_name}" \
        "${requested_key}" >/dev/null 2>&1
}

module_metadata_list() {
    local module_name="$1"
    local requested_key="$2"
    local metadata_file

    module_metadata_require "${module_name}" || return 1

    if [[ -z "${requested_key}" ]]; then
        module_metadata_error "Clé de liste manquante."
        return 1
    fi

    metadata_file="$(module_metadata_file "${module_name}")"

    python3 - "${metadata_file}" "${requested_key}" <<'PY'
import re
import sys
from pathlib import Path

metadata_file = Path(sys.argv[1])
requested_key = sys.argv[2]

lines = metadata_file.read_text(encoding="utf-8").splitlines()
stack = []
inside_requested_list = False
requested_indent = None
found = False

for raw_line in lines:
    if not raw_line.strip():
        continue

    stripped = raw_line.lstrip()

    if stripped.startswith("#"):
        continue

    indent = len(raw_line) - len(stripped)

    if inside_requested_list:
        if indent <= requested_indent:
            inside_requested_list = False
        elif stripped.startswith("- "):
            value = stripped[2:].strip()

            if (
                len(value) >= 2
                and value[0] == value[-1]
                and value[0] in {"'", '"'}
            ):
                value = value[1:-1]

            print(value)
            found = True
            continue

    match = re.match(r"^([A-Za-z0-9_-]+)\s*:\s*(.*)$", stripped)
    if not match:
        continue

    key, value = match.groups()

    while stack and stack[-1][0] >= indent:
        stack.pop()

    full_key = ".".join([item[1] for item in stack] + [key])

    if value == "":
        if full_key == requested_key:
            inside_requested_list = True
            requested_indent = indent

        stack.append((indent, key))

if not found:
    sys.exit(1)
PY
}

module_metadata_dump() {
    local module_name="$1"
    local metadata_file

    module_metadata_require "${module_name}" || return 1
    metadata_file="$(module_metadata_file "${module_name}")"

    cat "${metadata_file}"
}

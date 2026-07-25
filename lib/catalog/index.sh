#!/usr/bin/env bash

# ==============================================================================
# MediaStack - Catalogue de modules (index local + cache distant)
# ==============================================================================

catalog_error() {
    echo "[ERREUR] $*" >&2
}

catalog_info() {
    echo "[INFO] $*"
}

catalog_bundled_index() {
    printf '%s\n' "${MEDIASTACK_CATALOG_INDEX}"
}

catalog_cache_index() {
    printf '%s\n' "${MEDIASTACK_CATALOG_CACHE}"
}

# Fichier d'index effectif : cache distant si présent, sinon index bundlé.
catalog_active_index() {
    local cache
    local bundled

    cache="$(catalog_cache_index)"
    bundled="$(catalog_bundled_index)"

    if [[ -f "${cache}" ]]; then
        printf '%s\n' "${cache}"
        return 0
    fi

    if [[ -f "${bundled}" ]]; then
        printf '%s\n' "${bundled}"
        return 0
    fi

    catalog_error "Aucun index catalogue trouvé (${bundled})."
    return 1
}

# Valide un id de module catalogue.
catalog_valid_name() {
    local name="${1:-}"

    [[ "${name}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
}

# Liste les entrées : name|displayName|version|category|description|source
catalog_entries_query() {
    local query="${1:-}"
    local index_file
    local modules_dir="${MEDIASTACK_MODULES_DIR}"

    index_file="$(catalog_active_index)" || return 1

    python3 - "${index_file}" "${query}" "${modules_dir}" <<'PY'
import re
import sys
from pathlib import Path

index_file = Path(sys.argv[1])
query = (sys.argv[2] or "").strip().lower()
modules_path = Path(sys.argv[3]) if len(sys.argv) > 3 else Path()

text = index_file.read_text(encoding="utf-8")
entries = []
current = None

for raw in text.splitlines():
    if re.match(r"^\s*-\s+name:\s*", raw):
        if current and current.get("name"):
            entries.append(current)
        current = {
            "name": re.sub(r"^\s*-\s+name:\s*", "", raw).strip().strip('"').strip("'"),
            "displayName": "",
            "version": "",
            "category": "",
            "description": "",
            "source": "local",
        }
        continue
    if current is None:
        continue
    m = re.match(r"^\s+(displayName|version|category|description|source):\s*(.*)$", raw)
    if not m:
        continue
    key, value = m.groups()
    current[key] = value.strip().strip('"').strip("'")

if current and current.get("name"):
    entries.append(current)

if modules_path.is_dir():
    known = {e["name"] for e in entries}
    for module_yml in sorted(modules_path.glob("*/module.yml")):
        name = module_yml.parent.name
        if name in known:
            continue
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", name):
            continue
        meta = {}
        for line in module_yml.read_text(encoding="utf-8").splitlines():
            if line.startswith(" ") or not line.strip() or line.lstrip().startswith("#"):
                continue
            mm = re.match(r"^([A-Za-z0-9_-]+)\s*:\s*(.*)$", line.strip())
            if mm:
                meta[mm.group(1)] = mm.group(2).strip().strip('"').strip("'")
        entries.append(
            {
                "name": name,
                "displayName": meta.get("displayName", name),
                "version": meta.get("version", "-"),
                "category": meta.get("category", "-"),
                "description": meta.get("description", ""),
                "source": "local",
            }
        )

for entry in entries:
    blob = " ".join(
        [
            entry.get("name", ""),
            entry.get("displayName", ""),
            entry.get("category", ""),
            entry.get("description", ""),
        ]
    ).lower()
    if query and query not in blob:
        continue
    print(
        "|".join(
            [
                entry.get("name", ""),
                entry.get("displayName", ""),
                entry.get("version", ""),
                entry.get("category", ""),
                entry.get("description", "").replace("|", "/"),
                entry.get("source", "local"),
            ]
        )
    )
PY
}

# Compat : sans filtre
catalog_entries() {
    catalog_entries_query ""
}

catalog_refresh() {
    local url="${1:-${MEDIASTACK_CATALOG_URL}}"
    local cache
    local tmp

    require_command curl
    cache="$(catalog_cache_index)"
    mkdir -p "$(dirname "${cache}")"
    tmp="$(mktemp)"

    catalog_info "Téléchargement du catalogue : ${url}"
    if ! curl -fsSL --max-time 30 "${url}" -o "${tmp}"; then
        rm -f "${tmp}"
        catalog_error "Échec du téléchargement du catalogue."
        return 1
    fi

    if ! grep -q 'apiVersion: mediastack/catalog' "${tmp}"; then
        rm -f "${tmp}"
        catalog_error "Index distant invalide (apiVersion manquant)."
        return 1
    fi

    mv "${tmp}" "${cache}"
    catalog_info "Catalogue mis en cache : ${cache}"
}

# Télécharge un module distant (source git HTTPS GitHub) vers modules/<name>.
catalog_ensure_module() {
    local requested="${1:-}"
    local name
    local source
    local line
    local tmp
    local dest

    [[ -n "${requested}" ]] || return 1

    # Déjà local (après resolve éventuel)
    if declare -F module_resolve_name >/dev/null 2>&1; then
        if name="$(module_resolve_name "${requested}" 2>/dev/null)"; then
            printf '%s\n' "${name}"
            return 0
        fi
    elif [[ -d "${MEDIASTACK_MODULES_DIR}/${requested}" ]]; then
        printf '%s\n' "${requested}"
        return 0
    fi

    line="$(
        catalog_entries_query "${requested}" | while IFS='|' read -r n dn ver cat desc src; do
            if [[ "$(printf '%s' "${n}" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "${requested}" | tr '[:upper:]' '[:lower:]')" ]] ||
                [[ "$(printf '%s' "${dn}" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "${requested}" | tr '[:upper:]' '[:lower:]')" ]]; then
                printf '%s|%s\n' "${n}" "${src}"
                break
            fi
        done
    )"

    [[ -n "${line}" ]] || return 1
    name="${line%%|*}"
    source="${line#*|}"

    catalog_valid_name "${name}" || {
        catalog_error "Nom de module invalide : ${name}"
        return 1
    }

    if [[ -d "${MEDIASTACK_MODULES_DIR}/${name}" ]]; then
        printf '%s\n' "${name}"
        return 0
    fi

    if [[ "${source}" == "local" || -z "${source}" ]]; then
        catalog_error "Module ${name} référencé localement mais absent de modules/."
        return 1
    fi

    if [[ ! "${source}" =~ ^https://github\.com/ ]]; then
        catalog_error "Source distante non autorisée (GitHub HTTPS uniquement) : ${source}"
        return 1
    fi

    require_command git
    tmp="$(mktemp -d /tmp/mediastack-catalog.XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" RETURN

    catalog_info "Récupération du module ${name} depuis ${source}"
    git clone --depth 1 "${source}" "${tmp}/repo" >/dev/null 2>&1 || {
        catalog_error "Clone impossible : ${source}"
        return 1
    }

    if [[ ! -f "${tmp}/repo/module.yml" || ! -f "${tmp}/repo/compose.yml" ]]; then
        # mono-repo : modules/<name>/
        if [[ -f "${tmp}/repo/modules/${name}/module.yml" && -f "${tmp}/repo/modules/${name}/compose.yml" ]]; then
            dest="${MEDIASTACK_MODULES_DIR}/${name}"
            mkdir -p "${MEDIASTACK_MODULES_DIR}"
            cp -a "${tmp}/repo/modules/${name}" "${dest}"
            printf '%s\n' "${name}"
            return 0
        fi
        catalog_error "module.yml / compose.yml introuvables pour ${name}."
        return 1
    fi

    dest="${MEDIASTACK_MODULES_DIR}/${name}"
    mkdir -p "${MEDIASTACK_MODULES_DIR}"
    cp -a "${tmp}/repo" "${dest}"
    printf '%s\n' "${name}"
}

#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "${TMP_HOME}"' EXIT

mkdir -p "${TMP_HOME}/conf" "${TMP_HOME}/enabled" "${TMP_HOME}/backup"
cp -a "${ROOT_DIR}/modules" "${TMP_HOME}/"

export MEDIASTACK_HOME="${TMP_HOME}"
export MEDIASTACK_DATA="${TMP_HOME}/data"
export MEDIASTACK_VERSION="2.1.0-test"

# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/core/constants.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/core/output.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/modules/manager.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/modules/metadata.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/web/proxy.sh"

failures=0

assert_eq() {
    local label="$1"
    local expected="$2"
    local actual="$3"

    if [[ "${expected}" == "${actual}" ]]; then
        echo "[OK] ${label}"
    else
        echo "[FAIL] ${label}"
        echo "  attendu : ${expected}"
        echo "  obtenu  : ${actual}"
        failures=$((failures + 1))
    fi
}

assert_true() {
    local label="$1"
    shift
    if "$@"; then
        echo "[OK] ${label}"
    else
        echo "[FAIL] ${label}"
        failures=$((failures + 1))
    fi
}

echo "=== Smoke MediaStack ==="

assert_true "module jellyfin complet" module_is_complete jellyfin
assert_true "module caddy complet" module_is_complete caddy

deps="$(module_metadata_list jellyfin dependencies | paste -sd ',' -)"
assert_eq "dépendances jellyfin" "caddy" "${deps}"

proxy_enabled="$(module_metadata_get jellyfin proxy.enabled)"
assert_eq "proxy jellyfin activé" "true" "${proxy_enabled}"

proxy_target="$(module_metadata_get jellyfin proxy.target)"
assert_eq "proxy jellyfin target" "jellyfin:8096" "${proxy_target}"

install_feature="$(module_metadata_get jellyfin features.install)"
assert_eq "features.install jellyfin" "true" "${install_feature}"

ln -sfn "../modules/jellyfin" "${MEDIASTACK_ENABLED_DIR}/jellyfin"
ln -sfn "../modules/caddy" "${MEDIASTACK_ENABLED_DIR}/caddy"

domain_set "media.example.test"
proxy_write_caddyfile "media.example.test"

assert_true "Caddyfile généré" test -f "${MEDIASTACK_CADDYFILE}"
assert_true "Caddyfile contient le domaine" \
    grep -q 'http://media.example.test' "${MEDIASTACK_CADDYFILE}"
assert_true "Caddyfile contient jellyfin" \
    grep -q 'reverse_proxy jellyfin:8096' "${MEDIASTACK_CADDYFILE}"
assert_true "Caddyfile marque généré" \
    grep -q 'Généré automatiquement par MediaStack' "${MEDIASTACK_CADDYFILE}"

echo
if (( failures > 0 )); then
    echo "[FAIL] ${failures} test(s) en échec."
    exit 1
fi

echo "[OK] Tous les smoke tests sont passés."

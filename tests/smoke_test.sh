#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "${TMP_HOME}"' EXIT

mkdir -p "${TMP_HOME}/conf" "${TMP_HOME}/enabled" "${TMP_HOME}/backup"
cp -a "${ROOT_DIR}/modules" "${TMP_HOME}/"
ln -sfn "${ROOT_DIR}/lib" "${TMP_HOME}/lib"

export MEDIASTACK_HOME="${TMP_HOME}"
export MEDIASTACK_DATA="${TMP_HOME}/data"
export MEDIASTACK_VERSION="2.1.0-test"

# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/core/constants.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/core/output.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/core/common.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/modules/manager.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/modules/metadata.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/web/proxy.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/modules/lifecycle.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/modules/commands.sh"

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

assert_false() {
    local label="$1"
    shift
    if "$@"; then
        echo "[FAIL] ${label} (devait échouer)"
        failures=$((failures + 1))
    else
        echo "[OK] ${label}"
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

# --- Adresse site / modes TLS ---
# Défaut : tls=off (HTTP backend derrière reverse-proxy amont, ex. m710q)
assert_eq "tls off par défaut" "off" "$(tls_mode_get)"

# Sans TTY, le prompt conserve le mode courant (pas de blocage install)
assert_eq "tls_mode_prompt non interactif" \
    "off" \
    "$(tls_mode_prompt </dev/null)"

assert_eq "tls off => http://domaine" \
    "http://media.example.test" \
    "$(proxy_site_address "media.example.test")"

tls_mode_set auto
assert_eq "tls auto => domaine nu (HTTPS Caddy)" \
    "media.example.test" \
    "$(proxy_site_address "media.example.test")"

tls_mode_set off
assert_eq "domaine http explicite conservé" \
    "http://media.example.test" \
    "$(proxy_site_address "http://media.example.test")"

rm -f "$(tls_mode_file_path)" "$(domain_file_path)"
assert_eq "sans domaine => :80" \
    ":80" \
    "$(proxy_site_address "")"

domain_set "https://media.example.test"
assert_eq "domain_set normalise le schéma" \
    "media.example.test" \
    "$(domain_get)"

ln -sfn "../modules/jellyfin" "${MEDIASTACK_ENABLED_DIR}/jellyfin"
ln -sfn "../modules/caddy" "${MEDIASTACK_ENABLED_DIR}/caddy"

tls_mode_set off
domain_set "media.example.test"
proxy_write_caddyfile "media.example.test"

assert_true "Caddyfile généré" test -f "${MEDIASTACK_CADDYFILE}"
assert_true "Caddyfile HTTP backend (tls=off)" \
    grep -qE '^http://media\.example\.test \{' "${MEDIASTACK_CADDYFILE}"
assert_true "Caddyfile contient jellyfin" \
    grep -q 'reverse_proxy jellyfin:8096' "${MEDIASTACK_CADDYFILE}"
assert_true "Caddyfile marque généré" \
    grep -q 'Généré automatiquement par MediaStack' "${MEDIASTACK_CADDYFILE}"

tls_mode_set auto
proxy_write_caddyfile "media.example.test"
assert_true "Caddyfile HTTPS auto (tls=auto)" \
    grep -qE '^media\.example\.test \{' "${MEDIASTACK_CADDYFILE}"
assert_false "Caddyfile tls=auto sans http://" \
    grep -q 'http://media.example.test' "${MEDIASTACK_CADDYFILE}"

tls_mode_set off
proxy_write_caddyfile "media.example.test"

# --- Conflit de routes path=/ ---
mkdir -p "${MEDIASTACK_MODULES_DIR}/fakeroot"
cat > "${MEDIASTACK_MODULES_DIR}/fakeroot/module.yml" <<'EOF'
apiVersion: mediastack/v1
name: fakeroot
displayName: FakeRoot
version: "0.0.1"
description: Module de test conflit proxy
category: test
container:
  name: fakeroot
  image: fake:latest
network:
  name: mediastack_proxy
dependencies: []
storage: []
proxy:
  enabled: true
  target: fakeroot:8080
  path: /
features:
  doctor: false
  install: true
  uninstall: true
EOF
printf 'services: {}\n' > "${MEDIASTACK_MODULES_DIR}/fakeroot/compose.yml"
ln -sfn "../modules/fakeroot" "${MEDIASTACK_ENABLED_DIR}/fakeroot"

assert_false "refus de plusieurs routes proxy sur /" \
    proxy_write_caddyfile "media.example.test"

rm -f "${MEDIASTACK_ENABLED_DIR}/fakeroot"
rm -rf "${MEDIASTACK_MODULES_DIR}/fakeroot"

# Restaurer un Caddyfile valide après le conflit
proxy_write_caddyfile "media.example.test"

# --- Dépendants / blocage uninstall ---
dependents="$(module_dependents caddy | paste -sd ',' -)"
assert_eq "caddy requis par jellyfin" "jellyfin" "${dependents}"

jellyfin_deps="$(module_dependents jellyfin)"
assert_eq "jellyfin n'a pas de dépendants" "" "${jellyfin_deps}"

# --- Options CLI invalides ---
assert_false "install refuse option inconnue" \
    module_command_install jellyfin --bad-flag
assert_false "uninstall refuse option inconnue" \
    module_command_uninstall jellyfin --explode
assert_false "install sans nom de module" \
    module_command_install

# --- Parsing domain install (sans exécuter docker) ---
# Vérifie seulement que --domain= est accepté jusqu'à require_root
if [[ "${EUID}" -ne 0 ]]; then
    assert_false "install exige root hors root" \
        module_command_install jellyfin --domain=media.example.test
fi

echo
if (( failures > 0 )); then
    echo "[FAIL] ${failures} test(s) en échec."
    exit 1
fi

echo "[OK] Tous les smoke tests sont passés."

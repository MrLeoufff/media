#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_HOME="$(mktemp -d)"
TEST_LOG="${TMP_HOME}/docker.log"
trap 'rm -rf "${TMP_HOME}"' EXIT

mkdir -p "${TMP_HOME}/conf" "${TMP_HOME}/enabled" "${TMP_HOME}/backup" "${TMP_HOME}/data"
cp -a "${ROOT_DIR}/modules" "${TMP_HOME}/"
ln -sfn "${ROOT_DIR}/lib" "${TMP_HOME}/lib"

export MEDIASTACK_HOME="${TMP_HOME}"
export MEDIASTACK_DATA="${TMP_HOME}/data"
export MEDIASTACK_VERSION="2.2.0-test"
: > "${TEST_LOG}"

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
source "${ROOT_DIR}/lib/services/manager.sh"
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/modules/lifecycle.sh"

failures=0
DOCTOR_SHOULD_FAIL=0

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

# --- Mocks Docker / root / reload ---
require_root() { return 0; }
require_command() { return 0; }
confirm_action() { return 0; }
proxy_reload_caddy() { return 0; }

docker() {
    printf 'docker %s\n' "$*" >> "${TEST_LOG}"

    case "${1:-}" in
        network)
            case "${2:-}" in
                inspect) return 0 ;;
                create) return 0 ;;
            esac
            ;;
        inspect)
            # Conteneur "présent" et running pour les deps
            if [[ "${2:-}" == "--format" ]]; then
                printf 'true\n'
                return 0
            fi
            return 0
            ;;
        compose)
            return 0
            ;;
        exec|restart|rm)
            return 0
            ;;
    esac

    return 0
}

service_is_running() { return 0; }
service_start() {
    printf 'service_start %s\n' "$1" >> "${TEST_LOG}"
    return 0
}
service_remove() {
    printf 'service_remove %s\n' "$1" >> "${TEST_LOG}"
    return 0
}

# Ne jamais créer/supprimer les vrais chemins /opt/media du module.yml en mock.
module_ensure_storage() {
    printf 'ensure_storage %s\n' "$1" >> "${TEST_LOG}"
    return 0
}

module_lifecycle_run_doctor() {
    printf 'doctor %s\n' "$1" >> "${TEST_LOG}"
    if (( DOCTOR_SHOULD_FAIL )); then
        return 1
    fi
    return 0
}

echo "=== Lifecycle mock MediaStack ==="

# Install caddy puis jellyfin (deps + enable + compose mock)
assert_true "install caddy mock" \
    module_install caddy "media.example.test" "off"
assert_true "caddy activé" module_is_enabled caddy

assert_true "install jellyfin mock" \
    module_install jellyfin "media.example.test" "off"
assert_true "jellyfin activé" module_is_enabled jellyfin
assert_true "Caddyfile HTTP généré" \
    grep -q 'http://media.example.test' "${MEDIASTACK_CADDYFILE}"
assert_true "service_start jellyfin appelé" \
    grep -q 'service_start jellyfin' "${TEST_LOG}"

# Conflit proxy : second module sur / ne doit PAS rester activé
mkdir -p "${MEDIASTACK_MODULES_DIR}/fakeroot"
cat > "${MEDIASTACK_MODULES_DIR}/fakeroot/module.yml" <<'EOF'
apiVersion: mediastack/v1
name: fakeroot
displayName: FakeRoot
version: "0.0.1"
description: Conflit proxy
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

assert_false "install fakeroot refusé (conflit /)" \
    module_install fakeroot "media.example.test" "off"
assert_false "fakeroot non activé après conflit" \
    module_is_enabled fakeroot

# Échec doctor : module reste installé
DOCTOR_SHOULD_FAIL=1
# Forcer un "réinstall" homepage (pas de proxy root)
assert_false "install homepage avec doctor en échec" \
    module_install homepage "media.example.test" "off"
assert_true "homepage reste activé après échec doctor" \
    module_is_enabled homepage
DOCTOR_SHOULD_FAIL=0

# Uninstall bloqué par dépendance
assert_false "uninstall caddy bloqué (dépendants)" \
    module_uninstall caddy --keep-data --yes

# Uninstall homepage keep-data
assert_true "uninstall homepage keep-data" \
    module_uninstall homepage --keep-data --yes
assert_false "homepage désactivé" module_is_enabled homepage
assert_true "service_remove homepage appelé" \
    grep -q 'service_remove homepage' "${TEST_LOG}"

# Uninstall jellyfin keep-data (pas de --purge sur chemins /opt/media réels)
assert_true "uninstall jellyfin keep-data" \
    module_uninstall jellyfin --keep-data --yes
assert_false "jellyfin désactivé" module_is_enabled jellyfin

# Purge sur module de test avec storage sous TMP uniquement
mkdir -p "${MEDIASTACK_MODULES_DIR}/purgeable"
cat > "${MEDIASTACK_MODULES_DIR}/purgeable/module.yml" <<EOF
apiVersion: mediastack/v1
name: purgeable
displayName: Purgeable
version: "0.0.1"
description: Test purge
category: test
container:
  name: purgeable
  image: fake:latest
network:
  name: mediastack_proxy
dependencies: []
storage:
  - ${MEDIASTACK_DATA}/purgeable-data
proxy:
  enabled: false
features:
  doctor: false
  install: true
  uninstall: true
EOF
printf 'services: {}\n' > "${MEDIASTACK_MODULES_DIR}/purgeable/compose.yml"
mkdir -p "${MEDIASTACK_DATA}/purgeable-data"
echo keep > "${MEDIASTACK_DATA}/purgeable-data/file.txt"

# Restaurer ensure_storage réel pour ce module TMP
unset -f module_ensure_storage
# shellcheck source=/dev/null
source "${ROOT_DIR}/lib/modules/lifecycle.sh"

assert_true "install purgeable" \
    module_install purgeable "media.example.test" "off"
assert_true "uninstall purgeable --purge" \
    module_uninstall purgeable --purge --yes
assert_false "données purgeable supprimées" \
    test -e "${MEDIASTACK_DATA}/purgeable-data"

echo
if (( failures > 0 )); then
    echo "[FAIL] ${failures} test(s) lifecycle mock en échec."
    echo "--- docker log ---"
    cat "${TEST_LOG}" || true
    exit 1
fi

echo "[OK] Tous les tests lifecycle mock sont passés."

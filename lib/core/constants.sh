#!/usr/bin/env bash

# ==============================================================================
# MediaStack - Constantes globales
# ==============================================================================

# Valeurs par défaut.
# L'opérateur := n'effectue aucune réaffectation si la variable existe déjà.
: "${MEDIASTACK_HOME:=/opt/mediastack}"
: "${MEDIASTACK_DATA:=/opt/media}"

readonly MEDIASTACK_HOME
readonly MEDIASTACK_DATA

# Répertoires du projet
readonly MEDIASTACK_COMPOSE_DIR="${MEDIASTACK_HOME}/compose"
readonly MEDIASTACK_CONFIG_DIR="${MEDIASTACK_HOME}/conf"
readonly MEDIASTACK_MODULES_DIR="${MEDIASTACK_HOME}/modules"
readonly MEDIASTACK_ENABLED_DIR="${MEDIASTACK_HOME}/enabled"
readonly MEDIASTACK_BACKUP_DIR="${MEDIASTACK_HOME}/backup"
readonly MEDIASTACK_RESTORE_DIR="${MEDIASTACK_HOME}/restore"
readonly MEDIASTACK_CATALOG_DIR="${MEDIASTACK_HOME}/catalog"
readonly MEDIASTACK_CATALOG_INDEX="${MEDIASTACK_CATALOG_DIR}/index.yml"
readonly MEDIASTACK_CATALOG_CACHE="${MEDIASTACK_CONFIG_DIR}/catalog-cache.yml"
: "${MEDIASTACK_CATALOG_URL:=https://raw.githubusercontent.com/MrLeoufff/media/main/catalog/index.yml}"

# Configuration générale
readonly MEDIASTACK_CADDYFILE="${MEDIASTACK_CONFIG_DIR}/Caddyfile"
readonly MEDIASTACK_DOMAIN_FILE="${MEDIASTACK_CONFIG_DIR}/domain"
# off  = HTTP backend (TLS terminé en amont, ex. m710q)
# auto = HTTPS automatique Caddy (MediaStack est le reverse-proxy public)
readonly MEDIASTACK_TLS_MODE_FILE="${MEDIASTACK_CONFIG_DIR}/tls-mode"
: "${MEDIASTACK_TLS_MODE:=}"

# Bibliothèques multimédias
readonly FILMS_DIR="${MEDIASTACK_DATA}/films"
readonly SERIES_DIR="${MEDIASTACK_DATA}/series"
readonly MUSIC_DIR="${MEDIASTACK_DATA}/musique"
readonly ANIMES_DIR="${MEDIASTACK_DATA}/animes"
readonly CONCERTS_DIR="${MEDIASTACK_DATA}/concerts"
readonly DOCUMENTARIES_DIR="${MEDIASTACK_DATA}/documentaires"

# Données applicatives
readonly JELLYFIN_DIR="${MEDIASTACK_DATA}/jellyfin"
readonly PORTAINER_DIR="${MEDIASTACK_DATA}/portainer"
readonly CADDY_DIR="${MEDIASTACK_DATA}/caddy"
readonly HOMEPAGE_DIR="${MEDIASTACK_DATA}/homepage"

# ==============================================================================
# Alias temporaires de compatibilité
# ==============================================================================

readonly STACK_DIR="${MEDIASTACK_HOME}"
readonly DATA_DIR="${MEDIASTACK_DATA}"
readonly MEDIA_DIR="${MEDIASTACK_DATA}"

readonly COMPOSE_DIR="${MEDIASTACK_COMPOSE_DIR}"
readonly CONFIG_DIR="${MEDIASTACK_CONFIG_DIR}"
readonly BACKUP_DIR="${MEDIASTACK_BACKUP_DIR}"
readonly RESTORE_DIR="${MEDIASTACK_RESTORE_DIR}"
readonly CADDYFILE="${MEDIASTACK_CADDYFILE}"

readonly HOMEPAGE_COMPOSE_FILE="${MEDIASTACK_COMPOSE_DIR}/homepage.yml"

#!/usr/bin/env bash

readonly STACK_DIR="${MEDIASTACK_HOME:-/opt/mediastack}"
readonly COMPOSE_FILE="${STACK_DIR}/docker-compose.yml"
readonly HOMEPAGE_COMPOSE_FILE="${STACK_DIR}/docker-compose.homepage.yml"

readonly DATA_DIR="/opt/media"
readonly MEDIA_DIR="${DATA_DIR}/media"
readonly FILMS_DIR="${MEDIA_DIR}/films"
readonly SERIES_DIR="${MEDIA_DIR}/series"
readonly MUSIC_DIR="${MEDIA_DIR}/musique"

readonly JELLYFIN_DIR="${DATA_DIR}/jellyfin"
readonly PORTAINER_DIR="${DATA_DIR}/portainer"
readonly CADDY_DIR="${DATA_DIR}/caddy"
readonly HOMEPAGE_DIR="${DATA_DIR}/homepage"

readonly BACKUP_DIR="${STACK_DIR}/backup"
readonly RESTORE_DIR="${STACK_DIR}/restore"
readonly CONFIG_DIR="${STACK_DIR}/config"
readonly CADDYFILE="${CONFIG_DIR}/Caddyfile"

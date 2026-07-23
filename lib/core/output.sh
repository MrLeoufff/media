#!/usr/bin/env bash

readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_RESET='\033[0m'

media_info()    { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"; }
media_success() { echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"; }
media_warning() { echo -e "${COLOR_YELLOW}[ATTENTION]${COLOR_RESET} $*"; }
media_error()   { echo -e "${COLOR_RED}[ERREUR]${COLOR_RESET} $*" >&2; }
media_die()     { media_error "$*"; exit 1; }

media_separator() {
    printf '%*s\n' 60 '' | tr ' ' '-'
}

media_header() {
    echo
    media_separator
    printf "                     MediaStack %s\n" "${MEDIASTACK_VERSION}"
    media_separator
    echo
}

#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_VERSION="1.6.0"
readonly SCRIPT_NAME="MediaStack"

readonly STACK_DIR="/opt/mediastack"
readonly COMPOSE_FILE="${STACK_DIR}/docker-compose.yml"
readonly HOMEPAGE_COMPOSE_FILE="${STACK_DIR}/docker-compose.homepage.yml"

readonly DATA_DIR="/opt/media"
readonly BACKUP_DIR="${STACK_DIR}/backup"
readonly RESTORE_DIR="${STACK_DIR}/restore"

readonly MEDIA_DIR="${DATA_DIR}/media"
readonly FILMS_DIR="${MEDIA_DIR}/films"
readonly SERIES_DIR="${MEDIA_DIR}/series"
readonly MUSIC_DIR="${MEDIA_DIR}/musique"

readonly JELLYFIN_DIR="${DATA_DIR}/jellyfin"
readonly PORTAINER_DIR="${DATA_DIR}/portainer"
readonly CADDY_DIR="${DATA_DIR}/caddy"
readonly HOMEPAGE_DIR="${DATA_DIR}/homepage"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[ATTENTION]${NC} $*"
}

error() {
    echo -e "${RED}[ERREUR]${NC} $*" >&2
}

die() {
    error "$*"
    exit 1
}

separator() {
    printf '%*s\n' 50 '' | tr ' ' '-'
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Cette commande doit être exécutée avec sudo ou en tant que root."
    fi
}

require_commands() {
    local command_name

    for command_name in \
        docker df free awk grep date tar find sort stat sed hostname \
        systemctl du cut tr head basename dirname readlink
    do
        command -v "$command_name" >/dev/null 2>&1 \
            || die "Commande manquante : ${command_name}"
    done

    docker compose version >/dev/null 2>&1 \
        || die "Docker Compose n'est pas disponible."
}

check_stack() {
    [[ -d "$STACK_DIR" ]] || die "Dossier introuvable : ${STACK_DIR}"
    [[ -f "$COMPOSE_FILE" ]] || die "Fichier introuvable : ${COMPOSE_FILE}"
}

compose() {
    local compose_arguments=(
        --project-directory "$STACK_DIR"
        --file "$COMPOSE_FILE"
    )

    if [[ -f "$HOMEPAGE_COMPOSE_FILE" ]]; then
        compose_arguments+=(--file "$HOMEPAGE_COMPOSE_FILE")
    fi

    docker compose "${compose_arguments[@]}" "$@"
}

show_header() {
    echo
    separator
    printf "                 %s %s\n" "$SCRIPT_NAME" "$SCRIPT_VERSION"
    separator
    echo
}

get_primary_ip() {
    hostname -I 2>/dev/null | awk '{print $1}'
}

confirm_action() {
    local message="$1"
    local answer

    read -r -p "${message} [o/N] " answer

    case "$answer" in
        o|O|oui|OUI|y|Y|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

start_stack() {
    require_root
    info "Démarrage de MediaStack..."
    compose up -d
    success "MediaStack démarrée."
    compose ps
}

stop_stack() {
    require_root
    warning "Arrêt de MediaStack..."
    compose down
    success "MediaStack arrêtée."
}

restart_stack() {
    require_root
    info "Redémarrage de MediaStack..."
    compose down
    compose up -d
    success "MediaStack redémarrée."
    compose ps
}

show_status() {
    show_header

    echo "Conteneurs"
    separator
    compose ps
    echo

    echo "Système"
    separator
    printf "Nom              %s\n" "$(hostname)"
    printf "Adresse IP       %s\n" "$(get_primary_ip)"
    printf "Charge           %s\n" "$(cut -d ' ' -f 1-3 /proc/loadavg)"
    printf "Mémoire          %s\n" "$(free -h | awk '/^Mem:/ {print $3 " utilisée / " $2}')"
    printf "Disque racine    %s\n" "$(df -h / | awk 'NR == 2 {print $3 " utilisée / " $2 " (" $5 ")"}')"
    printf "Disponibilité    %s\n" "$(uptime -p 2>/dev/null || uptime)"

    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        printf "Température CPU  %s\n" \
            "$(awk '{printf "%.1f°C", $1 / 1000}' /sys/class/thermal/thermal_zone0/temp)"
    fi

    echo
    echo "Services"
    separator
    print_service_states
}

print_service_states() {
    local service

    while IFS= read -r service; do
        if compose ps --status running --services | grep -Fxq "$service"; then
            printf "${GREEN}✔${NC} %-18s actif\n" "$service"
        else
            printf "${RED}✘${NC} %-18s inactif\n" "$service"
        fi
    done < <(compose config --services)

    if systemctl is-active --quiet smbd; then
        printf "${GREEN}✔${NC} %-18s actif\n" "samba"
    else
        printf "${RED}✘${NC} %-18s inactif\n" "samba"
    fi
}

show_logs() {
    local service="${1:-}"

    if [[ -z "$service" ]]; then
        compose logs --tail 100 -f
        return
    fi

    if ! compose config --services | grep -Fxq "$service"; then
        die "Service inconnu : ${service}"
    fi

    compose logs --tail 100 -f "$service"
}

update_stack() {
    require_root

    info "Téléchargement des nouvelles images..."
    compose pull

    info "Recréation des conteneurs..."
    compose up -d --remove-orphans

    success "MediaStack mise à jour."
    compose ps
}

health_check() {
    local failed=0
    local service
    local state
    local disk_usage

    show_header

    if docker info >/dev/null 2>&1; then
        success "Docker fonctionne."
    else
        error "Docker ne répond pas."
        failed=1
    fi

    if compose config --quiet; then
        success "La configuration Docker Compose est valide."
    else
        error "La configuration Docker Compose est invalide."
        failed=1
    fi

    while IFS= read -r service; do
        state="$(compose ps --status running --services | grep -Fx "$service" || true)"

        if [[ "$state" == "$service" ]]; then
            success "Conteneur actif : ${service}"
        else
            error "Conteneur inactif : ${service}"
            failed=1
        fi
    done < <(compose config --services)

    if systemctl is-active --quiet smbd; then
        success "Samba fonctionne."
    else
        error "Samba ne fonctionne pas."
        failed=1
    fi

    if [[ -r /dev/dri/renderD128 ]]; then
        success "Le périphérique vidéo /dev/dri/renderD128 est disponible."
    else
        warning "Le périphérique /dev/dri/renderD128 n'est pas accessible depuis l'hôte."
    fi

    disk_usage="$(df --output=pcent / | tail -1 | tr -dc '0-9')"

    if (( disk_usage >= 90 )); then
        error "Disque presque plein : ${disk_usage}%."
        failed=1
    elif (( disk_usage >= 80 )); then
        warning "Utilisation du disque élevée : ${disk_usage}%."
    else
        success "Espace disque correct : ${disk_usage}% utilisé."
    fi

    if (( failed != 0 )); then
        die "Un ou plusieurs contrôles ont échoué."
    fi

    success "Tous les contrôles essentiels sont valides."
}

create_backup() {
    require_root

    local timestamp
    local destination

    timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
    destination="${BACKUP_DIR}/mediastack_${timestamp}.tar.gz"

    mkdir -p "$BACKUP_DIR"

    info "Création de la sauvegarde..."
    warning "Les films, séries et musiques ne seront pas sauvegardés."

    tar \
        --exclude="${BACKUP_DIR}" \
        --exclude="${RESTORE_DIR}" \
        --exclude="${MEDIA_DIR}" \
        --exclude="${JELLYFIN_DIR}/cache" \
        --exclude="${JELLYFIN_DIR}/config/log" \
        --exclude="${JELLYFIN_DIR}/config/logs" \
        -czf "$destination" \
        "$STACK_DIR" \
        "${JELLYFIN_DIR}/config" \
        "$PORTAINER_DIR" \
        "$CADDY_DIR" \
        "$HOMEPAGE_DIR" \
        /etc/samba/smb.conf

    success "Sauvegarde créée : ${destination}"
    ls -lh "$destination"
}

list_backups() {
    local backups
    local index=1
    local timestamp
    local filename
    local size
    local readable_size
    local readable_date

    show_header
    echo "Sauvegardes disponibles"
    separator

    if [[ ! -d "$BACKUP_DIR" ]]; then
        warning "Le dossier de sauvegarde n'existe pas."
        return 0
    fi

    backups="$(
        find "$BACKUP_DIR" \
            -maxdepth 1 \
            -type f \
            -name 'mediastack_*.tar.gz' \
            -printf '%T@|%f|%s\n' 2>/dev/null |
        sort -nr
    )"

    if [[ -z "$backups" ]]; then
        warning "Aucune sauvegarde disponible."
        return 0
    fi

    printf "%-4s %-42s %-10s %-20s\n" \
        "#" "Fichier" "Taille" "Date"
    printf "%-4s %-42s %-10s %-20s\n" \
        "----" "------------------------------------------" "----------" "--------------------"

    while IFS='|' read -r timestamp filename size; do
        readable_size="$(
            numfmt --to=iec-i --suffix=B "$size" 2>/dev/null ||
            echo "${size} octets"
        )"

        readable_date="$(
            date -d "@${timestamp%.*}" '+%d/%m/%Y %H:%M:%S'
        )"

        printf "%-4s %-42s %-10s %-20s\n" \
            "$index" "$filename" "$readable_size" "$readable_date"

        ((index += 1))
    done <<< "$backups"

    echo
    printf "Emplacement : %s\n" "$BACKUP_DIR"
}

resolve_backup_file() {
    local requested="${1:-}"
    local candidate

    if [[ -n "$requested" ]]; then
        if [[ -f "$requested" ]]; then
            readlink -f "$requested"
            return
        fi

        candidate="${BACKUP_DIR}/${requested}"

        if [[ -f "$candidate" ]]; then
            readlink -f "$candidate"
            return
        fi

        die "Sauvegarde introuvable : ${requested}"
    fi

    candidate="$(
        find "$BACKUP_DIR" \
            -maxdepth 1 \
            -type f \
            -name 'mediastack_*.tar.gz' \
            -printf '%T@ %p\n' 2>/dev/null |
        sort -nr |
        head -n 1 |
        cut -d ' ' -f 2-
    )"

    [[ -n "$candidate" ]] \
        || die "Aucune sauvegarde MediaStack n'est disponible."

    readlink -f "$candidate"
}

validate_backup_archive() {
    local archive="$1"
    local invalid_entry

    tar -tzf "$archive" >/dev/null 2>&1 \
        || die "L'archive est endommagée ou illisible."

    invalid_entry="$(
        tar -tzf "$archive" |
        awk '
            /^\// { print; exit }
            /(^|\/)\.\.(\/|$)/ { print; exit }
        '
    )"

    [[ -z "$invalid_entry" ]] \
        || die "Archive refusée : chemin dangereux détecté (${invalid_entry})."
}

restore_backup() {
    require_root

    local archive
    local timestamp
    local safety_backup
    local stack_was_running=0

    archive="$(resolve_backup_file "${1:-}")"
    validate_backup_archive "$archive"

    show_header
    warning "La restauration va remplacer la configuration actuelle."
    printf "Archive : %s\n\n" "$archive"

    confirm_action "Confirmer la restauration ?" \
        || die "Restauration annulée."

    timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
    mkdir -p "$RESTORE_DIR"
    safety_backup="${RESTORE_DIR}/avant_restauration_${timestamp}.tar.gz"

    info "Création d'une sauvegarde de sécurité de l'état actuel..."
    tar \
        --exclude="${BACKUP_DIR}" \
        --exclude="${RESTORE_DIR}" \
        --exclude="${MEDIA_DIR}" \
        --exclude="${JELLYFIN_DIR}/cache" \
        -czf "$safety_backup" \
        "$STACK_DIR" \
        "${JELLYFIN_DIR}/config" \
        "$PORTAINER_DIR" \
        "$CADDY_DIR" \
        "$HOMEPAGE_DIR" \
        /etc/samba/smb.conf

    success "Sauvegarde de sécurité : ${safety_backup}"

    if compose ps --status running --services | grep -q .; then
        stack_was_running=1
    fi

    warning "Arrêt des conteneurs..."
    compose down

    info "Restauration des fichiers..."
    tar -xzf "$archive" -C /

    if command -v testparm >/dev/null 2>&1; then
        testparm -s >/dev/null 2>&1 \
            || warning "La configuration Samba restaurée semble invalide."
    fi

    systemctl restart smbd || warning "Impossible de redémarrer Samba."

    if (( stack_was_running == 1 )); then
        info "Redémarrage des conteneurs..."
        compose up -d
    fi

    success "Restauration terminée."
    compose ps
}

prune_docker() {
    require_root

    warning "Suppression des images et caches Docker inutilisés."
    docker image prune -f
    docker builder prune -f
    success "Nettoyage Docker terminé."
}

scan_jellyfin() {
    info "Pour détecter les nouveaux médias :"
    echo
    echo "Jellyfin → Tableau de bord → Bibliothèques"
    echo "→ Analyser toutes les bibliothèques"
    echo
    warning "Le scan via l'API Jellyfin sera ajouté dans une prochaine version."
}

count_files_by_extensions() {
    local directory="$1"
    shift

    [[ -d "$directory" ]] || {
        echo 0
        return
    }

    local find_arguments=()
    local extension

    for extension in "$@"; do
        if (( ${#find_arguments[@]} > 0 )); then
            find_arguments+=(-o)
        fi

        find_arguments+=(-iname "*.${extension}")
    done

    find "$directory" -type f \( "${find_arguments[@]}" \) 2>/dev/null |
        wc -l |
        tr -d ' '
}

directory_size() {
    local directory="$1"

    if [[ -d "$directory" ]]; then
        du -sh "$directory" 2>/dev/null | awk '{print $1}'
    else
        echo "0"
    fi
}

show_stats() {
    local video_extensions=(mp4 mkv avi mov m4v webm mpg mpeg ts)
    local audio_extensions=(mp3 flac wav ogg m4a aac opus wma)

    show_header

    echo "Bibliothèque"
    separator
    printf "Films            %s\n" \
        "$(count_files_by_extensions "$FILMS_DIR" "${video_extensions[@]}")"
    printf "Épisodes         %s\n" \
        "$(count_files_by_extensions "$SERIES_DIR" "${video_extensions[@]}")"
    printf "Musiques         %s\n" \
        "$(count_files_by_extensions "$MUSIC_DIR" "${audio_extensions[@]}")"

    echo
    echo "Espace utilisé"
    separator
    printf "Films            %s\n" "$(directory_size "$FILMS_DIR")"
    printf "Séries           %s\n" "$(directory_size "$SERIES_DIR")"
    printf "Musique          %s\n" "$(directory_size "$MUSIC_DIR")"

    echo
    echo "Système"
    separator
    printf "Mémoire          %s\n" "$(free -h | awk '/^Mem:/ {print $3 " / " $2}')"
    printf "Disque           %s\n" "$(df -h / | awk 'NR == 2 {print $3 " / " $2 " utilisés (" $5 ")"}')"
    printf "Charge           %s\n" "$(cut -d ' ' -f 1-3 /proc/loadavg)"
    printf "Disponibilité    %s\n" "$(uptime -p 2>/dev/null || uptime)"

    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        printf "Température CPU  %s\n" \
            "$(awk '{printf "%.1f°C", $1 / 1000}' /sys/class/thermal/thermal_zone0/temp)"
    fi

    echo
    echo "Services"
    separator
    print_service_states

    echo
    printf "Adresse IP       %s\n" "$(get_primary_ip)"
}

show_dashboard() {
    local video_extensions=(mp4 mkv avi mov m4v webm mpg mpeg ts)
    local audio_extensions=(mp3 flac wav ogg m4a aac opus wma)
    local latest_backup="Aucune"
    local backup_file
    local temperature="indisponible"

    backup_file="$(
        find "$BACKUP_DIR" \
            -maxdepth 1 \
            -type f \
            -name 'mediastack_*.tar.gz' \
            -printf '%T@ %f\n' 2>/dev/null |
        sort -nr |
        head -n 1 |
        cut -d ' ' -f 2-
    )"

    if [[ -n "$backup_file" ]]; then
        latest_backup="$backup_file"
    fi

    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        temperature="$(
            awk '{printf "%.1f°C", $1 / 1000}' \
                /sys/class/thermal/thermal_zone0/temp
        )"
    fi

    show_header
    printf "${BOLD}TABLEAU DE BORD${NC}\n\n"

    echo "Serveur"
    separator
    printf "Hôte             %s\n" "$(hostname)"
    printf "Adresse IP       %s\n" "$(get_primary_ip)"
    printf "Température      %s\n" "$temperature"
    printf "Mémoire          %s\n" "$(free -h | awk '/^Mem:/ {print $3 " / " $2}')"
    printf "Disque           %s\n" "$(df -h / | awk 'NR == 2 {print $3 " / " $2 " (" $5 ")"}')"
    printf "Charge           %s\n" "$(cut -d ' ' -f 1-3 /proc/loadavg)"
    printf "Disponibilité    %s\n" "$(uptime -p 2>/dev/null || uptime)"

    echo
    echo "Services"
    separator
    print_service_states

    echo
    echo "Bibliothèque"
    separator
    printf "Films            %s\n" \
        "$(count_files_by_extensions "$FILMS_DIR" "${video_extensions[@]}")"
    printf "Épisodes         %s\n" \
        "$(count_files_by_extensions "$SERIES_DIR" "${video_extensions[@]}")"
    printf "Musiques         %s\n" \
        "$(count_files_by_extensions "$MUSIC_DIR" "${audio_extensions[@]}")"

    echo
    echo "Sauvegardes"
    separator
    printf "Dernière         %s\n" "$latest_backup"

    echo
    echo "Accès"
    separator
    printf "Jellyfin         http://%s:8096\n" "$(get_primary_ip)"
    printf "Portainer        https://%s:9443\n" "$(get_primary_ip)"

    if [[ -f "$HOMEPAGE_COMPOSE_FILE" ]]; then
        printf "Homepage         http://%s:3000\n" "$(get_primary_ip)"
    else
        printf "Homepage         non installé\n"
    fi
}

run_doctor() {
    local ok_count=0
    local warning_count=0
    local error_count=0

    local service
    local container_id
    local container_status
    local health_status
    local disk_usage
    local temperature
    local latest_backup
    local backup_timestamp
    local backup_age_days
    local directory

    doctor_ok() {
        printf "${GREEN}[OK]${NC}         %s\n" "$*"
        ((ok_count += 1))
    }

    doctor_warning() {
        printf "${YELLOW}[ATTENTION]${NC}  %s\n" "$*"
        ((warning_count += 1))
    }

    doctor_error() {
        printf "${RED}[ERREUR]${NC}     %s\n" "$*"
        ((error_count += 1))
    }

    show_header
    echo "Diagnostic complet du serveur"
    echo

    echo "Docker"
    separator

    if docker info >/dev/null 2>&1; then
        doctor_ok "Docker répond correctement."
    else
        doctor_error "Docker ne répond pas."
    fi

    if compose config --quiet >/dev/null 2>&1; then
        doctor_ok "La configuration Docker Compose est valide."
    else
        doctor_error "La configuration Docker Compose est invalide."
    fi

    while IFS= read -r service; do
        container_id="$(compose ps -q "$service" 2>/dev/null || true)"

        if [[ -z "$container_id" ]]; then
            doctor_error "Conteneur absent : ${service}"
            continue
        fi

        container_status="$(
            docker inspect \
                --format '{{.State.Status}}' \
                "$container_id" 2>/dev/null || true
        )"

        if [[ "$container_status" == "running" ]]; then
            doctor_ok "Conteneur actif : ${service}"
        else
            doctor_error "Conteneur ${service} : ${container_status:-inconnu}"
            continue
        fi

        health_status="$(
            docker inspect \
                --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
                "$container_id" 2>/dev/null || true
        )"

        case "$health_status" in
            healthy)
                doctor_ok "Healthcheck valide : ${service}"
                ;;
            unhealthy)
                doctor_error "Healthcheck en échec : ${service}"
                ;;
            starting)
                doctor_warning "Healthcheck en cours : ${service}"
                ;;
            "")
                doctor_warning "Aucun healthcheck configuré : ${service}"
                ;;
        esac
    done < <(compose config --services)

    echo
    echo "Services et accès"
    separator

    if systemctl is-active --quiet smbd; then
        doctor_ok "Samba est actif."
    else
        doctor_error "Samba est inactif."
    fi

    if systemctl is-enabled --quiet smbd 2>/dev/null; then
        doctor_ok "Samba démarrera automatiquement."
    else
        doctor_warning "Samba n'est pas activé au démarrage."
    fi

    if command -v curl >/dev/null 2>&1; then
        if curl --silent --show-error --fail --max-time 5 \
            http://127.0.0.1:8096/health >/dev/null 2>&1; then
            doctor_ok "Jellyfin répond sur le port 8096."
        elif curl --silent --fail --max-time 5 \
            http://127.0.0.1:8096 >/dev/null 2>&1; then
            doctor_ok "L'interface Jellyfin est accessible."
        else
            doctor_error "Jellyfin ne répond pas sur le port 8096."
        fi
    else
        doctor_warning "curl absent : test HTTP de Jellyfin ignoré."
    fi

    if command -v ss >/dev/null 2>&1; then
        if ss -lnt | awk '{print $4}' | grep -Eq '(^|:)8096$'; then
            doctor_ok "Le port Jellyfin 8096 est ouvert."
        else
            doctor_error "Le port Jellyfin 8096 n'est pas ouvert."
        fi
    else
        doctor_warning "Commande ss absente : contrôle des ports ignoré."
    fi

    echo
    echo "Accélération matérielle"
    separator

    if [[ -e /dev/dri/renderD128 ]]; then
        doctor_ok "/dev/dri/renderD128 existe."
    else
        doctor_warning "/dev/dri/renderD128 est absent."
    fi

    if [[ -r /dev/dri/renderD128 && -w /dev/dri/renderD128 ]]; then
        doctor_ok "Le périphérique vidéo est accessible."
    else
        doctor_warning "Les droits du périphérique vidéo sont limités."
    fi

    if docker exec jellyfin test -e /dev/dri/renderD128 2>/dev/null; then
        doctor_ok "Jellyfin voit le périphérique vidéo."
    else
        doctor_warning "Jellyfin ne voit pas /dev/dri/renderD128."
    fi

    echo
    echo "Dossiers et permissions"
    separator

    for directory in \
        "$FILMS_DIR" \
        "$SERIES_DIR" \
        "$MUSIC_DIR" \
        "${JELLYFIN_DIR}/config" \
        "$PORTAINER_DIR" \
        "$CADDY_DIR"
    do
        if [[ ! -d "$directory" ]]; then
            doctor_error "Dossier absent : ${directory}"
        elif [[ ! -r "$directory" ]]; then
            doctor_error "Dossier non lisible : ${directory}"
        elif [[ ! -w "$directory" ]]; then
            doctor_warning "Dossier non modifiable : ${directory}"
        else
            doctor_ok "Dossier accessible : ${directory}"
        fi
    done

    echo
    echo "Ressources système"
    separator

    disk_usage="$(df --output=pcent / | tail -1 | tr -dc '0-9')"

    if (( disk_usage >= 90 )); then
        doctor_error "Disque presque plein : ${disk_usage}%."
    elif (( disk_usage >= 80 )); then
        doctor_warning "Utilisation élevée du disque : ${disk_usage}%."
    else
        doctor_ok "Espace disque correct : ${disk_usage}% utilisé."
    fi

    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        temperature="$(
            awk '{printf "%.0f", $1 / 1000}' \
                /sys/class/thermal/thermal_zone0/temp
        )"

        if (( temperature >= 80 )); then
            doctor_error "Température CPU critique : ${temperature}°C."
        elif (( temperature >= 70 )); then
            doctor_warning "Température CPU élevée : ${temperature}°C."
        else
            doctor_ok "Température CPU correcte : ${temperature}°C."
        fi
    else
        doctor_warning "Température CPU indisponible."
    fi

    doctor_ok "Charge système : $(cut -d ' ' -f 1-3 /proc/loadavg)"
    doctor_ok "Mémoire : $(free -h | awk '/^Mem:/ {print $3 " / " $2}')"

    echo
    echo "Sauvegardes"
    separator

    latest_backup="$(
        find "$BACKUP_DIR" \
            -maxdepth 1 \
            -type f \
            -name 'mediastack_*.tar.gz' \
            -printf '%T@ %p\n' 2>/dev/null |
        sort -nr |
        head -n 1 |
        cut -d ' ' -f 2-
    )"

    if [[ -z "$latest_backup" ]]; then
        doctor_warning "Aucune sauvegarde MediaStack trouvée."
    else
        backup_timestamp="$(stat -c %Y "$latest_backup")"
        backup_age_days=$(( ($(date +%s) - backup_timestamp) / 86400 ))

        if (( backup_age_days > 30 )); then
            doctor_warning "Dernière sauvegarde ancienne : ${backup_age_days} jours."
        else
            doctor_ok "Dernière sauvegarde : $(basename "$latest_backup")"
        fi
    fi

    echo
    separator
    echo "Résultat du diagnostic"
    separator
    printf "${GREEN}Contrôles réussis : %s${NC}\n" "$ok_count"
    printf "${YELLOW}Avertissements    : %s${NC}\n" "$warning_count"
    printf "${RED}Erreurs           : %s${NC}\n" "$error_count"
    echo

    if (( error_count > 0 )); then
        error "MediaStack présente une ou plusieurs erreurs."
        return 1
    elif (( warning_count > 0 )); then
        warning "MediaStack fonctionne avec quelques avertissements."
    else
        success "MediaStack est entièrement opérationnelle."
    fi
}

write_homepage_configuration() {
    local server_ip
    server_ip="$(get_primary_ip)"

    mkdir -p "$HOMEPAGE_DIR"

    cat > "${HOMEPAGE_DIR}/settings.yaml" <<'EOF'
title: MediaStack
theme: dark
color: slate
headerStyle: clean
hideVersion: true
statusStyle: dot
layout:
  Médias:
    style: row
    columns: 3
  Administration:
    style: row
    columns: 3
EOF

    cat > "${HOMEPAGE_DIR}/services.yaml" <<EOF
- Médias:
    - Jellyfin:
        icon: jellyfin.png
        href: http://${server_ip}:8096
        description: Films, séries et musique
        server: mediastack
        container: jellyfin

- Administration:
    - Portainer:
        icon: portainer.png
        href: https://${server_ip}:9443
        description: Administration Docker
        server: mediastack
        container: portainer

    - MediaStack:
        icon: mdi-server
        href: http://${server_ip}:3000
        description: Tableau de bord du serveur
EOF

    cat > "${HOMEPAGE_DIR}/widgets.yaml" <<'EOF'
- resources:
    cpu: true
    memory: true
    disk: /
    uptime: true

- search:
    provider: google
    target: _blank

- datetime:
    text_size: xl
    format:
      dateStyle: long
      timeStyle: short
EOF

    cat > "${HOMEPAGE_DIR}/bookmarks.yaml" <<'EOF'
- Documentation:
    - Jellyfin:
        - icon: jellyfin.png
          href: https://jellyfin.org/docs/
    - Homepage:
        - icon: homepage.png
          href: https://gethomepage.dev/
EOF

    cat > "${HOMEPAGE_DIR}/docker.yaml" <<'EOF'
mediastack:
  socket: /var/run/docker.sock
EOF

    cat > "$HOMEPAGE_COMPOSE_FILE" <<EOF
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      HOMEPAGE_ALLOWED_HOSTS: "${server_ip}:3000,localhost:3000,media:3000"
    volumes:
      - "${HOMEPAGE_DIR}:/app/config"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
EOF
}

homepage_install() {
    require_root

    info "Création de la configuration Homepage..."
    write_homepage_configuration

    info "Téléchargement et démarrage de Homepage..."
    compose pull homepage
    compose up -d homepage

    success "Homepage est installée."
    printf "Adresse : http://%s:3000\n" "$(get_primary_ip)"
}

homepage_status() {
    if [[ ! -f "$HOMEPAGE_COMPOSE_FILE" ]]; then
        warning "Homepage n'est pas installée."
        return 0
    fi

    compose ps homepage
    printf "Adresse : http://%s:3000\n" "$(get_primary_ip)"
}

homepage_update() {
    require_root

    [[ -f "$HOMEPAGE_COMPOSE_FILE" ]] \
        || die "Homepage n'est pas installée."

    info "Mise à jour de la configuration Homepage..."
    write_homepage_configuration

    compose pull homepage
    compose up -d homepage

    success "Homepage est à jour."
}

homepage_remove() {
    require_root

    [[ -f "$HOMEPAGE_COMPOSE_FILE" ]] \
        || die "Homepage n'est pas installée."

    warning "Homepage va être supprimée de MediaStack."

    confirm_action "Confirmer la suppression ?" \
        || die "Suppression annulée."

    compose stop homepage || true
    compose rm -f homepage || true
    rm -f "$HOMEPAGE_COMPOSE_FILE"

    success "Homepage a été retirée."
    warning "La configuration est conservée dans ${HOMEPAGE_DIR}."
}

homepage_command() {
    local action="${1:-status}"

    case "$action" in
        install)
            homepage_install
            ;;
        status)
            homepage_status
            ;;
        update|configure)
            homepage_update
            ;;
        remove)
            homepage_remove
            ;;
        *)
            die "Action Homepage inconnue : ${action}. Utilise install, status, update ou remove."
            ;;
    esac
}

show_version() {
    local docker_version
    local compose_version
    local jellyfin_version="indisponible"
    local homepage_state="non installé"

    docker_version="$(docker --version 2>/dev/null || echo "indisponible")"
    compose_version="$(docker compose version 2>/dev/null || echo "indisponible")"

    if docker ps --format '{{.Names}}' | grep -Fxq jellyfin; then
        jellyfin_version="$(
            docker exec jellyfin \
                /jellyfin/jellyfin --version 2>/dev/null |
            head -n 1 ||
            echo "indisponible"
        )"
    fi

    if [[ -f "$HOMEPAGE_COMPOSE_FILE" ]]; then
        homepage_state="installé"
    fi

    show_header
    printf "Auteur           René Leliard\n"
    printf "Docker           %s\n" "$docker_version"
    printf "Compose          %s\n" "$compose_version"
    printf "Jellyfin         %s\n" "$jellyfin_version"
    printf "Homepage         %s\n" "$homepage_state"
}

show_help() {
    cat <<EOF
${SCRIPT_NAME} ${SCRIPT_VERSION}

Utilisation :
  media <commande>

Commandes disponibles :

  start                         Démarrer les services
  stop                          Arrêter les services
  restart                       Redémarrer les services
  status                        Afficher l'état général
  stats                         Afficher les statistiques
  dashboard                     Afficher le tableau de bord
  logs [service]                Afficher les logs
  update                        Mettre à jour les images Docker
  health                        Effectuer les contrôles essentiels
  doctor                        Effectuer un diagnostic complet
  backup                        Créer une sauvegarde
  backups                       Lister les sauvegardes
  restore [archive]             Restaurer une sauvegarde
  homepage install              Installer Homepage
  homepage status               Afficher l'état de Homepage
  homepage update               Mettre à jour Homepage
  homepage remove               Retirer Homepage
  prune                         Nettoyer Docker
  scan                          Afficher la procédure de scan Jellyfin
  version                       Afficher les versions
  help                          Afficher cette aide

Exemples :

  media dashboard
  media doctor
  media backup
  media restore mediastack_2026-07-18_17-36-00.tar.gz
  media homepage install
  media homepage status
EOF
}

main() {
    require_commands
    check_stack

    case "${1:-help}" in
        start)
            start_stack
            ;;
        stop)
            stop_stack
            ;;
        restart)
            restart_stack
            ;;
        status)
            show_status
            ;;
        stats)
            show_stats
            ;;
        dashboard)
            show_dashboard
            ;;
        logs)
            show_logs "${2:-}"
            ;;
        update)
            update_stack
            ;;
        health)
            health_check
            ;;
        doctor)
            run_doctor
            ;;
        backup)
            create_backup
            ;;
        backups)
            list_backups
            ;;
        restore)
            restore_backup "${2:-}"
            ;;
        homepage)
            homepage_command "${2:-status}"
            ;;
        prune)
            prune_docker
            ;;
        scan)
            scan_jellyfin
            ;;
        version|-v|--version)
            show_version
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            error "Commande inconnue : ${1:-}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"

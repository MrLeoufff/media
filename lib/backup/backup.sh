#!/usr/bin/env bash

prune_backups() {
    local keep=5
    local arg

    for arg in "$@"; do
        case "${arg}" in
            --keep=*)
                keep="${arg#--keep=}"
                ;;
            --keep)
                media_die "Usage : media backup prune --keep <n>"
                ;;
            *)
                if [[ "${arg}" =~ ^[0-9]+$ ]]; then
                    keep="${arg}"
                else
                    media_die "Option prune inconnue : ${arg}"
                fi
                ;;
        esac
    done

    if ! [[ "${keep}" =~ ^[0-9]+$ ]] || (( keep < 1 )); then
        media_die "La valeur --keep doit être un entier >= 1."
    fi

    mkdir -p "${BACKUP_DIR}"

    local archives=()
    local index
    local archive

    mapfile -t archives < <(
        find "${BACKUP_DIR}" \
            -maxdepth 1 \
            -type f \
            \( -name 'mediastack-backup-*.tar.gz' -o -name 'mediastack_*.tar.gz' \) \
            -printf '%T@ %p\n' 2>/dev/null |
            sort -nr |
            awk '{print $2}'
    )

    if (( ${#archives[@]} <= keep )); then
        media_success "Rien à purger (${#archives[@]} archive(s), keep=${keep})."
        return 0
    fi

    for ((index=keep; index<${#archives[@]}; index++)); do
        archive="${archives[$index]}"
        rm -f "${archive}" "${archive}.sha256"
        media_info "Supprimée : $(basename "${archive}")"
    done

    media_success "Purge terminée (conservé : ${keep})."
}

backup_command() {
    case "${1:-list}" in
        create) create_backup ;;
        list) list_backups ;;
        verify) verify_backup "${2:-}" ;;
        restore) restore_backup "${2:-}" ;;
        prune) shift; prune_backups "$@" ;;
        help|-h|--help)
            cat <<'BACKUP_HELP'
Utilisation :
  media backup create
  media backup list
  media backup verify [archive]
  media backup restore [archive]
  media backup prune [--keep <n>]
BACKUP_HELP
            ;;
        *) media_die "Commande backup inconnue : $1" ;;
    esac
}

#!/usr/bin/env bash

backup_command() {
    case "${1:-list}" in
        create) create_backup ;;
        list) list_backups ;;
        verify) verify_backup "${2:-}" ;;
        restore) restore_backup "${2:-}" ;;
        *) media_die "Commande backup inconnue : $1" ;;
    esac
}

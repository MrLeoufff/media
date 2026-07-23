#!/usr/bin/env bash

run_security_fix() {
    require_root

    media_warning "Garde la session SSH actuelle ouverte."
    confirm_action "Installer et configurer UFW ?" &&
        configure_firewall

    confirm_action "Installer et configurer Fail2ban ?" &&
        configure_fail2ban

    confirm_action "Activer les mises à jour automatiques ?" &&
        configure_automatic_updates

    audit_ssh_keys

    media_success "Configuration de sécurité terminée."
    run_security_audit
}

security_command() {
    case "${1:-audit}" in
        audit) run_security_audit ;;
        fix) run_security_fix ;;
        firewall) configure_firewall ;;
        fail2ban) configure_fail2ban ;;
        updates) configure_automatic_updates ;;
        ssh-audit) audit_ssh_keys ;;
        *) media_die "Commande security inconnue : $1" ;;
    esac
}

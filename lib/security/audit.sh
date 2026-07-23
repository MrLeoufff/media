#!/usr/bin/env bash

get_effective_sshd_value() {
    sshd -T 2>/dev/null |
        awk -v key="$1" '$1 == key {print $2; exit}'
}

audit_firewall() {
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q '^Status: active'; then
            media_success "UFW actif."
        else
            media_warning "UFW installé mais inactif."
        fi
    else
        media_warning "UFW absent."
    fi
}

audit_fail2ban() {
    systemctl is-active --quiet fail2ban &&
        media_success "Fail2ban actif." ||
        media_warning "Fail2ban absent ou inactif."
}

audit_automatic_updates() {
    systemctl is-active --quiet unattended-upgrades &&
        media_success "Mises à jour automatiques actives." ||
        media_warning "Mises à jour automatiques inactives."
}

audit_ssh() {
    local password_auth
    local root_login

    password_auth="$(get_effective_sshd_value passwordauthentication || true)"
    root_login="$(get_effective_sshd_value permitrootlogin || true)"

    [[ "${password_auth}" == "no" ]] &&
        media_success "Mot de passe SSH désactivé." ||
        media_warning "Authentification SSH par mot de passe active."

    case "${root_login}" in
        no)
            media_success "Connexion SSH root entièrement désactivée."
            ;;
        prohibit-password|without-password)
            media_success "Connexion SSH root par mot de passe désactivée."
            ;;
        *)
            media_warning "Connexion SSH root autorisée : ${root_login:-inconnue}."
            ;;
    esac
}

audit_docker_ports() {
    local exposed
    exposed="$(
        docker ps --format '{{.Names}} {{.Ports}}' |
        grep -E '0\.0\.0\.0:(3000|8096|9443)->|\[::\]:(3000|8096|9443)->' ||
        true
    )"

    if [[ -z "${exposed}" ]]; then
        media_success "Services internes non exposés sur toutes les interfaces."
    else
        media_warning "Ports Docker internes publiés :"
        echo "${exposed}"
    fi
}

run_security_audit() {
    media_header
    echo "Audit de sécurité"
    media_separator

    audit_firewall
    audit_fail2ban
    audit_automatic_updates
    audit_ssh
    audit_docker_ports
}

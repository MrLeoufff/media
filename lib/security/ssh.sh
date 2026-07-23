#!/usr/bin/env bash

audit_ssh_keys() {
    local user_name="${SUDO_USER:-rene}"
    local user_home

    user_home="$(getent passwd "${user_name}" | cut -d: -f6)"

    if [[ -f "${user_home}/.ssh/authorized_keys" ]] &&
       [[ -s "${user_home}/.ssh/authorized_keys" ]]; then
        media_success "Clé SSH trouvée pour ${user_name}."
    else
        media_warning "Aucune clé SSH trouvée pour ${user_name}."
        media_warning "Ne désactive pas le mot de passe avant d'avoir testé une clé."
    fi
}

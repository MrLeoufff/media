#!/usr/bin/env bash

configure_fail2ban() {
    require_root

    apt-get update
    apt-get install -y fail2ban

    cat > /etc/fail2ban/jail.d/mediastack.conf <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd
ignoreip = 127.0.0.1/8 ::1 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12

[sshd]
enabled = true
port = ssh
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban

    for attempt in {1..10}; do
        if fail2ban-client ping >/dev/null 2>&1; then
            break
        fi

        sleep 1
    done

    if ! fail2ban-client ping >/dev/null 2>&1; then
        media_error "Fail2ban n'a pas démarré correctement."
        systemctl status fail2ban --no-pager -l || true
        journalctl -u fail2ban -n 30 --no-pager || true
        return 1
    fi

    media_success "Fail2ban installé et configuré."
    fail2ban-client status sshd
}

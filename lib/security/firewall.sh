#!/usr/bin/env bash

configure_firewall() {
    require_root

    apt-get update
    apt-get install -y ufw

    ufw default deny incoming
    ufw default allow outgoing

    ufw allow 22/tcp comment "SSH"
    ufw allow 80/tcp comment "HTTP Caddy"
    ufw allow 443/tcp comment "HTTPS Caddy"
    ufw allow 443/udp comment "HTTP3 Caddy"

    ufw allow from 192.168.1.0/24 to any port 139 proto tcp comment "Samba LAN"
    ufw allow from 192.168.1.0/24 to any port 445 proto tcp comment "Samba LAN"
    ufw allow from 192.168.1.0/24 to any port 137 proto udp comment "NetBIOS LAN"
    ufw allow from 192.168.1.0/24 to any port 138 proto udp comment "NetBIOS LAN"

    ufw --force enable
    media_success "UFW installé et configuré."
    ufw status verbose
}

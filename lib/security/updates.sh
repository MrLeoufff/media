#!/usr/bin/env bash

configure_automatic_updates() {
    require_root

    apt-get update
    apt-get install -y unattended-upgrades apt-listchanges

    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    systemctl enable --now unattended-upgrades
    media_success "Mises à jour automatiques activées."
}

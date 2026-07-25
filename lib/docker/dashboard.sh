#!/usr/bin/env bash

display_service_state() {
    local service="$1"

    if service_is_running "${service}"; then
        printf "${COLOR_GREEN}✔${COLOR_RESET} %-18s actif\n" "${service}"
    else
        printf "${COLOR_RED}✘${COLOR_RESET} %-18s inactif\n" "${service}"
    fi
}

show_dashboard() {
    media_header
    echo -e "${COLOR_BOLD}TABLEAU DE BORD${COLOR_RESET}"
    echo

    printf "Hôte             %s\n" "$(hostname)"
    printf "Adresse IP       %s\n" "$(primary_ip)"
    printf "Mémoire          %s\n" "$(free -h | awk '/^Mem:/ {print $3 " / " $2}')"
    printf "Disque           %s\n" "$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
    printf "Charge           %s\n" "$(cut -d ' ' -f1-3 /proc/loadavg)"

    if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
        printf "Température      %s\n" \
            "$(awk '{printf "%.1f°C", $1/1000}' /sys/class/thermal/thermal_zone0/temp)"
    fi

    echo
    echo "Services"
    media_separator

    while IFS= read -r service; do
        display_service_state "${service}"
    done < <(service_names)

    if systemctl is-active --quiet smbd; then
        printf "${COLOR_GREEN}✔${COLOR_RESET} %-18s actif\n" "samba"
    else
        printf "${COLOR_RED}✘${COLOR_RESET} %-18s inactif\n" "samba"
    fi
}

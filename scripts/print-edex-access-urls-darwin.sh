#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="${1:-${HOME}/Library/Application Support/eDEX-UI-Service/edex.env}"
MODE="${2:-}"

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

: "${EDEX_WEB_PORT:=6080}"

novnc_path() {
    printf '/vnc.html?autoconnect=1&resize=remote&path=websockify'
}

local_url() {
    printf 'http://127.0.0.1:%s%s\n' "$EDEX_WEB_PORT" "$(novnc_path)"
}

lan_ips() {
    if [[ -n "${EDEX_ACCESS_IPS:-}" ]]; then
        printf '%s\n' $EDEX_ACCESS_IPS
        return
    fi

    if command -v ipconfig >/dev/null 2>&1; then
        for iface in en0 en1 en2; do
            ipconfig getifaddr "$iface" 2>/dev/null || true
        done
    fi

    if command -v ifconfig >/dev/null 2>&1; then
        ifconfig 2>/dev/null |
            awk '/inet / && $2 != "127.0.0.1" { print $2 }'
    elif command -v hostname >/dev/null 2>&1; then
        hostname -I 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i != "127.0.0.1") print $i }'
    fi
}

first_lan_ip() {
    local ip_addr
    while IFS= read -r ip_addr; do
        [[ -n "$ip_addr" ]] || continue
        printf '%s' "$ip_addr"
        return
    done < <(lan_ips | awk '!seen[$0]++')
}

lan_url() {
    local ip_addr="${1:-}"
    ip_addr="${ip_addr:-$(first_lan_ip)}"
    ip_addr="${ip_addr:-<mac-lan-ip>}"
    printf 'http://%s:%s%s\n' "$ip_addr" "$EDEX_WEB_PORT" "$(novnc_path)"
}

case "$MODE" in
    local-url)
        local_url
        exit 0
        ;;
    lan-url)
        lan_url
        exit 0
        ;;
esac

printf '\n== macOS Browser URLs ==\n'
printf '  Local URL: %s\n' "$(local_url)"
found_ip=0
while IFS= read -r ip_addr; do
    [[ -n "$ip_addr" ]] || continue
    found_ip=1
    printf '  LAN URL  : %s\n' "$(lan_url "$ip_addr")"
done < <(lan_ips | awk '!seen[$0]++')

if [[ "$found_ip" -eq 0 ]]; then
    printf '  LAN URL  : %s\n' "$(lan_url)"
fi

printf '\n== macOS Screen Sharing Requirement ==\n'
printf '  The browser connects to macOS Screen Sharing through noVNC.\n'
printf '  Enable Screen Sharing and "VNC viewers may control screen with password" in System Settings.\n'

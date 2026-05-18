#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="${1:-/etc/edex-ui/edex.env}"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

: "${EDEX_WEB_PORT:=8443}"
: "${EDEX_NOVNC_PORT:=6080}"
: "${EDEX_VNC_PORT:=5901}"
: "${EDEX_PUBLIC_HOSTNAME:=}"

section() {
    printf '\n== %s ==\n' "$*"
}

container_ips() {
    if [[ -n "${EDEX_ACCESS_IPS:-}" ]]; then
        printf '%s\n' $EDEX_ACCESS_IPS
        return
    fi

    if command -v ip >/dev/null 2>&1; then
        ip -4 addr show scope global 2>/dev/null |
            awk '/inet / { sub(/\/.*/, "", $2); print $2 }'
        return
    fi

    hostname -I 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) print $i }'
}

first_container_ip() {
    local ip_addr
    while IFS= read -r ip_addr; do
        [[ -n "$ip_addr" ]] || continue
        printf '%s' "$ip_addr"
        return
    done < <(container_ips)
}

novnc_path() {
    printf '/vnc.html?autoconnect=1&resize=remote&path=websockify'
}

section "Browser URLs"
found_ip=0
while IFS= read -r ip_addr; do
    [[ -n "$ip_addr" ]] || continue
    found_ip=1
    printf '  LAN noVNC URL : https://%s:%s%s\n' "$ip_addr" "$EDEX_WEB_PORT" "$(novnc_path)"
    printf '  LAN base URL  : https://%s:%s/\n' "$ip_addr" "$EDEX_WEB_PORT"
done < <(container_ips)

if [[ "$found_ip" -eq 0 ]]; then
    printf '  LAN noVNC URL : https://<server-ip>:%s%s\n' "$EDEX_WEB_PORT" "$(novnc_path)"
    printf '  LAN base URL  : https://<server-ip>:%s/\n' "$EDEX_WEB_PORT"
fi

if [[ -n "$EDEX_PUBLIC_HOSTNAME" ]]; then
    public_host="${EDEX_PUBLIC_HOSTNAME#http://}"
    public_host="${public_host#https://}"
    public_host="${public_host%%/*}"
    printf '  Cloudflare URL: https://%s%s\n' "$public_host" "$(novnc_path)"
else
    printf '  Cloudflare URL: https://<cloudflare-hostname>%s\n' "$(novnc_path)"
fi

section "Private Backends"
printf '  noVNC backend : http://127.0.0.1:%s/vnc.html\n' "$EDEX_NOVNC_PORT"
printf '  Raw VNC       : 127.0.0.1:%s\n' "$EDEX_VNC_PORT"

section "Cloudflare Tunnel"
cloudflare_ip="$(first_container_ip)"
cloudflare_ip="${cloudflare_ip:-<server-ip>}"
printf '  noVNC origin  : tcp://%s:%s\n' "$cloudflare_ip" "$EDEX_WEB_PORT"
printf '  VNC origin    : tcp://%s:%s\n' "$cloudflare_ip" "$EDEX_VNC_PORT"
printf '  Expose the Nginx noVNC endpoint for browser access; expose raw VNC only when you explicitly need a VNC client.\n'

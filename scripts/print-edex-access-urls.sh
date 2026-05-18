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
: "${EDEX_RAW_VNC_HOST:=127.0.0.1}"
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

is_loopback_host() {
    case "$1" in
        127.0.0.1|localhost|::1)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

public_host() {
    local host="$EDEX_PUBLIC_HOSTNAME"
    host="${host#http://}"
    host="${host#https://}"
    host="${host%%/*}"
    printf '%s' "$host"
}

cloudflare_ip="$(first_container_ip)"
cloudflare_ip="${cloudflare_ip:-<server-ip>}"
cloudflare_browser_host="$(public_host)"

section "LAN Browser"
found_ip=0
while IFS= read -r ip_addr; do
    [[ -n "$ip_addr" ]] || continue
    found_ip=1
    printf '  LAN browser URL: https://%s:%s%s\n' "$ip_addr" "$EDEX_WEB_PORT" "$(novnc_path)"
done < <(container_ips)

if [[ "$found_ip" -eq 0 ]]; then
    printf '  LAN browser URL: https://<server-ip>:%s%s\n' "$EDEX_WEB_PORT" "$(novnc_path)"
fi

section "Cloudflare Browser-Rendered VNC"
printf '  Cloudflare browser origin: https://%s:%s\n' "$cloudflare_ip" "$EDEX_WEB_PORT"
if [[ -n "$cloudflare_browser_host" ]]; then
    printf '  Cloudflare browser URL   : https://%s%s\n' "$cloudflare_browser_host" "$(novnc_path)"
else
    printf '  Cloudflare browser URL   : https://<cloudflare-hostname>%s\n' "$(novnc_path)"
fi
printf '  Cloudflare tunnel option : originRequest.noTLSVerify=true\n'

section "Private Backends"
printf '  noVNC backend : http://127.0.0.1:%s/vnc.html\n' "$EDEX_NOVNC_PORT"
printf '  Raw VNC       : %s:%s\n' "$EDEX_RAW_VNC_HOST" "$EDEX_VNC_PORT"

section "Cloudflare Raw VNC"
if is_loopback_host "$EDEX_RAW_VNC_HOST"; then
    printf '  Cloudflare raw VNC origin: disabled; raw VNC is loopback-only by default\n'
    printf '  Enable only with EDEX_RAW_VNC_HOST=<lan-ip-or-0.0.0.0> and EDEX_VNC_PASSWORD_FILE or EDEX_VNC_PASSWORD.\n'
else
    raw_vnc_host="$EDEX_RAW_VNC_HOST"
    if [[ "$raw_vnc_host" == "0.0.0.0" ]]; then
        raw_vnc_host="$cloudflare_ip"
    fi
    printf '  Cloudflare raw VNC origin: tcp://%s:%s\n' "$raw_vnc_host" "$EDEX_VNC_PORT"
    printf '  Use this only when Cloudflare is configured for TCP/raw VNC instead of browser-rendered noVNC.\n'
fi

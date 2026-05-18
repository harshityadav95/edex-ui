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
: "${EDEX_DISPLAY:=:1}"
: "${EDEX_DISPLAY_BACKEND:=auto}"
: "${EDEX_PUBLIC_HOSTNAME:=}"

section() {
    printf '\n== %s ==\n' "$*"
}

container_ip() {
    hostname -I 2>/dev/null | awk '{print $1}'
}

section "Configuration"
printf 'Display: %s\n' "$EDEX_DISPLAY"
printf 'Display backend: %s\n' "$EDEX_DISPLAY_BACKEND"
printf 'LAN URL: https://%s:%s/\n' "$(container_ip)" "$EDEX_WEB_PORT"
printf 'noVNC/Kasm web backend: 127.0.0.1:%s\n' "$EDEX_NOVNC_PORT"
printf 'VNC backend: %s:%s\n' "$EDEX_RAW_VNC_HOST" "$EDEX_VNC_PORT"
if [[ -n "$EDEX_PUBLIC_HOSTNAME" ]]; then
    printf 'Cloudflare hostname: %s\n' "$EDEX_PUBLIC_HOSTNAME"
fi

if command -v print-edex-access-urls.sh >/dev/null 2>&1; then
    print-edex-access-urls.sh "$ENV_FILE"
elif [[ -x "$(dirname "${BASH_SOURCE[0]}")/print-edex-access-urls.sh" ]]; then
    "$(dirname "${BASH_SOURCE[0]}")/print-edex-access-urls.sh" "$ENV_FILE"
fi

section "GPU"
if compgen -G '/dev/dri/renderD*' >/dev/null; then
    ls -l /dev/dri/renderD*
else
    printf 'No /dev/dri/renderD* device visible; Xvfb/software rendering is expected.\n'
fi

section "Systemd"
if command -v systemctl >/dev/null 2>&1; then
    systemctl --no-pager --full status edex.service || true
else
    printf 'systemctl is not available.\n'
fi

section "Listeners"
if command -v ss >/dev/null 2>&1; then
    ss -ltnp | awk -v web=":${EDEX_WEB_PORT}" -v novnc=":${EDEX_NOVNC_PORT}" -v vnc=":${EDEX_VNC_PORT}" \
        'NR == 1 || index($0, web) || index($0, novnc) || index($0, vnc) || /:3000|:3001|:3002|:3003|:3004|:3005|:3006/'
else
    printf 'ss is not available.\n'
fi

section "Processes"
ps -eo pid,user,comm,args | awk 'NR == 1 || /electron|edex|Xvfb|Xorg|openbox|x11vnc|novnc|websockify|kasmvnc/'

section "Recent journal"
if command -v journalctl >/dev/null 2>&1; then
    journalctl -u edex.service -n 80 --no-pager || true
else
    printf 'journalctl is not available.\n'
fi

#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE=/etc/edex-ui/edex.env

log() {
    printf '[edex-start] %s\n' "$*"
}

need_root_or_reexec() {
    if [[ "${EUID}" -eq 0 ]]; then
        return
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        printf 'This script installs system packages and services. Run it as root or install sudo.\n' >&2
        exit 1
    fi

    log "re-running with sudo"
    exec sudo -E bash "$0" "$@"
}

container_ips() {
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

print_urls() {
    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
    fi

    : "${EDEX_WEB_PORT:=8443}"
    : "${EDEX_VNC_PORT:=5901}"

    local novnc_path="/vnc.html?autoconnect=1&resize=remote&path=websockify"
    local cloudflare_ip
    cloudflare_ip="$(first_container_ip)"
    cloudflare_ip="${cloudflare_ip:-<server-ip>}"

    printf '\n'
    printf 'eDEX-UI is starting as systemd service: edex.service\n'
    printf '\n'
    printf 'Cloudflare accepted TCP origins:\n'
    printf '  Cloudflare noVNC: tcp://%s:%s\n' "$cloudflare_ip" "$EDEX_WEB_PORT"
    printf '  Cloudflare VNC  : tcp://%s:%s\n' "$cloudflare_ip" "$EDEX_VNC_PORT"
    printf '\n'
    printf 'Cloudflare browser path after tunnel is created:\n'
    printf '  https://<cloudflare-hostname>%s\n' "$novnc_path"
    printf '\n'
    printf 'LAN noVNC browser URLs:\n'

    local found_ip=0 ip_addr
    while IFS= read -r ip_addr; do
        [[ -n "$ip_addr" ]] || continue
        found_ip=1
        printf '  Browser: https://%s:%s%s\n' "$ip_addr" "$EDEX_WEB_PORT" "$novnc_path"
        printf '  Cloudflare: tcp://%s:%s\n' "$ip_addr" "$EDEX_WEB_PORT"
    done < <(container_ips)

    if [[ "$found_ip" -eq 0 ]]; then
        printf '  Browser: https://<server-ip>:%s%s\n' "$EDEX_WEB_PORT" "$novnc_path"
        printf '  Cloudflare: tcp://<server-ip>:%s\n' "$EDEX_WEB_PORT"
    fi

    printf '\n'
    printf 'Raw VNC client endpoint, local/private only:\n'
    printf '  127.0.0.1:%s\n' "$EDEX_VNC_PORT"
    printf '  Cloudflare: tcp://%s:%s\n' "$cloudflare_ip" "$EDEX_VNC_PORT"
    printf '\n'
    printf 'Status and diagnostics:\n'
    printf '  sudo systemctl status edex.service nginx\n'
    printf '  sudo check-edex-service.sh\n'
}

main() {
    need_root_or_reexec "$@"

    cd "$REPO_ROOT"

    if [[ ! -x scripts/install-edex-service-linux.sh ]]; then
        printf 'Missing installer: %s/scripts/install-edex-service-linux.sh\n' "$REPO_ROOT" >&2
        exit 1
    fi

    log "building and installing eDEX-UI Linux browser/VNC service"
    bash scripts/install-edex-service-linux.sh

    log "waiting briefly for service listeners"
    sleep 3

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --no-pager --full status edex.service >/dev/null 2>&1 || true
        systemctl --no-pager --full status nginx >/dev/null 2>&1 || true
    fi

    print_urls
}

main "$@"

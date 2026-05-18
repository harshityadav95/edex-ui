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

print_urls() {
    if command -v print-edex-access-urls.sh >/dev/null 2>&1; then
        print-edex-access-urls.sh "$ENV_FILE"
    elif [[ -x "$REPO_ROOT/scripts/print-edex-access-urls.sh" ]]; then
        "$REPO_ROOT/scripts/print-edex-access-urls.sh" "$ENV_FILE"
    else
        printf 'Missing URL helper: print-edex-access-urls.sh\n' >&2
    fi
}

print_cloudflare_tunnel_details() {
    if [[ -f "$ENV_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$ENV_FILE"
    fi

    : "${EDEX_WEB_PORT:=8443}"
    : "${EDEX_CLOUDFLARE_ORIGIN_HOST:=10.1.1.117}"
    : "${EDEX_PUBLIC_HOSTNAME:=<cloudflare-hostname>}"

    local origin="https://${EDEX_CLOUDFLARE_ORIGIN_HOST}:${EDEX_WEB_PORT}"
    local public_host="$EDEX_PUBLIC_HOSTNAME"
    public_host="${public_host#http://}"
    public_host="${public_host#https://}"
    public_host="${public_host%%/*}"
    [[ -n "$public_host" ]] || public_host="<cloudflare-hostname>"

    printf '\n== Cloudflare Tunnel Setup ==\n'
    printf 'Your working local browser URL:\n'
    printf '  %s/vnc.html?autoconnect=1&resize=remote&path=websockify\n' "$origin"
    printf '\n'
    printf 'Use this as the Cloudflare Tunnel origin service, without the /vnc.html path:\n'
    printf '  %s\n' "$origin"
    printf '\n'
    printf 'Cloudflare Zero Trust dashboard values:\n'
    printf '  Public hostname: %s\n' "$public_host"
    printf '  Service type   : HTTPS\n'
    printf '  Service URL    : %s:%s\n' "$EDEX_CLOUDFLARE_ORIGIN_HOST" "$EDEX_WEB_PORT"
    printf '  TLS setting    : No TLS Verify / Disable TLS verification = ON\n'
    printf '\n'
    printf 'Equivalent cloudflared config.yml ingress:\n'
    cat <<EOF
ingress:
  - hostname: ${public_host}
    service: ${origin}
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
    printf '\n'
    printf 'Open this after the tunnel DNS route is active:\n'
    printf '  https://%s/vnc.html?autoconnect=1&resize=remote&path=websockify\n' "$public_host"
    printf '\n'
    printf 'Do not use tcp:// for this browser noVNC page. tcp:// is only for raw VNC clients.\n'
    printf 'Keep forwarding only HTTPS port %s; do not expose 5901, 6080, or 3000-3006 publicly.\n' "$EDEX_WEB_PORT"
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
    print_cloudflare_tunnel_details
}

main "$@"

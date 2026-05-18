#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: render-edex-nginx-config.sh [template] [output] [env-file]

Renders deploy/linux/nginx-edex.conf placeholders into an Nginx server config.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_TEMPLATE="$REPO_ROOT/deploy/linux/nginx-edex.conf"
if [[ ! -f "$DEFAULT_TEMPLATE" && -f /opt/edex-ui/deploy/linux/nginx-edex.conf ]]; then
    DEFAULT_TEMPLATE=/opt/edex-ui/deploy/linux/nginx-edex.conf
fi

TEMPLATE="${1:-$DEFAULT_TEMPLATE}"
OUTPUT="${2:-/etc/nginx/sites-available/edex-ui}"
ENV_FILE="${3:-/etc/edex-ui/edex.env}"

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

: "${EDEX_WEB_PORT:=8443}"
: "${EDEX_NOVNC_HOST:=127.0.0.1}"
: "${EDEX_NOVNC_PORT:=6080}"
: "${EDEX_SSL_CERT:=/etc/ssl/certs/ssl-cert-snakeoil.pem}"
: "${EDEX_SSL_KEY:=/etc/ssl/private/ssl-cert-snakeoil.key}"
: "${EDEX_HTPASSWD_FILE:=/etc/nginx/edex.htpasswd}"

validate_port() {
    local name="$1" value="$2"
    if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 || value > 65535 )); then
        printf 'Invalid %s: %s\n' "$name" "$value" >&2
        exit 2
    fi
}

validate_path() {
    local name="$1" value="$2"
    if [[ "$value" != /* ]]; then
        printf '%s must be an absolute path: %s\n' "$name" "$value" >&2
        exit 2
    fi
}

validate_port EDEX_WEB_PORT "$EDEX_WEB_PORT"
validate_port EDEX_NOVNC_PORT "$EDEX_NOVNC_PORT"
validate_path EDEX_SSL_CERT "$EDEX_SSL_CERT"
validate_path EDEX_SSL_KEY "$EDEX_SSL_KEY"
validate_path EDEX_HTPASSWD_FILE "$EDEX_HTPASSWD_FILE"

if [[ "$EDEX_NOVNC_HOST" != "127.0.0.1" && "$EDEX_NOVNC_HOST" != "localhost" ]]; then
    printf 'EDEX_NOVNC_HOST should stay loopback-only, got: %s\n' "$EDEX_NOVNC_HOST" >&2
    exit 2
fi

sed_replacement() {
    printf '%s' "$1" | sed 's/[&|\]/\\&/g'
}

mkdir -p "$(dirname "$OUTPUT")"
sed \
    -e "s|__EDEX_WEB_PORT__|$(sed_replacement "$EDEX_WEB_PORT")|g" \
    -e "s|__EDEX_NOVNC_HOST__|$(sed_replacement "$EDEX_NOVNC_HOST")|g" \
    -e "s|__EDEX_NOVNC_PORT__|$(sed_replacement "$EDEX_NOVNC_PORT")|g" \
    -e "s|__EDEX_SSL_CERT__|$(sed_replacement "$EDEX_SSL_CERT")|g" \
    -e "s|__EDEX_SSL_KEY__|$(sed_replacement "$EDEX_SSL_KEY")|g" \
    -e "s|__EDEX_HTPASSWD_FILE__|$(sed_replacement "$EDEX_HTPASSWD_FILE")|g" \
    "$TEMPLATE" > "$OUTPUT"

if grep -q '__EDEX_' "$OUTPUT"; then
    printf 'Unrendered placeholders remain in %s\n' "$OUTPUT" >&2
    exit 1
fi

#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_SERVICE_DIR="${HOME}/Library/Application Support/eDEX-UI-Service"
ENV_FILE="${EDEX_ENV_FILE:-${DEFAULT_SERVICE_DIR}/edex.env}"

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

load_defaults() {
    : "${EDEX_SERVICE_DIR:=${DEFAULT_SERVICE_DIR}}"
    : "${EDEX_APP_DIR:=${EDEX_SERVICE_DIR}/app}"
    : "${EDEX_HOME:=${EDEX_SERVICE_DIR}/home}"
    : "${EDEX_LOG_DIR:=${HOME}/Library/Logs/eDEX-UI-Service}"
    : "${EDEX_WEB_HOST:=0.0.0.0}"
    : "${EDEX_WEB_PORT:=6080}"
    : "${EDEX_MAC_VNC_HOST:=127.0.0.1}"
    : "${EDEX_MAC_VNC_PORT:=5900}"
    : "${EDEX_NOVNC_DIR:=${EDEX_SERVICE_DIR}/noVNC}"
    : "${EDEX_PYTHON_VENV:=${EDEX_SERVICE_DIR}/venv}"
    : "${EDEX_NODE_ENV:=production}"
    : "${EDEX_ELECTRON_FLAGS:=--nointro}"
    : "${EDEX_SETUP_RETRY_SECONDS:=60}"
}

log() {
    printf '[edex-darwin-session] %s\n' "$*"
}

cleanup() {
    local code=$?
    local pids
    log "stopping child processes"
    pids="$(jobs -pr || true)"
    if [[ -n "$pids" ]]; then
        kill $pids 2>/dev/null || true
    fi
    wait 2>/dev/null || true
    exit "$code"
}
trap cleanup EXIT INT TERM

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        log "missing required command: $1"
        exit 127
    }
}

screen_sharing_ready() {
    if command -v nc >/dev/null 2>&1; then
        nc -z "$EDEX_MAC_VNC_HOST" "$EDEX_MAC_VNC_PORT" >/dev/null 2>&1
        return
    fi

    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$EDEX_MAC_VNC_PORT" -sTCP:LISTEN >/dev/null 2>&1
        return
    fi

    return 1
}

print_screen_sharing_help() {
    cat <<EOF
[edex-darwin-session] macOS Screen Sharing is not listening on ${EDEX_MAC_VNC_HOST}:${EDEX_MAC_VNC_PORT}.
[edex-darwin-session] Enable it manually:
[edex-darwin-session]   1. Open System Settings.
[edex-darwin-session]   2. Open General > Sharing.
[edex-darwin-session]   3. Enable Screen Sharing.
[edex-darwin-session]   4. Open Screen Sharing settings / Computer Settings.
[edex-darwin-session]   5. Enable "VNC viewers may control screen with password".
[edex-darwin-session]   6. Set a dedicated VNC password, then start eDEX Service again.
EOF
}

start_edex() {
    if [[ ! -d "$EDEX_APP_DIR/src" ]]; then
        log "missing eDEX app directory: ${EDEX_APP_DIR}"
        exit 1
    fi

    require_cmd pnpm

    install -d -m 0755 "$EDEX_HOME" "$EDEX_LOG_DIR"
    log "starting eDEX-UI from ${EDEX_APP_DIR}"
    cd "$EDEX_APP_DIR"
    export HOME="$EDEX_HOME"
    export NODE_ENV="$EDEX_NODE_ENV"
    # shellcheck disable=SC2086
    pnpm run start -- $EDEX_ELECTRON_FLAGS &
}

start_novnc() {
    local novnc_proxy="${EDEX_NOVNC_DIR}/utils/novnc_proxy"

    if [[ ! -x "$novnc_proxy" ]]; then
        log "missing noVNC proxy: ${novnc_proxy}"
        exit 127
    fi

    if [[ -d "$EDEX_PYTHON_VENV/bin" ]]; then
        export PATH="${EDEX_PYTHON_VENV}/bin:${PATH}"
    fi

    require_cmd websockify

    log "starting noVNC on ${EDEX_WEB_HOST}:${EDEX_WEB_PORT}, targeting ${EDEX_MAC_VNC_HOST}:${EDEX_MAC_VNC_PORT}"
    cd "$EDEX_NOVNC_DIR"
    "$novnc_proxy" \
        --listen "${EDEX_WEB_HOST}:${EDEX_WEB_PORT}" \
        --vnc "${EDEX_MAC_VNC_HOST}:${EDEX_MAC_VNC_PORT}" &
}

main() {
    load_defaults
    install -d -m 0755 "$EDEX_LOG_DIR"

    if ! screen_sharing_ready; then
        print_screen_sharing_help
        sleep "$EDEX_SETUP_RETRY_SECONDS"
        exit 78
    fi

    start_edex
    sleep 3
    start_novnc

    log "service ready; keeping session alive"
    wait -n
}

main "$@"

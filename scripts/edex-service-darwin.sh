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
    : "${EDEX_LOG_DIR:=${HOME}/Library/Logs/eDEX-UI-Service}"
    : "${EDEX_LAUNCH_AGENT_DIR:=${HOME}/Library/LaunchAgents}"
    : "${EDEX_SESSION_LABEL:=com.edex-ui.session}"
    : "${EDEX_CONTROLLER_LABEL:=com.edex-ui.controller}"
    : "${EDEX_SERVICE_CLI:=${EDEX_SERVICE_DIR}/bin/edex-service-darwin.sh}"
    : "${EDEX_WEB_PORT:=6080}"
    : "${EDEX_MAC_VNC_HOST:=127.0.0.1}"
    : "${EDEX_MAC_VNC_PORT:=5900}"
}

usage() {
    cat <<EOF
Usage: edex-service-darwin.sh <command>

Commands:
  start        Enable and start the eDEX macOS service LaunchAgent.
  stop         Disable and stop the eDEX macOS service LaunchAgent.
  restart      Restart the eDEX macOS service LaunchAgent.
  status       Print service status.
  check        Print setup, listener, LaunchAgent, and URL details.
  urls         Print local and LAN browser URLs.
  local-url    Print only the local browser URL.
  lan-url      Print only the first LAN browser URL.
  controller   Run the eDEX menu-bar controller.
EOF
}

launch_domain() {
    printf 'gui/%s' "$(id -u)"
}

session_target() {
    printf '%s/%s' "$(launch_domain)" "$EDEX_SESSION_LABEL"
}

controller_target() {
    printf '%s/%s' "$(launch_domain)" "$EDEX_CONTROLLER_LABEL"
}

session_plist() {
    printf '%s/%s.plist' "$EDEX_LAUNCH_AGENT_DIR" "$EDEX_SESSION_LABEL"
}

controller_plist() {
    printf '%s/%s.plist' "$EDEX_LAUNCH_AGENT_DIR" "$EDEX_CONTROLLER_LABEL"
}

is_bootstrapped() {
    local target="$1"
    command -v launchctl >/dev/null 2>&1 && launchctl print "$target" >/dev/null 2>&1
}

bootstrap_if_needed() {
    local label="$1" plist="$2" target
    target="$(launch_domain)/${label}"

    if is_bootstrapped "$target"; then
        launchctl kickstart -k "$target"
        return
    fi

    launchctl bootstrap "$(launch_domain)" "$plist"
}

start_service() {
    local plist
    plist="$(session_plist)"
    if [[ ! -f "$plist" ]]; then
        printf 'Missing LaunchAgent plist: %s\nRun scripts/install-edex-service-darwin.sh first.\n' "$plist" >&2
        exit 1
    fi

    launchctl enable "$(session_target)" || true
    bootstrap_if_needed "$EDEX_SESSION_LABEL" "$plist"
}

stop_service() {
    launchctl disable "$(session_target)" || true
    if is_bootstrapped "$(session_target)"; then
        launchctl bootout "$(session_target)" || launchctl bootout "$(launch_domain)" "$(session_plist)" || true
    fi
}

restart_service() {
    stop_service
    start_service
}

status_service() {
    if is_bootstrapped "$(session_target)"; then
        printf 'running\n'
    else
        printf 'stopped\n'
    fi
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

urls() {
    "${EDEX_SERVICE_DIR}/bin/print-edex-access-urls-darwin.sh" "$ENV_FILE"
}

local_url() {
    "${EDEX_SERVICE_DIR}/bin/print-edex-access-urls-darwin.sh" "$ENV_FILE" local-url
}

lan_url() {
    "${EDEX_SERVICE_DIR}/bin/print-edex-access-urls-darwin.sh" "$ENV_FILE" lan-url
}

check_service() {
    printf '\n== Configuration ==\n'
    printf 'Service dir: %s\n' "$EDEX_SERVICE_DIR"
    printf 'App dir    : %s\n' "$EDEX_APP_DIR"
    printf 'Log dir    : %s\n' "$EDEX_LOG_DIR"
    printf 'Status     : %s\n' "$(status_service)"

    printf '\n== Screen Sharing ==\n'
    if screen_sharing_ready; then
        printf 'macOS Screen Sharing is listening on %s:%s.\n' "$EDEX_MAC_VNC_HOST" "$EDEX_MAC_VNC_PORT"
    else
        printf 'macOS Screen Sharing is not listening on %s:%s.\n' "$EDEX_MAC_VNC_HOST" "$EDEX_MAC_VNC_PORT"
        printf 'Enable Screen Sharing and "VNC viewers may control screen with password" in System Settings.\n'
    fi

    printf '\n== LaunchAgents ==\n'
    printf 'Session plist   : %s\n' "$(session_plist)"
    printf 'Controller plist: %s\n' "$(controller_plist)"
    if command -v launchctl >/dev/null 2>&1; then
        launchctl print "$(session_target)" 2>/dev/null | sed -n '1,30p' || true
    else
        printf 'launchctl is not available on this host.\n'
    fi

    printf '\n== Listeners ==\n'
    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"$EDEX_WEB_PORT" -sTCP:LISTEN 2>/dev/null || true
        lsof -nP -iTCP:"$EDEX_MAC_VNC_PORT" -sTCP:LISTEN 2>/dev/null || true
    else
        printf 'lsof is not available.\n'
    fi

    urls
}

run_controller() {
    local electron_bin="${EDEX_APP_DIR}/node_modules/.bin/electron"
    local controller_entry="${EDEX_APP_DIR}/src/darwin-service-controller.js"

    if [[ ! -x "$electron_bin" ]]; then
        printf 'Missing Electron binary: %s\nRun scripts/install-edex-service-darwin.sh first.\n' "$electron_bin" >&2
        exit 127
    fi

    if [[ ! -f "$controller_entry" ]]; then
        printf 'Missing controller entry: %s\n' "$controller_entry" >&2
        exit 1
    fi

    export EDEX_ENV_FILE="$ENV_FILE"
    export EDEX_SERVICE_DIR
    export EDEX_SERVICE_CLI
    cd "$EDEX_APP_DIR"
    exec "$electron_bin" "$controller_entry"
}

main() {
    load_defaults
    local command="${1:-}"

    case "$command" in
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        status)
            status_service
            ;;
        check)
            check_service
            ;;
        urls)
            urls
            ;;
        local-url)
            local_url
            ;;
        lan-url)
            lan_url
            ;;
        controller)
            run_controller
            ;;
        -h|--help|help|'')
            usage
            ;;
        *)
            printf 'Unknown command: %s\n' "$command" >&2
            usage >&2
            exit 2
            ;;
    esac
}

main "$@"

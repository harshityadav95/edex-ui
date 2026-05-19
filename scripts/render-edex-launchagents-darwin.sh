#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_DIR="${1:-$REPO_ROOT/deploy/darwin}"
OUTPUT_DIR="${2:-${HOME}/Library/LaunchAgents}"
ENV_FILE="${3:-${HOME}/Library/Application Support/eDEX-UI-Service/edex.env}"

if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

: "${EDEX_SERVICE_DIR:=${HOME}/Library/Application Support/eDEX-UI-Service}"
: "${EDEX_LOG_DIR:=${HOME}/Library/Logs/eDEX-UI-Service}"
: "${EDEX_SESSION_LABEL:=com.edex-ui.session}"
: "${EDEX_CONTROLLER_LABEL:=com.edex-ui.controller}"
: "${EDEX_SESSION_RUNNER:=${EDEX_SERVICE_DIR}/bin/run-edex-session-darwin.sh}"
: "${EDEX_SERVICE_CLI:=${EDEX_SERVICE_DIR}/bin/edex-service-darwin.sh}"

xml_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    value="${value//\"/&quot;}"
    printf '%s' "$value"
}

sed_escape() {
    printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

render_one() {
    local template="$1"
    local output="$2"
    local session_label controller_label session_runner service_cli log_dir

    session_label="$(sed_escape "$(xml_escape "$EDEX_SESSION_LABEL")")"
    controller_label="$(sed_escape "$(xml_escape "$EDEX_CONTROLLER_LABEL")")"
    session_runner="$(sed_escape "$(xml_escape "$EDEX_SESSION_RUNNER")")"
    service_cli="$(sed_escape "$(xml_escape "$EDEX_SERVICE_CLI")")"
    log_dir="$(sed_escape "$(xml_escape "$EDEX_LOG_DIR")")"

    sed \
        -e "s|__EDEX_SESSION_LABEL__|${session_label}|g" \
        -e "s|__EDEX_CONTROLLER_LABEL__|${controller_label}|g" \
        -e "s|__EDEX_SESSION_RUNNER__|${session_runner}|g" \
        -e "s|__EDEX_SERVICE_CLI__|${service_cli}|g" \
        -e "s|__EDEX_LOG_DIR__|${log_dir}|g" \
        "$template" > "$output"
}

install -d -m 0755 "$OUTPUT_DIR"
render_one \
    "$TEMPLATE_DIR/com.edex-ui.session.plist" \
    "$OUTPUT_DIR/${EDEX_SESSION_LABEL}.plist"
render_one \
    "$TEMPLATE_DIR/com.edex-ui.controller.plist" \
    "$OUTPUT_DIR/${EDEX_CONTROLLER_LABEL}.plist"

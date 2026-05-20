#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
    printf '[edex-darwin-install] %s\n' "$*"
}

need_macos_user() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        printf 'This installer is for macOS only.\n' >&2
        exit 1
    fi

    if [[ "${EUID}" -eq 0 ]]; then
        printf 'Run this macOS installer as the logged-in user, not with sudo.\n' >&2
        exit 1
    fi
}

load_defaults() {
    : "${EDEX_SERVICE_DIR:=${HOME}/Library/Application Support/eDEX-UI-Service}"
    : "${EDEX_APP_DIR:=${EDEX_SERVICE_DIR}/app}"
    : "${EDEX_HOME:=${EDEX_SERVICE_DIR}/home}"
    : "${EDEX_LOG_DIR:=${HOME}/Library/Logs/eDEX-UI-Service}"
    : "${EDEX_LAUNCH_AGENT_DIR:=${HOME}/Library/LaunchAgents}"
    : "${EDEX_ENV_FILE:=${EDEX_SERVICE_DIR}/edex.env}"
    : "${EDEX_NOVNC_VERSION:=v1.7.0}"
    : "${EDEX_WEBSOCKIFY_VERSION:=0.13.0}"
    : "${EDEX_NOVNC_DIR:=${EDEX_SERVICE_DIR}/noVNC}"
    : "${EDEX_PYTHON_VENV:=${EDEX_SERVICE_DIR}/venv}"
    : "${EDEX_MAC_VNC_HOST:=127.0.0.1}"
    : "${EDEX_MAC_VNC_PORT:=5900}"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'Missing required command: %s\n' "$1" >&2
        exit 127
    }
}

ensure_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        printf 'Homebrew is required for the macOS service dependencies.\n' >&2
        printf 'Install it from https://brew.sh, then rerun this installer.\n' >&2
        exit 1
    fi
}

install_brew_dependencies() {
    local packages=(node pnpm python)
    log "installing Homebrew dependencies: ${packages[*]}"
    brew install "${packages[@]}"
}

install_directories() {
    install -d -m 0755 \
        "$EDEX_SERVICE_DIR" \
        "$EDEX_APP_DIR" \
        "$EDEX_HOME" \
        "$EDEX_LOG_DIR" \
        "$EDEX_LAUNCH_AGENT_DIR" \
        "$EDEX_SERVICE_DIR/bin"
}

install_env_file() {
    if [[ -f "$EDEX_ENV_FILE" ]]; then
        log "keeping existing config at ${EDEX_ENV_FILE}"
        return
    fi

    install -m 0644 "$REPO_ROOT/deploy/darwin/edex.env" "$EDEX_ENV_FILE"
}

install_scripts() {
    install -m 0755 "$REPO_ROOT/scripts/run-edex-session-darwin.sh" "$EDEX_SERVICE_DIR/bin/run-edex-session-darwin.sh"
    install -m 0755 "$REPO_ROOT/scripts/edex-service-darwin.sh" "$EDEX_SERVICE_DIR/bin/edex-service-darwin.sh"
    install -m 0755 "$REPO_ROOT/scripts/print-edex-access-urls-darwin.sh" "$EDEX_SERVICE_DIR/bin/print-edex-access-urls-darwin.sh"
    install -m 0755 "$REPO_ROOT/scripts/render-edex-launchagents-darwin.sh" "$EDEX_SERVICE_DIR/bin/render-edex-launchagents-darwin.sh"
}

install_app_source() {
    log "installing app source to ${EDEX_APP_DIR}"
    rsync -a --delete \
        --exclude .git \
        --exclude node_modules \
        --exclude src/node_modules \
        --exclude dist \
        --exclude prebuild-src \
        "$REPO_ROOT"/ "$EDEX_APP_DIR"/
}

build_app() {
    log "building eDEX-UI for macOS"
    cd "$EDEX_APP_DIR"
    pnpm config set fetch-retries 5
    pnpm config set fetch-retry-mintimeout 20000
    pnpm config set fetch-retry-maxtimeout 120000
    pnpm config set fetch-timeout 300000
    pnpm run install-darwin
}

install_websockify() {
    require_cmd python3

    log "installing websockify ${EDEX_WEBSOCKIFY_VERSION} into ${EDEX_PYTHON_VENV}"
    python3 -m venv "$EDEX_PYTHON_VENV"
    "$EDEX_PYTHON_VENV/bin/python" -m pip install --upgrade pip
    "$EDEX_PYTHON_VENV/bin/python" -m pip install "websockify==${EDEX_WEBSOCKIFY_VERSION}"
}

install_novnc() {
    local tmpdir archive extracted
    require_cmd curl
    require_cmd tar

    tmpdir="$(mktemp -d)"
    archive="$tmpdir/novnc.tar.gz"

    log "downloading noVNC ${EDEX_NOVNC_VERSION}"
    curl -fsSL \
        "https://github.com/novnc/noVNC/archive/refs/tags/${EDEX_NOVNC_VERSION}.tar.gz" \
        -o "$archive"
    tar -xzf "$archive" -C "$tmpdir"
    extracted="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -1)"
    if [[ -z "$extracted" ]]; then
        printf 'Unable to extract noVNC archive.\n' >&2
        rm -rf "$tmpdir"
        exit 1
    fi

    install -d -m 0755 "$EDEX_NOVNC_DIR"
    rsync -a --delete "$extracted"/ "$EDEX_NOVNC_DIR"/
    chmod +x "$EDEX_NOVNC_DIR/utils/novnc_proxy"
    rm -rf "$tmpdir"
}

render_launch_agents() {
    log "rendering LaunchAgents"
    "$REPO_ROOT/scripts/render-edex-launchagents-darwin.sh" \
        "$REPO_ROOT/deploy/darwin" \
        "$EDEX_LAUNCH_AGENT_DIR" \
        "$EDEX_ENV_FILE"

    if command -v plutil >/dev/null 2>&1; then
        plutil -lint \
            "$EDEX_LAUNCH_AGENT_DIR/com.edex-ui.session.plist" \
            "$EDEX_LAUNCH_AGENT_DIR/com.edex-ui.controller.plist"
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

print_screen_sharing_help() {
    cat <<EOF

== Manual macOS Screen Sharing setup required ==
The service uses native macOS Screen Sharing as the VNC source.

Open System Settings:
  1. General > Sharing.
  2. Enable Screen Sharing.
  3. Open Screen Sharing settings / Computer Settings.
  4. Enable "VNC viewers may control screen with password".
  5. Set a dedicated VNC password.

After that, start the service from the eDEX top-bar menu or run:
  "${EDEX_SERVICE_DIR}/bin/edex-service-darwin.sh" start

EOF
}

bootstrap_controller() {
    local domain="gui/$(id -u)"
    local target="${domain}/com.edex-ui.controller"
    local plist="${EDEX_LAUNCH_AGENT_DIR}/com.edex-ui.controller.plist"

    if ! command -v launchctl >/dev/null 2>&1; then
        log "launchctl is unavailable; skipping LaunchAgent bootstrap"
        return
    fi

    launchctl enable "$target" || true
    if launchctl print "$target" >/dev/null 2>&1; then
        launchctl kickstart -k "$target" || true
    else
        launchctl bootstrap "$domain" "$plist" || true
    fi
}

start_session_if_ready() {
    if ! command -v launchctl >/dev/null 2>&1; then
        return
    fi

    if ! screen_sharing_ready; then
        launchctl disable "gui/$(id -u)/com.edex-ui.session" || true
        print_screen_sharing_help
        return
    fi

    "$EDEX_SERVICE_DIR/bin/edex-service-darwin.sh" start
}

main() {
    need_macos_user
    load_defaults
    ensure_homebrew
    install_brew_dependencies
    install_directories
    install_env_file
    install_scripts
    install_app_source
    build_app
    install_websockify
    install_novnc
    render_launch_agents
    bootstrap_controller
    start_session_if_ready
    "$EDEX_SERVICE_DIR/bin/print-edex-access-urls-darwin.sh" "$EDEX_ENV_FILE" || true
    log "done"
}

main "$@"

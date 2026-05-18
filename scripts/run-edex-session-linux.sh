#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    printf '[edex-session] %s\n' "$*"
}

cleanup() {
    local code=$?
    log "stopping child processes"
    jobs -pr | xargs -r kill 2>/dev/null || true
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

load_defaults() {
    : "${EDEX_APP_DIR:=/opt/edex-ui}"
    : "${EDEX_HOME:=/var/lib/edex-ui}"
    : "${EDEX_DISPLAY:=:1}"
    : "${EDEX_RESOLUTION:=1600x900}"
    : "${EDEX_DEPTH:=24}"
    : "${EDEX_DISPLAY_BACKEND:=auto}"
    : "${EDEX_VNC_STACK:=novnc}"
    : "${EDEX_VNC_PORT:=5901}"
    : "${EDEX_RAW_VNC_HOST:=127.0.0.1}"
    : "${EDEX_VNC_PASSWORD_FILE:=}"
    : "${EDEX_VNC_PASSWORD:=}"
    : "${EDEX_NOVNC_HOST:=127.0.0.1}"
    : "${EDEX_NOVNC_PORT:=6080}"
    : "${EDEX_ELECTRON_FLAGS:=--no-sandbox}"
    : "${EDEX_DISABLE_AUDIO:=false}"
    : "${EDEX_THEME:=tron}"
}

display_number() {
    printf '%s' "${EDEX_DISPLAY#:}"
}

start_xorg_dummy() {
    require_cmd Xorg

    local display_num
    display_num="$(display_number)"
    local width="${EDEX_RESOLUTION%x*}"
    local height="${EDEX_RESOLUTION#*x}"
    local xorg_conf="${XDG_RUNTIME_DIR:-/tmp}/edex-xorg-dummy.conf"

    cat > "$xorg_conf" <<EOF
Section "Device"
    Identifier "DummyDevice"
    Driver "dummy"
    VideoRam 256000
EndSection

Section "Monitor"
    Identifier "DummyMonitor"
    HorizSync 28.0-80.0
    VertRefresh 48.0-75.0
    Modeline "${EDEX_RESOLUTION}" 172.80 ${width} 2040 2248 2576 ${height} 1081 1084 1118
EndSection

Section "Screen"
    Identifier "DummyScreen"
    Device "DummyDevice"
    Monitor "DummyMonitor"
    DefaultDepth ${EDEX_DEPTH}
    SubSection "Display"
        Depth ${EDEX_DEPTH}
        Modes "${EDEX_RESOLUTION}"
    EndSubSection
EndSection
EOF

    log "starting Xorg dummy display ${EDEX_DISPLAY} at ${EDEX_RESOLUTION}x${EDEX_DEPTH}"
    Xorg "$EDEX_DISPLAY" -noreset -nolisten tcp -config "$xorg_conf" &
    DISPLAY_PID=$!
}

start_xvfb() {
    require_cmd Xvfb
    log "starting Xvfb display ${EDEX_DISPLAY} at ${EDEX_RESOLUTION}x${EDEX_DEPTH}"
    Xvfb "$EDEX_DISPLAY" -screen 0 "${EDEX_RESOLUTION}x${EDEX_DEPTH}" -nolisten tcp &
    DISPLAY_PID=$!
}

display_is_alive() {
    [[ -n "${DISPLAY_PID:-}" ]] && kill -0 "$DISPLAY_PID" >/dev/null 2>&1
}

start_display() {
    case "$EDEX_DISPLAY_BACKEND" in
        xorg-dri)
            start_xorg_dummy
            ;;
        xvfb)
            start_xvfb
            ;;
        auto)
            if [[ -e /dev/dri/renderD128 ]] && command -v Xorg >/dev/null 2>&1; then
                start_xorg_dummy
                sleep 2
                if ! display_is_alive; then
                    log "Xorg dummy did not stay running; falling back to Xvfb"
                    start_xvfb
                fi
            else
                start_xvfb
            fi
            ;;
        *)
            log "invalid EDEX_DISPLAY_BACKEND=${EDEX_DISPLAY_BACKEND}"
            exit 2
            ;;
    esac

    sleep 2
    if ! display_is_alive; then
        log "display server failed to start"
        exit 1
    fi
}

start_window_manager() {
    if command -v openbox-session >/dev/null 2>&1; then
        log "starting openbox"
        DISPLAY="$EDEX_DISPLAY" openbox-session &
    elif command -v openbox >/dev/null 2>&1; then
        log "starting openbox"
        DISPLAY="$EDEX_DISPLAY" openbox &
    else
        log "openbox is not installed"
        exit 127
    fi
    sleep 1
}

write_edex_settings_overrides() {
    mkdir -p "$EDEX_HOME/.config/eDEX-UI"

    local settings_file="$EDEX_HOME/.config/eDEX-UI/settings.json"
    if [[ -f "$settings_file" ]]; then
        return
    fi

    cat > "$settings_file" <<EOF
{
    "shell": "bash",
    "shellArgs": "",
    "cwd": "${EDEX_HOME}",
    "keyboard": "en-US",
    "theme": "${EDEX_THEME}",
    "termFontSize": 15,
    "audio": $([[ "$EDEX_DISABLE_AUDIO" == "true" ]] && printf 'false' || printf 'true'),
    "audioVolume": 1.0,
    "disableFeedbackAudio": false,
    "clockHours": 24,
    "pingAddr": "1.1.1.1",
    "port": 3000,
    "nointro": true,
    "nocursor": false,
    "forceFullscreen": true,
    "allowWindowed": false,
    "excludeThreadsFromToplist": true,
    "hideDotfiles": false,
    "fsListView": false,
    "experimentalGlobeFeatures": false,
    "experimentalFeatures": false
}
EOF
}

start_edex() {
    require_cmd npm
    log "starting eDEX-UI from ${EDEX_APP_DIR}"
    cd "$EDEX_APP_DIR"
    export DISPLAY="$EDEX_DISPLAY"
    export HOME="$EDEX_HOME"
    export NODE_ENV="${EDEX_NODE_ENV:-production}"
    write_edex_settings_overrides
    npm run start -- $EDEX_ELECTRON_FLAGS &
}

start_kasmvnc() {
    if ! command -v kasmvncserver >/dev/null 2>&1; then
        return 1
    fi

    if [[ ! -f "$EDEX_HOME/.kasmpasswd" ]]; then
        log "KasmVNC is installed but ${EDEX_HOME}/.kasmpasswd is missing"
        return 1
    fi

    log "starting KasmVNC on ${EDEX_DISPLAY}, web port ${EDEX_NOVNC_PORT}, vnc port ${EDEX_VNC_PORT}"
    kasmvncserver "$EDEX_DISPLAY" \
        -geometry "$EDEX_RESOLUTION" \
        -depth "$EDEX_DEPTH" \
        -websocketPort "$EDEX_NOVNC_PORT" \
        -rfbport "$EDEX_VNC_PORT" \
        -interface "$EDEX_NOVNC_HOST" \
        -SecurityTypes VncAuth &
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

write_vnc_password_file() {
    local password_file="${EDEX_HOME}/.vnc/passwd"
    install -d -m 0700 "${EDEX_HOME}/.vnc"
    x11vnc -storepasswd "$EDEX_VNC_PASSWORD" "$password_file" >/dev/null
    chmod 0600 "$password_file"
    printf '%s' "$password_file"
}

vnc_auth_args() {
    if [[ -n "$EDEX_VNC_PASSWORD_FILE" ]]; then
        if [[ ! -f "$EDEX_VNC_PASSWORD_FILE" ]]; then
            log "EDEX_VNC_PASSWORD_FILE does not exist: ${EDEX_VNC_PASSWORD_FILE}"
            exit 1
        fi
        VNC_AUTH_ARGS=(-rfbauth "$EDEX_VNC_PASSWORD_FILE")
        return
    fi

    if [[ -n "$EDEX_VNC_PASSWORD" ]]; then
        VNC_AUTH_ARGS=(-rfbauth "$(write_vnc_password_file)")
        return
    fi

    if is_loopback_host "$EDEX_RAW_VNC_HOST"; then
        VNC_AUTH_ARGS=(-nopw)
        return
    fi

    log "refusing to expose raw VNC on ${EDEX_RAW_VNC_HOST}:${EDEX_VNC_PORT} without EDEX_VNC_PASSWORD_FILE or EDEX_VNC_PASSWORD"
    exit 1
}

start_novnc_fallback() {
    require_cmd x11vnc

    local novnc_proxy=""
    if command -v novnc_proxy >/dev/null 2>&1; then
        novnc_proxy="$(command -v novnc_proxy)"
    elif [[ -x /usr/share/novnc/utils/novnc_proxy ]]; then
        novnc_proxy=/usr/share/novnc/utils/novnc_proxy
    else
        log "missing noVNC proxy"
        exit 127
    fi

    local vnc_bind_args=()
    local vnc_proxy_host="127.0.0.1"
    if is_loopback_host "$EDEX_RAW_VNC_HOST"; then
        vnc_bind_args=(-localhost)
    else
        vnc_bind_args=(-listen "$EDEX_RAW_VNC_HOST")
        if [[ "$EDEX_RAW_VNC_HOST" != "0.0.0.0" ]]; then
            vnc_proxy_host="$EDEX_RAW_VNC_HOST"
        fi
    fi

    local VNC_AUTH_ARGS=()
    vnc_auth_args

    log "starting x11vnc on ${EDEX_RAW_VNC_HOST}:${EDEX_VNC_PORT}"
    x11vnc -display "$EDEX_DISPLAY" \
        -forever -shared "${vnc_bind_args[@]}" \
        -rfbport "$EDEX_VNC_PORT" \
        "${VNC_AUTH_ARGS[@]}" -xkb -repeat &

    sleep 1

    log "starting noVNC on ${EDEX_NOVNC_HOST}:${EDEX_NOVNC_PORT}"
    "$novnc_proxy" \
        --listen "${EDEX_NOVNC_HOST}:${EDEX_NOVNC_PORT}" \
        --vnc "${vnc_proxy_host}:${EDEX_VNC_PORT}" &
}

start_vnc_stack() {
    case "$EDEX_VNC_STACK" in
        kasm)
            start_kasmvnc || {
                log "EDEX_VNC_STACK=kasm requested, but KasmVNC could not start"
                exit 1
            }
            ;;
        novnc)
            start_novnc_fallback
            ;;
        auto)
            if start_kasmvnc; then
                return
            fi
            start_novnc_fallback
            ;;
        *)
            log "invalid EDEX_VNC_STACK=${EDEX_VNC_STACK}"
            exit 2
            ;;
    esac
}

main() {
    load_defaults
    mkdir -p "$EDEX_HOME"
    start_display
    start_window_manager
    start_edex
    sleep 3
    start_vnc_stack

    log "service ready; keeping session alive"
    wait -n
}

main "$@"

#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
    printf '[edex-install] %s\n' "$*"
}

need_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        printf 'Run as root: sudo %s\n' "$0" >&2
        exit 1
    fi
}

apt_install() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y "$@"
}

install_node22_if_needed() {
    local major=0
    if command -v node >/dev/null 2>&1; then
        major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || printf 0)"
    fi

    if [[ "$major" -ge 22 ]]; then
        log "Node.js $(node --version) is already installed"
        return
    fi

    log "installing Node.js 22.x"
    apt-get install -y ca-certificates curl gnupg
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list
    apt-get update
    apt-get install -y nodejs
}

create_service_user() {
    if ! id edex >/dev/null 2>&1; then
        log "creating edex service user"
        useradd --system --create-home --home-dir /var/lib/edex-ui --shell /bin/bash edex
    fi

    install -d -o edex -g edex -m 0755 /var/lib/edex-ui
    install -d -o root -g root -m 0755 /etc/edex-ui
}

install_app_source() {
    log "installing app source to /opt/edex-ui"
    install -d -o edex -g edex -m 0755 /opt/edex-ui
    rsync -a --delete \
        --exclude .git \
        --exclude node_modules \
        --exclude src/node_modules \
        --exclude dist \
        "$REPO_ROOT"/ /opt/edex-ui/
    chown -R edex:edex /opt/edex-ui
}

build_app() {
    log "building eDEX-UI from source"
    sudo -u edex -H bash -lc 'cd /opt/edex-ui && npm run install-linux'
}

install_deployment_files() {
    log "installing service, runner, checker, and nginx config"
    install -m 0644 "$REPO_ROOT/deploy/linux/edex.env" /etc/edex-ui/edex.env
    install -m 0644 "$REPO_ROOT/deploy/linux/edex.service" /etc/systemd/system/edex.service
    install -m 0755 "$REPO_ROOT/scripts/run-edex-session-linux.sh" /usr/local/bin/run-edex-session-linux.sh
    install -m 0755 "$REPO_ROOT/scripts/check-edex-service.sh" /usr/local/bin/check-edex-service.sh
    install -m 0644 "$REPO_ROOT/deploy/linux/nginx-edex.conf" /etc/nginx/sites-available/edex-ui

    ln -sfn /etc/nginx/sites-available/edex-ui /etc/nginx/sites-enabled/edex-ui
    rm -f /etc/nginx/sites-enabled/default
}

create_web_credentials() {
    local user="${EDEX_WEB_USER:-edex}"
    local password="${EDEX_WEB_PASSWORD:-}"

    if [[ -z "$password" && -t 0 ]]; then
        read -r -s -p "Password for web user '${user}': " password
        printf '\n'
    fi

    if [[ -z "$password" ]]; then
        password="$(openssl rand -base64 24)"
        log "generated web password for ${user}: ${password}"
    fi

    htpasswd -Bbc /etc/nginx/edex.htpasswd "$user" "$password"
    chmod 0640 /etc/nginx/edex.htpasswd
    chown root:www-data /etc/nginx/edex.htpasswd
}

enable_services() {
    log "validating nginx and enabling services"
    nginx -t
    systemctl daemon-reload
    systemctl enable --now nginx
    systemctl enable --now edex.service
}

main() {
    need_root
    apt_install \
        ca-certificates curl gnupg git rsync sudo openssl \
        build-essential python3 make g++ pkg-config \
        xserver-xorg-core xserver-xorg-video-dummy xvfb openbox dbus-x11 \
        x11vnc novnc websockify nginx apache2-utils ssl-cert \
        libasound2 libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libgbm1 \
        libgtk-3-0 libnss3 libx11-xcb1 libxcomposite1 libxcursor1 \
        libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 \
        libxshmfence1 libxss1 libxtst6
    install_node22_if_needed
    create_service_user
    install_app_source
    build_app
    install_deployment_files
    create_web_credentials
    enable_services
    log "done. Open https://<container-ip>:8443/"
}

main "$@"


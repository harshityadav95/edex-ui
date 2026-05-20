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

need_debian_linux() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        printf 'This installer supports Debian/Ubuntu Linux only.\n' >&2
        exit 1
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        printf 'This installer requires apt-get and supports Debian/Ubuntu Linux only.\n' >&2
        exit 1
    fi

    local id="" id_like=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        id="${ID:-}"
        id_like="${ID_LIKE:-}"
    fi

    case " ${id} ${id_like} " in
        *" debian "*|*" ubuntu "*)
            return
            ;;
    esac

    printf 'This installer supports Debian/Ubuntu Linux only. Detected ID=%s ID_LIKE=%s.\n' "${id:-unknown}" "${id_like:-unknown}" >&2
    exit 1
}

apt_install() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y "$@"
}

apt_has_candidate() {
    local package="$1"
    [[ "$(apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ { print $2; exit }')" != "(none)" ]]
}

alsa_runtime_package() {
    if apt_has_candidate libasound2; then
        printf 'libasound2'
    elif apt_has_candidate libasound2t64; then
        printf 'libasound2t64'
    else
        printf 'libasound2'
    fi
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
    sudo -u edex -H bash -lc 'cd /opt/edex-ui && pnpm config set fetch-retries 5 && pnpm config set fetch-retry-mintimeout 20000 && pnpm config set fetch-retry-maxtimeout 120000 && pnpm config set fetch-timeout 300000 && pnpm run install-linux'
}

install_deployment_files() {
    log "installing service, runner, checker, and nginx config"
    install -m 0644 "$REPO_ROOT/deploy/linux/edex.env" /etc/edex-ui/edex.env
    install -m 0644 "$REPO_ROOT/deploy/linux/edex.service" /etc/systemd/system/edex.service
    install -m 0755 "$REPO_ROOT/scripts/run-edex-session-linux.sh" /usr/local/bin/run-edex-session-linux.sh
    install -m 0755 "$REPO_ROOT/scripts/check-edex-service.sh" /usr/local/bin/check-edex-service.sh
    install -m 0755 "$REPO_ROOT/scripts/render-edex-nginx-config.sh" /usr/local/bin/render-edex-nginx-config.sh
    install -m 0755 "$REPO_ROOT/scripts/print-edex-access-urls.sh" /usr/local/bin/print-edex-access-urls.sh
    /usr/local/bin/render-edex-nginx-config.sh \
        "$REPO_ROOT/deploy/linux/nginx-edex.conf" \
        /etc/nginx/sites-available/edex-ui \
        /etc/edex-ui/edex.env

    ln -sfn /etc/nginx/sites-available/edex-ui /etc/nginx/sites-enabled/edex-ui
    rm -f /etc/nginx/sites-enabled/default
}

create_web_credentials() {
    local user="${EDEX_WEB_USER:-edex}"
    local password="${EDEX_WEB_PASSWORD:-}"
    local htpasswd_file="${EDEX_HTPASSWD_FILE:-/etc/nginx/edex.htpasswd}"

    if [[ -z "$password" && -t 0 ]]; then
        read -r -s -p "Password for web user '${user}': " password
        printf '\n'
    fi

    if [[ -z "$password" ]]; then
        password="$(openssl rand -base64 24)"
        log "generated web password for ${user}: ${password}"
    fi

    install -d -m 0755 "$(dirname "$htpasswd_file")"
    htpasswd -Bbc "$htpasswd_file" "$user" "$password"
    chmod 0640 "$htpasswd_file"
    chown root:www-data "$htpasswd_file"
}

enable_services() {
    log "validating nginx and enabling services"
    nginx -t
    systemctl daemon-reload
    systemctl enable nginx
    systemctl reload-or-restart nginx
    systemctl enable --now edex.service
}

main() {
    need_debian_linux
    need_root
    local alsa_package
    alsa_package="$(alsa_runtime_package)"
    apt_install \
        ca-certificates curl gnupg git rsync sudo openssl \
        build-essential python3 make g++ pkg-config \
        xserver-xorg-core xserver-xorg-video-dummy xvfb openbox dbus-x11 \
        x11vnc novnc websockify nginx apache2-utils ssl-cert \
        "$alsa_package" libatk-bridge2.0-0 libatk1.0-0 libcups2 libdrm2 libgbm1 \
        libgtk-3-0 libnss3 libx11-xcb1 libxcomposite1 libxcursor1 \
        libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 \
        libxshmfence1 libxss1 libxtst6
    install_node22_if_needed
    if ! command -v pnpm >/dev/null 2>&1; then
        log "installing pnpm globally"
        npm install -g pnpm
    fi
    create_service_user
    install_app_source
    build_app
    install_deployment_files
    # shellcheck disable=SC1091
    source /etc/edex-ui/edex.env
    create_web_credentials
    enable_services
    /usr/local/bin/print-edex-access-urls.sh /etc/edex-ui/edex.env || true
    log "done"
}

main "$@"

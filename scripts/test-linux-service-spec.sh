#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

pass() {
    printf 'PASS: %s\n' "$*"
}

assert_file_contains() {
    local file="$1" pattern="$2" message="$3"
    grep -Eq -- "$pattern" "$file" || fail "$message"
}

assert_output_contains() {
    local output="$1" pattern="$2" message="$3"
    grep -Eq -- "$pattern" <<<"$output" || fail "$message"
}

tmpdir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmpdir"
}
trap cleanup EXIT

for script in \
    start.sh \
    scripts/install-edex-service-linux.sh \
    scripts/run-edex-session-linux.sh \
    scripts/check-edex-service.sh \
    scripts/render-edex-nginx-config.sh \
    scripts/print-edex-access-urls.sh \
    scripts/test-linux-service-spec.sh
do
    bash -n "$script"
done
pass "shell scripts parse"

bash scripts/render-edex-nginx-config.sh \
    deploy/linux/nginx-edex.conf \
    "$tmpdir/nginx.conf" \
    deploy/linux/edex.env

assert_file_contains "$tmpdir/nginx.conf" 'listen 8443 ssl;' 'rendered nginx config must listen on EDEX_WEB_PORT'
assert_file_contains "$tmpdir/nginx.conf" 'proxy_pass http://127\.0\.0\.1:6080/;' 'rendered nginx config must proxy root to loopback noVNC'
assert_file_contains "$tmpdir/nginx.conf" 'proxy_pass http://127\.0\.0\.1:6080/websockify;' 'rendered nginx config must proxy websocket path to noVNC'
assert_file_contains "$tmpdir/nginx.conf" 'auth_basic_user_file /etc/nginx/edex\.htpasswd;' 'rendered nginx config must use configured htpasswd file'
if grep -q '__EDEX_' "$tmpdir/nginx.conf"; then
    fail "rendered nginx config contains unresolved placeholders"
fi
pass "nginx template renders from env defaults"

custom_env="$tmpdir/custom.env"
cp deploy/linux/edex.env "$custom_env"
{
    printf '\nEDEX_WEB_PORT=9443\n'
    printf 'EDEX_NOVNC_PORT=6180\n'
    printf 'EDEX_SSL_CERT=/tmp/edex-test.crt\n'
    printf 'EDEX_SSL_KEY=/tmp/edex-test.key\n'
    printf 'EDEX_HTPASSWD_FILE=/tmp/edex-test.htpasswd\n'
} >> "$custom_env"

bash scripts/render-edex-nginx-config.sh \
    deploy/linux/nginx-edex.conf \
    "$tmpdir/nginx-custom.conf" \
    "$custom_env"
assert_file_contains "$tmpdir/nginx-custom.conf" 'listen 9443 ssl;' 'custom EDEX_WEB_PORT must be rendered'
assert_file_contains "$tmpdir/nginx-custom.conf" 'proxy_pass http://127\.0\.0\.1:6180/;' 'custom EDEX_NOVNC_PORT must be rendered'
pass "nginx template renders custom ports"

invalid_env="$tmpdir/invalid.env"
printf 'EDEX_WEB_PORT=70000\n' > "$invalid_env"
if bash scripts/render-edex-nginx-config.sh \
    deploy/linux/nginx-edex.conf \
    "$tmpdir/nginx-invalid.conf" \
    "$invalid_env" >/dev/null 2>&1
then
    fail "invalid ports must be rejected"
fi
pass "invalid nginx ports are rejected"

url_env="$tmpdir/url.env"
cp deploy/linux/edex.env "$url_env"
printf '\nEDEX_PUBLIC_HOSTNAME=edex.example.com\n' >> "$url_env"
url_output="$(EDEX_ACCESS_IPS='192.0.2.10' bash scripts/print-edex-access-urls.sh "$url_env")"
assert_output_contains "$url_output" 'LAN browser URL: https://192\.0\.2\.10:8443/vnc\.html\?autoconnect=1&resize=remote&path=websockify' 'LAN browser URL must include websocket path'
assert_output_contains "$url_output" 'Cloudflare browser origin: https://192\.0\.2\.10:8443' 'Cloudflare browser origin must use HTTPS LAN IP and web port'
assert_output_contains "$url_output" 'Cloudflare browser URL   : https://edex\.example\.com/vnc\.html\?autoconnect=1&resize=remote&path=websockify' 'Cloudflare browser URL must include noVNC path'
assert_output_contains "$url_output" 'originRequest\.noTLSVerify=true' 'Cloudflare output must mention self-signed origin TLS handling'
assert_output_contains "$url_output" 'Raw VNC       : 127\.0\.0\.1:5901' 'raw VNC output must remain loopback-only'
assert_output_contains "$url_output" 'Cloudflare raw VNC origin: disabled; raw VNC is loopback-only by default' 'raw VNC Cloudflare origin must be disabled by default'
pass "access URL output covers LAN and Cloudflare tunnel"

raw_vnc_env="$tmpdir/raw-vnc.env"
cp deploy/linux/edex.env "$raw_vnc_env"
{
    printf '\nEDEX_RAW_VNC_HOST=0.0.0.0\n'
    printf 'EDEX_VNC_PASSWORD_FILE=/tmp/edex-test-vnc.passwd\n'
} >> "$raw_vnc_env"
raw_vnc_output="$(EDEX_ACCESS_IPS='192.0.2.10' bash scripts/print-edex-access-urls.sh "$raw_vnc_env")"
assert_output_contains "$raw_vnc_output" 'Raw VNC       : 0\.0\.0\.0:5901' 'raw VNC private backend must show configured bind host'
assert_output_contains "$raw_vnc_output" 'Cloudflare raw VNC origin: tcp://192\.0\.2\.10:5901' 'enabled raw VNC origin must use LAN IP and VNC port'
pass "raw VNC Cloudflare output is opt-in"

assert_file_contains deploy/linux/edex.service '^User=edex$' 'systemd unit must run as the edex service user'
assert_file_contains deploy/linux/edex.service '^EnvironmentFile=/etc/edex-ui/edex\.env$' 'systemd unit must load /etc/edex-ui/edex.env'
assert_file_contains deploy/linux/edex.service '^ExecStart=/usr/local/bin/run-edex-session-linux\.sh$' 'systemd unit must execute the Linux session runner'
assert_file_contains scripts/run-edex-session-linux.sh '-localhost' 'x11vnc must bind raw VNC to localhost'
assert_file_contains scripts/run-edex-session-linux.sh 'EDEX_RAW_VNC_HOST' 'session runner must support explicit raw VNC bind host'
assert_file_contains scripts/run-edex-session-linux.sh 'refusing to expose raw VNC' 'session runner must reject unauthenticated LAN raw VNC'
assert_file_contains scripts/run-edex-session-linux.sh 'EDEX_VNC_PASSWORD_FILE' 'session runner must support password-protected raw VNC'
assert_file_contains scripts/run-edex-session-linux.sh '--listen "\$\{EDEX_NOVNC_HOST\}:\$\{EDEX_NOVNC_PORT\}"' 'noVNC must listen on configured noVNC host and port'
assert_file_contains scripts/run-edex-session-linux.sh '--vnc "\$\{vnc_proxy_host\}:\$\{EDEX_VNC_PORT\}"' 'noVNC must connect to the configured raw VNC listener'
assert_file_contains deploy/linux/edex.env '^EDEX_NOVNC_HOST=127\.0\.0\.1$' 'default noVNC backend must be loopback-only'
assert_file_contains deploy/linux/edex.env '^EDEX_RAW_VNC_HOST=127\.0\.0\.1$' 'default raw VNC backend must be loopback-only'
assert_file_contains deploy/linux/edex.env '^EDEX_VNC_STACK=novnc$' 'default VNC stack must be distro noVNC'
assert_file_contains start.sh 'print-edex-access-urls\.sh "\$ENV_FILE"' 'start.sh must use the shared URL helper'
pass "service spec uses loopback VNC/noVNC behind nginx"

printf '\nLinux service spec tests passed.\n'

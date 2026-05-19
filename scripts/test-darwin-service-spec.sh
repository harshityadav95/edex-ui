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
    scripts/install-edex-service-darwin.sh \
    scripts/run-edex-session-darwin.sh \
    scripts/edex-service-darwin.sh \
    scripts/print-edex-access-urls-darwin.sh \
    scripts/render-edex-launchagents-darwin.sh \
    scripts/test-darwin-service-spec.sh
do
    bash -n "$script"
done
node --check src/darwin-service-controller.js
pass "Darwin shell scripts and controller parse"

env_file="$tmpdir/edex.env"
service_dir="$tmpdir/Service Root"
launch_dir="$tmpdir/LaunchAgents"
log_dir="$tmpdir/Logs"
cat > "$env_file" <<EOF
EDEX_SERVICE_DIR="${service_dir}"
EDEX_APP_DIR="${service_dir}/app"
EDEX_LOG_DIR="${log_dir}"
EDEX_LAUNCH_AGENT_DIR="${launch_dir}"
EDEX_WEB_PORT=6080
EDEX_SESSION_LABEL=com.edex-ui.session
EDEX_CONTROLLER_LABEL=com.edex-ui.controller
EOF

bash scripts/render-edex-launchagents-darwin.sh \
    deploy/darwin \
    "$launch_dir" \
    "$env_file"

session_plist="$launch_dir/com.edex-ui.session.plist"
controller_plist="$launch_dir/com.edex-ui.controller.plist"

[[ -f "$session_plist" ]] || fail "session LaunchAgent plist was not rendered"
[[ -f "$controller_plist" ]] || fail "controller LaunchAgent plist was not rendered"
assert_file_contains "$session_plist" '<string>com\.edex-ui\.session</string>' 'session plist must use the session label'
assert_file_contains "$session_plist" '<key>KeepAlive</key>' 'session plist must keep service alive'
assert_file_contains "$session_plist" 'run-edex-session-darwin\.sh' 'session plist must run the macOS session runner'
assert_file_contains "$controller_plist" '<string>com\.edex-ui\.controller</string>' 'controller plist must use the controller label'
assert_file_contains "$controller_plist" 'edex-service-darwin\.sh' 'controller plist must run the service CLI'
assert_file_contains "$controller_plist" '<string>controller</string>' 'controller plist must launch controller mode'
if grep -q '__EDEX_' "$session_plist" "$controller_plist"; then
    fail "rendered LaunchAgents contain unresolved placeholders"
fi
pass "Darwin LaunchAgent templates render"

url_output="$(EDEX_ACCESS_IPS='192.0.2.20' bash scripts/print-edex-access-urls-darwin.sh "$env_file")"
assert_output_contains "$url_output" 'Local URL: http://127\.0\.0\.1:6080/vnc\.html\?autoconnect=1&resize=remote&path=websockify' 'local URL must use localhost and noVNC path'
assert_output_contains "$url_output" 'LAN URL  : http://192\.0\.2\.20:6080/vnc\.html\?autoconnect=1&resize=remote&path=websockify' 'LAN URL must use detected LAN IP and noVNC path'
assert_output_contains "$url_output" 'VNC viewers may control screen with password' 'URL output must mention the macOS VNC prerequisite'
pass "Darwin URL output covers local and LAN access"

assert_file_contains scripts/edex-service-darwin.sh 'launchctl enable "\$\(session_target\)"' 'start must enable the session LaunchAgent'
assert_file_contains scripts/edex-service-darwin.sh 'launchctl disable "\$\(session_target\)"' 'stop must disable the session LaunchAgent before bootout'
assert_file_contains scripts/edex-service-darwin.sh 'launchctl bootout "\$\(session_target\)"' 'stop must boot out the running session'
assert_file_contains scripts/edex-service-darwin.sh 'launchctl kickstart -k "\$target"' 'start must kickstart an already bootstrapped session'
assert_file_contains scripts/edex-service-darwin.sh 'local-url' 'service CLI must expose local URL command'
assert_file_contains scripts/edex-service-darwin.sh 'lan-url' 'service CLI must expose LAN URL command'
pass "Darwin service CLI manages LaunchAgents and URLs"

assert_file_contains scripts/run-edex-session-darwin.sh 'EDEX_MAC_VNC_HOST' 'session runner must target macOS Screen Sharing host'
assert_file_contains scripts/run-edex-session-darwin.sh 'EDEX_MAC_VNC_PORT' 'session runner must target macOS Screen Sharing port'
assert_file_contains scripts/run-edex-session-darwin.sh 'VNC viewers may control screen with password' 'session runner must print manual Screen Sharing setup'
assert_file_contains scripts/run-edex-session-darwin.sh '--listen "\$\{EDEX_WEB_HOST\}:\$\{EDEX_WEB_PORT\}"' 'noVNC must listen on configured web host and port'
assert_file_contains scripts/run-edex-session-darwin.sh '--vnc "\$\{EDEX_MAC_VNC_HOST\}:\$\{EDEX_MAC_VNC_PORT\}"' 'noVNC must connect to macOS Screen Sharing'
pass "Darwin session runner uses native Screen Sharing and noVNC"

assert_file_contains scripts/install-edex-service-darwin.sh 'Run this macOS installer as the logged-in user, not with sudo' 'installer must refuse root installs'
assert_file_contains scripts/install-edex-service-darwin.sh 'brew install "\$\{packages\[@\]\}"' 'installer must use Homebrew dependencies'
assert_file_contains scripts/install-edex-service-darwin.sh 'websockify==\$\{EDEX_WEBSOCKIFY_VERSION\}' 'installer must install pinned websockify'
assert_file_contains scripts/install-edex-service-darwin.sh 'noVNC/archive/refs/tags/\$\{EDEX_NOVNC_VERSION\}\.tar\.gz' 'installer must download pinned noVNC'
assert_file_contains scripts/install-edex-service-darwin.sh 'Manual macOS Screen Sharing setup required' 'installer must print manual Screen Sharing setup'
pass "Darwin installer follows user-scoped install contract"

assert_file_contains src/darwin-service-controller.js 'new Tray' 'controller must create a menu-bar tray'
assert_file_contains src/darwin-service-controller.js 'Start Service' 'controller must expose start action'
assert_file_contains src/darwin-service-controller.js 'Stop Service' 'controller must expose stop action'
assert_file_contains src/darwin-service-controller.js 'Open LAN URL' 'controller must expose LAN URL action'
pass "Darwin menu-bar controller exposes service actions"

assert_file_contains package.json '"test:darwin-service": "bash scripts/test-darwin-service-spec\.sh"' 'package.json must expose Darwin service tests'
assert_file_contains start.sh 'install-edex-service-darwin\.sh' 'start.sh must dispatch to the Darwin installer'
pass "package/start entrypoints include Darwin service"

printf '\nDarwin service spec tests passed.\n'

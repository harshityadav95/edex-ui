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

local_only_url="$(EDEX_ACCESS_IPS='192.0.2.21' bash scripts/print-edex-access-urls-darwin.sh "$env_file" local-url)"
assert_output_contains "$local_only_url" '^http://127\.0\.0\.1:6080/vnc\.html\?autoconnect=1&resize=remote&path=websockify$' 'local-url mode must print only localhost URL'
lan_only_url="$(EDEX_ACCESS_IPS='192.0.2.22 192.0.2.23' bash scripts/print-edex-access-urls-darwin.sh "$env_file" lan-url)"
assert_output_contains "$lan_only_url" '^http://192\.0\.2\.22:6080/vnc\.html\?autoconnect=1&resize=remote&path=websockify$' 'lan-url mode must print the first LAN URL'
url_stub_bin="$tmpdir/url-stub-bin"
mkdir -p "$url_stub_bin"
cat > "$url_stub_bin/ipconfig" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat > "$url_stub_bin/ifconfig" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$url_stub_bin/hostname" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$url_stub_bin/ipconfig" "$url_stub_bin/ifconfig" "$url_stub_bin/hostname"
fallback_lan_url="$(EDEX_ACCESS_IPS='' PATH="$url_stub_bin:/usr/bin:/bin" bash scripts/print-edex-access-urls-darwin.sh "$env_file" lan-url)"
assert_output_contains "$fallback_lan_url" '^http://<mac-lan-ip>:6080/vnc\.html\?autoconnect=1&resize=remote&path=websockify$' 'lan-url mode must fall back to placeholder when no LAN IP is available'
pass "Darwin URL helper modes and fallbacks are covered"

escaped_env="$tmpdir/escaped.env"
escaped_launch="$tmpdir/escaped-launch"
cat > "$escaped_env" <<EOF
EDEX_SERVICE_DIR="${service_dir}"
EDEX_LOG_DIR="${tmpdir}/Logs & Metrics"
EDEX_LAUNCH_AGENT_DIR="${escaped_launch}"
EDEX_SESSION_LABEL="com.edex-ui.session-<test>"
EDEX_CONTROLLER_LABEL="com.edex-ui.controller-<test>"
EOF
bash scripts/render-edex-launchagents-darwin.sh \
    deploy/darwin \
    "$escaped_launch" \
    "$escaped_env"
escaped_session="$escaped_launch/com.edex-ui.session-<test>.plist"
escaped_controller="$escaped_launch/com.edex-ui.controller-<test>.plist"
assert_file_contains "$escaped_session" 'com\.edex-ui\.session-' 'session label text must be rendered'
assert_file_contains "$escaped_controller" 'com\.edex-ui\.controller-' 'controller label text must be rendered'
assert_file_contains "$escaped_session" 'Logs &amp; Metrics' 'log directory ampersand must be XML-escaped'
if grep -q '__EDEX_' "$escaped_session" "$escaped_controller"; then
    fail "escaped render path must still replace all placeholders"
fi
pass "Darwin LaunchAgent renderer escapes XML-sensitive values"

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

stub_bin="$tmpdir/stub-bin"
service_cli="$REPO_ROOT/scripts/edex-service-darwin.sh"
service_root="$tmpdir/service-root"
service_env="$tmpdir/service-cli.env"
service_log="$tmpdir/stub-launchctl.log"
url_log="$tmpdir/stub-urls.log"
launch_state="$tmpdir/stub-launchctl.state"

mkdir -p "$stub_bin" "$service_root/bin" "$service_root/app/src" "$service_root/app/node_modules/.bin" "$tmpdir/agents"
cat > "$service_env" <<EOF
EDEX_SERVICE_DIR="${service_root}"
EDEX_APP_DIR="${service_root}/app"
EDEX_LOG_DIR="${tmpdir}/logs"
EDEX_LAUNCH_AGENT_DIR="${tmpdir}/agents"
EDEX_SESSION_LABEL=com.edex-ui.session
EDEX_CONTROLLER_LABEL=com.edex-ui.controller
EDEX_MAC_VNC_HOST=127.0.0.1
EDEX_MAC_VNC_PORT=5900
EDEX_WEB_PORT=6080
EOF

cat > "$service_root/bin/print-edex-access-urls-darwin.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$STUB_URL_LOG"
case "${2:-}" in
  local-url) printf 'http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote&path=websockify\n' ;;
  lan-url) printf 'http://192.0.2.44:6080/vnc.html?autoconnect=1&resize=remote&path=websockify\n' ;;
  *) printf 'stub-urls\n' ;;
esac
EOF
chmod +x "$service_root/bin/print-edex-access-urls-darwin.sh"

cat > "$service_root/app/node_modules/.bin/electron" <<'EOF'
#!/usr/bin/env bash
printf 'electron %s\n' "$*" >> "$STUB_LAUNCHCTL_LOG"
exit 0
EOF
chmod +x "$service_root/app/node_modules/.bin/electron"
touch "$service_root/app/src/darwin-service-controller.js"

cat > "$stub_bin/launchctl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
cmd="$1"
printf 'launchctl %s\n' "$*" >> "$STUB_LAUNCHCTL_LOG"
case "$cmd" in
  print)
    if [[ "${2:-}" == "gui/501/com.edex-ui.session" && "${STUB_BOOTSTRAPPED:-0}" == "1" ]]; then
      printf 'state = running\n'
      exit 0
    fi
    exit 1
    ;;
  enable|disable|bootstrap|kickstart|bootout)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$stub_bin/launchctl"

cat > "$stub_bin/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-u" ]]; then
  printf '501\n'
  exit 0
fi
exec /usr/bin/id "$@"
EOF
chmod +x "$stub_bin/id"

cat > "$stub_bin/nc" <<'EOF'
#!/usr/bin/env bash
if [[ "${STUB_NC_READY:-1}" == "1" ]]; then
  exit 0
fi
exit 1
EOF
chmod +x "$stub_bin/nc"

cat > "$stub_bin/lsof" <<'EOF'
#!/usr/bin/env bash
if [[ "${STUB_LSOF_READY:-0}" == "1" ]]; then
  exit 0
fi
exit 1
EOF
chmod +x "$stub_bin/lsof"

touch "$tmpdir/agents/com.edex-ui.session.plist" "$tmpdir/agents/com.edex-ui.controller.plist"

service_path="$stub_bin:/usr/bin:/bin"
service_cmd_base=(env EDEX_ENV_FILE="$service_env" STUB_LAUNCHCTL_LOG="$service_log" STUB_URL_LOG="$url_log" PATH="$service_path" bash "$service_cli")

rm -f "$service_log"
"${service_cmd_base[@]}" help >/dev/null
if [[ -s "$service_log" ]]; then
    fail "help command should not invoke launchctl"
fi

rm -f "$service_log"
STUB_BOOTSTRAPPED=0 "${service_cmd_base[@]}" start
assert_output_contains "$(cat "$service_log")" 'launchctl enable gui/501/com\.edex-ui\.session' 'start must enable the session target'
assert_output_contains "$(cat "$service_log")" 'launchctl bootstrap gui/501 .*/com\.edex-ui\.session\.plist' 'start must bootstrap non-running session'

rm -f "$service_log"
STUB_BOOTSTRAPPED=1 "${service_cmd_base[@]}" start
assert_output_contains "$(cat "$service_log")" 'launchctl kickstart -k gui/501/com\.edex-ui\.session' 'start must kickstart existing bootstrapped session'

rm -f "$service_log"
STUB_BOOTSTRAPPED=1 "${service_cmd_base[@]}" stop
assert_output_contains "$(cat "$service_log")" 'launchctl disable gui/501/com\.edex-ui\.session' 'stop must disable session target'
assert_output_contains "$(cat "$service_log")" 'launchctl bootout gui/501/com\.edex-ui\.session' 'stop must boot out bootstrapped session'

status_running="$(STUB_BOOTSTRAPPED=1 "${service_cmd_base[@]}" status)"
assert_output_contains "$status_running" '^running$' 'status must report running when launchctl print succeeds'
status_stopped="$(STUB_BOOTSTRAPPED=0 "${service_cmd_base[@]}" status)"
assert_output_contains "$status_stopped" '^stopped$' 'status must report stopped when launchctl print fails'

rm -f "$url_log"
"${service_cmd_base[@]}" urls >/dev/null
"${service_cmd_base[@]}" local-url >/dev/null
"${service_cmd_base[@]}" lan-url >/dev/null
assert_output_contains "$(cat "$url_log")" "${service_env}" 'URL commands must pass env file to URL helper'
assert_output_contains "$(cat "$url_log")" 'local-url' 'local-url command must call helper with local-url mode'
assert_output_contains "$(cat "$url_log")" 'lan-url' 'lan-url command must call helper with lan-url mode'

check_output="$(STUB_NC_READY=0 STUB_LSOF_READY=0 STUB_BOOTSTRAPPED=0 "${service_cmd_base[@]}" check)"
assert_output_contains "$check_output" 'Screen Sharing is not listening' 'check must print screen sharing warning when probes fail'
assert_output_contains "$check_output" 'Enable Screen Sharing and "VNC viewers may control screen with password"' 'check must include setup guidance for missing screen sharing'
assert_output_contains "$check_output" 'Session plist' 'check output must include rendered session plist path'

set +e
unknown_output="$("${service_cmd_base[@]}" unknown 2>&1)"
unknown_exit=$?
set -e
[[ "$unknown_exit" -eq 2 ]] || fail "unknown service command must exit with status 2"
assert_output_contains "$unknown_output" 'Unknown command: unknown' 'unknown command path must print clear error'

rm -f "$service_log"
"${service_cmd_base[@]}" controller
assert_output_contains "$(cat "$service_log")" 'electron .*/src/darwin-service-controller\.js' 'controller command must exec electron with controller entry'

missing_env="$tmpdir/missing-plist.env"
cat > "$missing_env" <<EOF
EDEX_SERVICE_DIR="${service_root}"
EDEX_APP_DIR="${service_root}/app"
EDEX_LAUNCH_AGENT_DIR="${tmpdir}/missing-agents"
EDEX_SESSION_LABEL=com.edex-ui.session
EOF
set +e
missing_plist_output="$(env EDEX_ENV_FILE="$missing_env" PATH="$service_path" bash "$service_cli" start 2>&1)"
missing_plist_exit=$?
set -e
[[ "$missing_plist_exit" -eq 1 ]] || fail "start must fail when plist is missing"
assert_output_contains "$missing_plist_output" 'Missing LaunchAgent plist' 'missing plist failure must explain remediation'
pass "Darwin service CLI behavioral paths are covered with launchctl stubs"

session_stub_bin="$tmpdir/session-stub-bin"
mkdir -p "$session_stub_bin"
cat > "$session_stub_bin/nc" <<'EOF'
#!/usr/bin/env bash
exit "${STUB_NC_READY:-1}"
EOF
chmod +x "$session_stub_bin/nc"
cat > "$session_stub_bin/lsof" <<'EOF'
#!/usr/bin/env bash
exit "${STUB_LSOF_READY:-1}"
EOF
chmod +x "$session_stub_bin/lsof"
cat > "$session_stub_bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$session_stub_bin/sleep"
session_cmd_base=(env EDEX_SETUP_RETRY_SECONDS=0 EDEX_APP_DIR="$tmpdir/nonexistent-app" PATH="$session_stub_bin:/usr/bin:/bin" bash "$REPO_ROOT/scripts/run-edex-session-darwin.sh")

set +e
session_missing_ss_output="$(STUB_NC_READY=1 STUB_LSOF_READY=1 "${session_cmd_base[@]}" 2>&1)"
session_missing_ss_exit=$?
set -e
[[ "$session_missing_ss_exit" -eq 78 ]] || fail "session runner must exit 78 when screen sharing is unavailable"
assert_output_contains "$session_missing_ss_output" 'Enable "VNC viewers may control screen with password"' 'session runner failure path must print manual setup steps'

set +e
session_missing_app_output="$(STUB_NC_READY=0 STUB_LSOF_READY=1 "${session_cmd_base[@]}" 2>&1)"
session_missing_app_exit=$?
set -e
[[ "$session_missing_app_exit" -eq 1 ]] || fail "session runner must fail when app directory is missing after screen sharing probe succeeds"
assert_output_contains "$session_missing_app_output" 'missing eDEX app directory' 'session runner missing app path must be explicit'
pass "Darwin session runner failure paths are covered"

printf '\nDarwin service spec tests passed.\n'

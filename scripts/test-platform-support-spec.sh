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

assert_file_not_contains() {
    local file="$1" pattern="$2" message="$3"
    if grep -Eq -- "$pattern" "$file"; then
        fail "$message"
    fi
}

node <<'NODE'
const fs = require("fs");

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exit(1);
}

function assertSupportedOs(pkg, name) {
  const os = pkg.os || [];
  if (JSON.stringify(os) !== JSON.stringify(["darwin", "linux"])) {
    fail(`${name} must restrict os to darwin and linux`);
  }
}

function assertMissingScripts(pkg, names) {
  for (const name of names) {
    if (pkg.scripts && Object.prototype.hasOwnProperty.call(pkg.scripts, name)) {
      fail(`package.json must not expose ${name}`);
    }
  }
}

const root = readJson("package.json");
const src = readJson("src/package.json");

assertSupportedOs(root, "package.json");
assertSupportedOs(src, "src/package.json");
assertMissingScripts(root, [
  "preinstall-windows",
  "install-windows",
  "prebuild-windows",
  "build-windows",
  "postbuild-windows",
  "prebuild-linux",
  "build-linux",
  "postbuild-linux"
]);

for (const key of ["win", "nsis", "linux", "appImage"]) {
  if (root.build && Object.prototype.hasOwnProperty.call(root.build, key)) {
    fail(`electron-builder config must not include ${key}`);
  }
}

if (!root.scripts || root.scripts["test:platform-support"] !== "bash scripts/test-platform-support-spec.sh") {
  fail("package.json must expose test:platform-support");
}
NODE
pass "package manifests restrict platform support"

for file in \
    .github/workflows/build-binaries.yaml \
    .github/workflows/pr-service-tests.yml \
    .github/workflows/release-macos-arm64.yml \
    .github/workflows/codeql-analysis.yml \
    README.md \
    .github/ISSUE_TEMPLATE/issue_template.md
do
    assert_file_not_contains "$file" 'Windows|windows-latest|build-windows|Windows-Installer|\.exe' "${file} must not advertise Windows support"
done
pass "CI and docs do not advertise Windows support"

for file in \
    .github/workflows/build-binaries.yaml \
    README.md \
    docs/lan-service-deployment.md \
    docs/linux-debian-service-setup.md
do
    assert_file_not_contains "$file" 'AppImage|Linux-AppImage|build-linux|prebuild-linux|dist/\*\.AppImage' "${file} must not advertise Linux AppImage packaging"
done
pass "CI and docs do not advertise Linux AppImage packaging"

assert_file_contains .github/workflows/build-binaries.yaml 'workflow_dispatch' 'macOS package workflow must support manual dispatch'
assert_file_contains .github/workflows/build-binaries.yaml 'tags:' 'macOS package workflow must run from version tags'
assert_file_not_contains .github/workflows/build-binaries.yaml 'pull_request|create' 'macOS package workflow must not run on PR/create without signing secrets'
assert_file_contains .github/workflows/build-binaries.yaml 'npm ci' 'macOS package workflow must use npm ci'
assert_file_contains .github/workflows/build-binaries.yaml 'npm run prebuild-darwin' 'macOS package workflow must prepare prebuild-src before Electron Builder'
assert_file_contains .github/workflows/release-macos-arm64.yml 'npm run prebuild-darwin-arm64' 'macOS arm64 release workflow must prepare prebuild-src before Electron Builder'

for file in .github/workflows/*.yml .github/workflows/*.yaml
do
    [[ -f "$file" ]] || continue
    assert_file_not_contains "$file" 'node-version: 24' "${file} must use the supported Node 22 line"
    assert_file_not_contains "$file" 'npm install' "${file} must use npm ci for lockfile-consistent installs"
done
pass "GitHub Actions match supported build and install policy"

for file in \
    src/_boot.js \
    src/_renderer.js \
    src/classes/sysinfo.class.js \
    src/classes/terminal.class.js \
    src/classes/filesystem.class.js \
    src/classes/cpuinfo.class.js
do
    assert_file_not_contains "$file" 'win32|powershell|Windows' "${file} must not contain Windows runtime branches"
done
pass "runtime files contain no Windows branches"

assert_file_contains scripts/install-edex-service-linux.sh 'need_debian_linux' 'Linux installer must define Debian/Ubuntu guard'
assert_file_contains scripts/install-edex-service-linux.sh 'ID_LIKE' 'Linux installer must inspect os-release ID_LIKE'
assert_file_contains scripts/install-edex-service-linux.sh 'apt-get' 'Linux installer must require apt-get'
assert_file_contains scripts/install-edex-service-linux.sh 'Debian/Ubuntu Linux only' 'Linux installer must clearly state supported Linux family'
pass "Linux installer enforces Debian/Ubuntu family"

printf '\nPlatform support spec tests passed.\n'

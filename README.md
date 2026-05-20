# eDEX-UI LAN Browser Service

This repository is a maintained deployment fork of **eDEX-UI**, the fullscreen sci-fi terminal emulator and system monitor originally created by [GitSquared](https://github.com/GitSquared/edex-ui).

The application remains an Electron desktop app. The service layer makes that desktop reachable from a browser on a LAN:

- On Linux, eDEX runs on a virtual display and is streamed through noVNC behind authenticated HTTPS.
- On macOS, eDEX runs in the logged-in desktop session and native Screen Sharing is exposed through noVNC, with a separate top-bar controller for start/stop and URL actions.

Linux support is the Debian/Ubuntu source-service installation path only. The macOS DMG remains the only packaged desktop artifact.

## Supported Profiles

| Platform | Service manager | Browser URL | Access model | Main caveat |
| --- | --- | --- | --- | --- |
| Debian 12 / Ubuntu 24.04 | systemd + Nginx | `https://<server-ip>:8443/vnc.html?autoconnect=1&resize=remote&path=websockify` | Nginx HTTPS Basic Auth | VNC/noVNC/eDEX internal ports must stay loopback-only |
| macOS desktop session | per-user LaunchAgents + top-bar controller | `http://<mac-lan-ip>:6080/vnc.html?autoconnect=1&resize=remote&path=websockify` | macOS Screen Sharing VNC password | Browser clients control the active Mac desktop session |

## Architecture

Linux service profile:

```text
LAN browser or Cloudflare hostname
  -> Nginx HTTPS Basic Auth on 8443
      -> noVNC backend on 127.0.0.1:6080
          -> x11vnc on 127.0.0.1:5901
              -> virtual X11 display :1
                  -> Openbox
                      -> eDEX-UI Electron app
                          -> terminal WebSockets on 127.0.0.1:3000-3006
```

Only Nginx is intended to be reachable from the LAN. VNC, noVNC, and eDEX terminal WebSocket ports should remain private unless you deliberately configure password-protected raw VNC access.

macOS service profile:

```text
LAN browser
  -> noVNC HTTP server on 0.0.0.0:6080
      -> macOS Screen Sharing VNC on 127.0.0.1:5900
          -> logged-in macOS Aqua desktop session
              -> eDEX-UI Electron app
```

macOS does not provide the same native Xvfb-style hidden desktop used by the Linux profile. The macOS profile exposes the active Mac session, so use it only on a trusted LAN or behind a private network.

## Requirements

Linux targets:

- Debian 12 or Ubuntu 24.04.
- LXD/LXC, Proxmox LXC, VM, or bare-metal host.
- `sudo`, `git`, and outbound network access during install.
- Minimum: 2 vCPU, 2 GB RAM, 10 GB disk.
- Recommended: 2-4 vCPU, 4 GB RAM, optional `/dev/dri/renderD*` render device.

macOS targets:

- macOS with an interactive logged-in desktop user.
- Homebrew.
- Screen Sharing enabled in System Settings.
- `VNC viewers may control screen with password` enabled with a dedicated VNC password.
- LAN devices allowed to reach the Mac on the configured noVNC HTTP port.

## Quick Install: Linux

Clone the repository on the target Linux host:

```bash
apt update
apt install -y git sudo ca-certificates
git clone https://github.com/harshityadav95/edex-ui.git /root/edex-ui
cd /root/edex-ui
```

Run the one-command setup wrapper:

```bash
sudo ./start.sh
```

or run the Linux installer directly:

```bash
sudo scripts/install-edex-service-linux.sh
```

For a non-interactive install with known web credentials:

```bash
sudo EDEX_WEB_USER=operator EDEX_WEB_PASSWORD='change-this-password' scripts/install-edex-service-linux.sh
```

The Linux installer:

- installs Node.js 22 when needed;
- installs runtime packages for Electron, X11, noVNC, Nginx, and native builds;
- creates the `edex` service user;
- copies the app to `/opt/edex-ui`;
- runs `pnpm run install-linux`;
- installs `/etc/edex-ui/edex.env`;
- installs and enables `edex.service`;
- renders and enables the Nginx HTTPS proxy;
- creates the Nginx password file;
- starts `edex.service` and `nginx`.

Open the Linux service at:

```text
https://<server-ip>:8443/vnc.html?autoconnect=1&resize=remote&path=websockify
```

The default Nginx certificate is self-signed, so the browser will show a certificate warning. Accept it for the local service, then log in with the username/password configured during installation.

Print exact Linux LAN and Cloudflare URLs:

```bash
sudo check-edex-service.sh
```

or:

```bash
print-edex-access-urls.sh /etc/edex-ui/edex.env
```

## Quick Install: macOS

First enable native Screen Sharing:

1. Open System Settings.
2. Open General > Sharing.
3. Enable Screen Sharing.
4. Open Screen Sharing settings / Computer Settings.
5. Enable `VNC viewers may control screen with password`.
6. Set a dedicated VNC password that is not your macOS login password.

Clone the repository on the Mac, then run the installer as the logged-in user. Do not use `sudo`:

```bash
./start.sh
```

or:

```bash
scripts/install-edex-service-darwin.sh
```

The macOS installer:

- uses Homebrew for Node.js and Python dependencies;
- copies the app to `~/Library/Application Support/eDEX-UI-Service/app`;
- runs `pnpm run install-darwin`;
- installs pinned noVNC and websockify;
- installs per-user LaunchAgents;
- starts the menu-bar controller;
- starts the eDEX session service when Screen Sharing is ready.

If Screen Sharing is not ready, the installer leaves the eDEX session disabled and prints the manual setup steps. After enabling Screen Sharing, start it from the top-bar menu or run:

```bash
"$HOME/Library/Application Support/eDEX-UI-Service/bin/edex-service-darwin.sh" start
```

Open the macOS service locally:

```text
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote&path=websockify
```

Open it from another LAN device:

```text
http://<mac-lan-ip>:6080/vnc.html?autoconnect=1&resize=remote&path=websockify
```

Enter the VNC password configured in macOS Screen Sharing when noVNC prompts for it.

## Service Management

Linux:

```bash
sudo systemctl status edex.service
sudo systemctl status nginx
sudo systemctl restart edex.service nginx
sudo journalctl -u edex.service -f
sudo check-edex-service.sh
```

macOS:

The top-bar controller provides:

- Start Service
- Stop Service
- Restart Service
- Open Local URL
- Open LAN URL
- Copy Local URL
- Copy LAN URL
- Status / Setup Check

The same actions are available from the terminal:

```bash
SERVICE="$HOME/Library/Application Support/eDEX-UI-Service/bin/edex-service-darwin.sh"

"$SERVICE" status
"$SERVICE" start
"$SERVICE" stop
"$SERVICE" restart
"$SERVICE" urls
"$SERVICE" check
```

## Configuration

Linux configuration lives in:

```text
/etc/edex-ui/edex.env
```

Common Linux settings:

```bash
EDEX_RESOLUTION=1600x900
EDEX_DEPTH=24
EDEX_DISPLAY_BACKEND=auto
EDEX_VNC_STACK=novnc
EDEX_RAW_VNC_HOST=127.0.0.1
EDEX_NOVNC_HOST=127.0.0.1
EDEX_WEB_PORT=8443
EDEX_ELECTRON_FLAGS="--no-sandbox"
EDEX_DISABLE_AUDIO=false
EDEX_THEME=tron
```

Display backends:

- `auto`: use Xorg dummy when `/dev/dri/renderD128` is available, otherwise fall back to Xvfb.
- `xvfb`: most compatible software display path.
- `xorg-dri`: require the Xorg dummy path; use only after GPU passthrough works.

VNC stacks:

- `novnc`: default distro package path using x11vnc plus noVNC.
- `auto`: prefer KasmVNC if installed and configured, otherwise use noVNC.
- `kasm`: require KasmVNC.

Apply Linux config changes:

```bash
sudo systemctl restart edex.service
sudo render-edex-nginx-config.sh
sudo nginx -t
sudo systemctl reload nginx
```

macOS configuration lives in:

```text
~/Library/Application Support/eDEX-UI-Service/edex.env
```

Common macOS settings:

```bash
EDEX_WEB_HOST=0.0.0.0
EDEX_WEB_PORT=6080
EDEX_MAC_VNC_HOST=127.0.0.1
EDEX_MAC_VNC_PORT=5900
EDEX_ELECTRON_FLAGS="--nointro"
```

Apply macOS config changes:

```bash
"$HOME/Library/Application Support/eDEX-UI-Service/bin/edex-service-darwin.sh" restart
```

## Cloudflare Tunnel

The documented Cloudflare path applies to the Linux HTTPS/Nginx profile.

Point the tunnel origin at the eDEX/Nginx HTTPS service:

```text
https://<server-ip>:8443
```

If `cloudflared` runs on a different machine than eDEX-UI, do not use `localhost` as the origin. `localhost` would refer to the `cloudflared` machine, not the eDEX host.

With the generated self-signed Nginx certificate, disable origin TLS verification:

```yaml
ingress:
  - hostname: edex.example.com
    service: https://<server-ip>:8443
    originRequest:
      noTLSVerify: true
  - service: http_status:404
```

Then open:

```text
https://edex.example.com/vnc.html?autoconnect=1&resize=remote&path=websockify
```

Do not expose ports `5901`, `6080`, or `3000-3006` publicly on Linux. For macOS, do not publish the HTTP noVNC endpoint directly to the internet; use a VPN or private access layer.

## Raw VNC

Linux raw VNC is loopback-only by default:

```bash
EDEX_RAW_VNC_HOST=127.0.0.1
EDEX_VNC_PORT=5901
```

Only enable LAN-facing raw VNC when you explicitly need a VNC client. A password is required when binding raw VNC to a non-loopback address:

```bash
EDEX_RAW_VNC_HOST=0.0.0.0
EDEX_VNC_PASSWORD_FILE=/var/lib/edex-ui/.vnc/passwd
```

or:

```bash
EDEX_RAW_VNC_HOST=0.0.0.0
EDEX_VNC_PASSWORD='change-this-vnc-password'
```

For normal Linux browser use, keep raw VNC private and access eDEX through the HTTPS noVNC URL.

On macOS, raw VNC is native Screen Sharing on `127.0.0.1:5900` from the service perspective. Configure Screen Sharing access in System Settings, not in the eDEX Linux env file.

## Development From Source

Install dependencies and native modules for the host platform:

```bash
pnpm run install-linux
pnpm run install-darwin
```

Start the desktop app directly:

```bash
pnpm run start
```

Direct mode launches Electron locally and does not install the browser/VNC service.

Build the macOS distributable desktop package:

```bash
pnpm run build-darwin
```

On Linux, use `sudo ./start.sh` or `sudo scripts/install-edex-service-linux.sh` to install the Debian/Ubuntu service from source.

## Tests

Run the Linux service contract tests:

```bash
pnpm run test:linux-service
```

The Linux tests validate shell script syntax, Nginx template rendering, URL output, service defaults, and the loopback-only backend contract.

Run the macOS service contract tests:

```bash
pnpm run test:darwin-service
```

The macOS tests validate shell script syntax, LaunchAgent template rendering, URL output, service control commands, and the menu-bar controller entry point.

## Useful Files

Cross-platform:

- `start.sh`: OS-dispatching convenience installer wrapper.
- `src/_boot.js`: main eDEX Electron entry point.
- `src/darwin-service-controller.js`: macOS top-bar controller entry point.

Linux service:

- `scripts/install-edex-service-linux.sh`: primary Debian/Ubuntu service installer.
- `scripts/run-edex-session-linux.sh`: systemd session runner for display, Electron, and VNC/noVNC.
- `scripts/check-edex-service.sh`: status, listener, process, and journal checker.
- `scripts/print-edex-access-urls.sh`: LAN and Cloudflare URL helper.
- `scripts/render-edex-nginx-config.sh`: renders Nginx config from `/etc/edex-ui/edex.env`.
- `deploy/linux/edex.service`: systemd unit.
- `deploy/linux/edex.env`: default Linux runtime environment.
- `deploy/linux/nginx-edex.conf`: Nginx HTTPS/noVNC reverse proxy template.

macOS service:

- `scripts/install-edex-service-darwin.sh`: macOS per-user service installer.
- `scripts/edex-service-darwin.sh`: macOS LaunchAgent service control helper.
- `scripts/run-edex-session-darwin.sh`: macOS eDEX/noVNC session runner.
- `scripts/print-edex-access-urls-darwin.sh`: macOS local/LAN URL helper.
- `scripts/render-edex-launchagents-darwin.sh`: renders macOS LaunchAgent plists.
- `deploy/darwin/edex.env`: default macOS runtime environment.
- `deploy/darwin/*.plist`: LaunchAgent templates.

Runbooks:

- `docs/linux-debian-service-setup.md`: detailed Debian/Ubuntu runbook.
- `docs/lan-service-deployment.md`: Linux service architecture notes.
- `docs/macos-service-setup.md`: macOS Screen Sharing/noVNC service runbook.

## Troubleshooting

Linux first checks:

```bash
sudo check-edex-service.sh
```

If the Linux browser cannot connect:

- confirm `nginx` is active;
- confirm port `8443/tcp` is reachable from your LAN;
- use the full noVNC path: `/vnc.html?autoconnect=1&resize=remote&path=websockify`;
- verify that noVNC and VNC are listening only on loopback;
- check `sudo journalctl -u edex.service -n 100 --no-pager`.

If the Linux display does not start in a container, set:

```bash
EDEX_DISPLAY_BACKEND=xvfb
```

then restart:

```bash
sudo systemctl restart edex.service
```

If Cloudflare Tunnel shows a TLS/origin error, make sure the tunnel uses:

```text
originRequest.noTLSVerify=true
```

and that the service URL is the eDEX host LAN address, not `localhost`, unless `cloudflared` is running on the same host.

macOS first checks:

```bash
"$HOME/Library/Application Support/eDEX-UI-Service/bin/edex-service-darwin.sh" check
```

If the macOS browser cannot connect:

- confirm Screen Sharing is enabled in System Settings;
- confirm `VNC viewers may control screen with password` is enabled;
- confirm port `6080/tcp` is reachable from the LAN;
- use the full noVNC path;
- check logs in `~/Library/Logs/eDEX-UI-Service`;
- keep the Mac awake for always-on LAN access.

## Credits

The original eDEX-UI application was created by [Gabriel "Squared" Saillard](https://github.com/GitSquared). This repository keeps the original application code and adds Linux and macOS LAN browser service deployment workflows.

Thanks to the original eDEX-UI contributors and the upstream projects used by eDEX-UI, including Electron, xterm.js, systeminformation, SmoothieCharts, noVNC, x11vnc, and Nginx.

## License

GPL-3.0. See [LICENSE](LICENSE).

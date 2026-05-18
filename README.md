# eDEX-UI LAN Browser Service

This repository is a maintained deployment fork of **eDEX-UI**, the fullscreen sci-fi terminal emulator and system monitor originally created by [GitSquared](https://github.com/GitSquared/edex-ui).

The current working setup keeps eDEX-UI as an Electron desktop application, but runs it headlessly on Linux and streams the desktop to a browser over HTTPS. It is intended for Debian/Ubuntu servers, containers, VMs, and LAN-hosted dashboards.

## What Works

- Debian 12 and Ubuntu 24.04 service deployment.
- LXD/LXC, Proxmox LXC, VM, or bare-metal Linux host.
- Source build using Node.js 22 and Electron.
- Virtual display using Xvfb, or Xorg dummy when a render device is available.
- Openbox window manager for the Electron desktop session.
- Browser access through noVNC at an authenticated HTTPS endpoint.
- Nginx Basic Auth in front of noVNC.
- Private loopback binding for VNC, noVNC, and eDEX terminal WebSocket ports.
- Optional Cloudflare Tunnel access for the browser-rendered noVNC page.
- Health-check and URL helper scripts.

The AppImage download path from the archived upstream project is not used for this service setup.

## Architecture

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

Only Nginx is intended to be reachable from the LAN. The VNC, noVNC, and eDEX internal ports should remain private unless you deliberately configure raw VNC access.

## Requirements

Use one of:

- Debian 12
- Ubuntu 24.04
- LXD/LXC container
- Proxmox LXC container
- VM or bare-metal Linux host

Minimum resources:

- 2 vCPU
- 2 GB RAM
- 10 GB disk

Recommended resources:

- 2-4 vCPU
- 4 GB RAM
- Optional `/dev/dri/renderD*` render device for accelerated display paths

## Quick Install

Clone the repository on the target Linux host:

```bash
apt update
apt install -y git sudo ca-certificates
git clone https://github.com/harshityadav95/edex-ui.git /root/edex-ui
cd /root/edex-ui
```

Run the installer:

```bash
sudo scripts/install-edex-service-linux.sh
```

For a non-interactive install with known web credentials:

```bash
sudo EDEX_WEB_USER=operator EDEX_WEB_PASSWORD='change-this-password' scripts/install-edex-service-linux.sh
```

The installer:

- installs Node.js 22 when needed;
- installs the Linux runtime packages for Electron, X11, noVNC, Nginx, and builds;
- creates the `edex` service user;
- copies the app to `/opt/edex-ui`;
- runs `npm run install-linux`;
- installs `/etc/edex-ui/edex.env`;
- installs and enables `edex.service`;
- renders and enables the Nginx HTTPS proxy;
- creates the Nginx password file;
- starts `edex.service` and `nginx`.

## Open In A Browser

Find the host IP:

```bash
hostname -I
```

Open:

```text
https://<server-ip>:8443/vnc.html?autoconnect=1&resize=remote&path=websockify
```

The default Nginx certificate is self-signed, so the browser will show a certificate warning. Accept it for the local service, then log in with the username/password configured during installation.

You can print the exact LAN and Cloudflare URLs at any time:

```bash
sudo check-edex-service.sh
```

or:

```bash
print-edex-access-urls.sh /etc/edex-ui/edex.env
```

## One-Command Local Setup Helper

`start.sh` wraps the service installer and prints LAN and Cloudflare tunnel guidance after installation:

```bash
sudo ./start.sh
```

It installs the same systemd service and Nginx/noVNC stack as `scripts/install-edex-service-linux.sh`.

## Service Management

Check status:

```bash
sudo systemctl status edex.service
sudo systemctl status nginx
```

Restart:

```bash
sudo systemctl restart edex.service nginx
```

Follow logs:

```bash
sudo journalctl -u edex.service -f
```

Run the service checker:

```bash
sudo check-edex-service.sh
```

## Configuration

Runtime configuration lives in:

```text
/etc/edex-ui/edex.env
```

Common settings:

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

After changing `/etc/edex-ui/edex.env`, apply the changes:

```bash
sudo systemctl restart edex.service
sudo render-edex-nginx-config.sh
sudo nginx -t
sudo systemctl reload nginx
```

## Cloudflare Tunnel

For browser access through Cloudflare Tunnel, point the tunnel origin at the eDEX/Nginx HTTPS service:

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

Do not expose ports `5901`, `6080`, or `3000-3006` publicly.

## Raw VNC

Raw VNC is loopback-only by default:

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

For normal browser use, keep raw VNC private and access eDEX through the HTTPS noVNC URL.

## Development From Source

Install dependencies and native modules:

```bash
npm run install-linux
```

Start the desktop app directly:

```bash
npm run start
```

This direct mode launches Electron locally and does not install the browser/VNC service.

Build distributable desktop packages for the host platform:

```bash
npm run build-linux
npm run build-darwin
npm run build-windows
```

Native modules mean builds should be created on the target OS family.

## Tests

Run the Linux service contract tests:

```bash
npm run test:linux-service
```

The tests validate shell script syntax, Nginx template rendering, URL output, service defaults, and the loopback-only backend contract.

## Useful Files

- `start.sh`: convenience installer wrapper.
- `scripts/install-edex-service-linux.sh`: primary Debian/Ubuntu service installer.
- `scripts/run-edex-session-linux.sh`: systemd session runner for display, Electron, and VNC/noVNC.
- `scripts/check-edex-service.sh`: status, listener, process, and journal checker.
- `scripts/print-edex-access-urls.sh`: LAN and Cloudflare URL helper.
- `scripts/render-edex-nginx-config.sh`: renders Nginx config from `/etc/edex-ui/edex.env`.
- `deploy/linux/edex.service`: systemd unit.
- `deploy/linux/edex.env`: default runtime environment.
- `deploy/linux/nginx-edex.conf`: Nginx HTTPS/noVNC reverse proxy template.
- `docs/linux-debian-service-setup.md`: detailed Debian/Ubuntu runbook.
- `docs/lan-service-deployment.md`: service architecture notes.

## Troubleshooting

Check the service first:

```bash
sudo check-edex-service.sh
```

If the browser cannot connect:

- confirm `nginx` is active;
- confirm port `8443/tcp` is reachable from your LAN;
- use the full noVNC path: `/vnc.html?autoconnect=1&resize=remote&path=websockify`;
- verify that noVNC and VNC are listening only on loopback;
- check `sudo journalctl -u edex.service -n 100 --no-pager`.

If the display does not start in a container, set:

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

## Credits

The original eDEX-UI application was created by [Gabriel "Squared" Saillard](https://github.com/GitSquared). This repository keeps the original application code and adds the Linux browser service deployment workflow.

Thanks to the original eDEX-UI contributors and the upstream projects used by eDEX-UI, including Electron, xterm.js, systeminformation, SmoothieCharts, noVNC, x11vnc, and Nginx.

## License

GPL-3.0. See [LICENSE](LICENSE).

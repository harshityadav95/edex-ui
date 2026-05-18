# eDEX-UI Linux LAN Service Architecture

This document describes the supported LAN service architecture for eDEX-UI on Debian/Ubuntu Linux. eDEX-UI remains an Electron desktop application; it is not converted into a web app. The service runs the desktop app on a virtual Linux display and streams that display to browsers through an authenticated HTTPS endpoint.

## Supported Target

- Debian 12 or Ubuntu 24.04.
- systemd service manager.
- LXD/LXC, Proxmox LXC, VM, or bare-metal Linux.
- Source build with `npm run install-linux`.
- Browser access at `https://<server-ip>:8443/vnc.html?autoconnect=1&resize=remote&path=websockify`.
- Optional Cloudflare Tunnel access by forwarding local Nginx HTTPS to a public hostname.

The AppImage path is intentionally not used for this service deployment.

## Runtime Architecture

```text
LAN browser or Cloudflare hostname
  -> Nginx HTTPS Basic Auth on 8443
      -> noVNC/Kasm browser backend on 127.0.0.1:6080
          -> VNC server on 127.0.0.1:5901
              -> virtual X11 display :1
                  -> Openbox window manager
                      -> eDEX-UI Electron process
                          -> internal terminal WebSockets on 127.0.0.1:3000-3006
```

Only Nginx is exposed to the LAN or Cloudflare Tunnel. VNC, noVNC, and eDEX terminal WebSocket ports stay private to the Linux host/container.

## Service Model

The repo provides a single Linux systemd unit:

- `deploy/linux/edex.service`

The unit runs:

- a virtual display, either Xorg dummy or Xvfb;
- Openbox;
- eDEX-UI from `/opt/edex-ui`;
- x11vnc/noVNC by default.
- KasmVNC only when explicitly selected and configured.

The service uses:

- `/etc/edex-ui/edex.env` for runtime configuration;
- `/var/lib/edex-ui` for persistent eDEX user data and shell home;
- `/usr/local/bin/run-edex-session-linux.sh` as the session runner.

## Display Pipeline

Default behavior:

- `EDEX_DISPLAY_BACKEND=auto`
- `EDEX_RESOLUTION=1600x900`
- `EDEX_DEPTH=24`

`auto` starts Xorg dummy when a render node such as `/dev/dri/renderD128` is available. If that path is not usable, it falls back to Xvfb.

Recommended choices:

- Use `xvfb` for maximum compatibility in containers.
- Use `xorg-dri` only when GPU passthrough is confirmed.
- Keep `1600x900` for responsive browser streaming.
- Use `1920x1080` only after checking CPU/GPU load.

## Network And Authentication

LAN-facing endpoint:

```text
https://<server-ip>:8443/vnc.html?autoconnect=1&resize=remote&path=websockify
```

Credentials are stored in:

```text
/etc/nginx/edex.htpasswd
```

The Nginx config is:

```text
deploy/linux/nginx-edex.conf
```

Ports that must not be exposed to the LAN:

```text
3000-3006/tcp  eDEX terminal WebSockets
5901/tcp       raw VNC
6080/tcp       noVNC/Kasm backend
```

For internet access, place the service behind a VPN or identity-aware gateway. Cloudflare Tunnel TCP origins should use the LAN IP and port:

```text
tcp://<server-ip>:8443
```

Cloudflare browser URL:

```text
https://<cloudflare-hostname>/vnc.html?autoconnect=1&resize=remote&path=websockify
```

Use `tcp://<server-ip>:5901` only for raw VNC client access. Do not forward `8443` directly to the public internet.

## Installation Flow

The Linux installer:

```bash
sudo scripts/install-edex-service-linux.sh
```

The installer performs these actions:

- installs Debian/Ubuntu packages and Node.js 22 when needed;
- creates the `edex` service user;
- copies the source tree to `/opt/edex-ui`;
- runs `npm run install-linux`;
- installs the systemd unit, runner, checker, and Nginx config;
- renders Nginx from `/etc/edex-ui/edex.env`;
- creates the Nginx password file;
- enables and starts `edex.service` and `nginx`.

## Verification

Run:

```bash
sudo check-edex-service.sh
```

Expected:

- `edex.service` is active.
- Nginx listens on `8443`.
- noVNC/Kasm and VNC backends listen on loopback.
- eDEX terminal WebSocket ports bind to `127.0.0.1`.
- Browser access prompts for username/password and displays eDEX-UI.

Repo-local deployment contract tests:

```bash
npm run test:linux-service
```

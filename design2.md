# eDEX-UI Linux LAN Service Design

## Purpose

This design defines a Linux-only service deployment for eDEX-UI. The service runs on Debian/Ubuntu and presents eDEX-UI to LAN browsers through an authenticated HTTPS endpoint.

The design does not use AppImage and does not attempt to rewrite eDEX-UI into a web application. eDEX-UI continues to run as an Electron desktop app on a virtual Linux display.

## Supported Environment

- Debian 12 or Ubuntu 24.04.
- LXD/LXC, Proxmox LXC, VM, or bare-metal Linux.
- systemd.
- Node.js 22.
- Nginx.
- Xorg dummy or Xvfb.
- Openbox.
- x11vnc/noVNC fallback, with optional KasmVNC.

## Architecture

```text
LAN browser
  -> HTTPS Basic Auth on Nginx port 8443
      -> browser VNC gateway on 127.0.0.1:6080
          -> VNC server on 127.0.0.1:5901
              -> virtual display :1
                  -> Openbox
                      -> eDEX-UI Electron process
                          -> node-pty shell
                          -> terminal WebSockets on 127.0.0.1:3000-3006
```

## Security Design

Only `8443/tcp` is intended for LAN access.

Private ports:

```text
3000-3006/tcp  eDEX terminal WebSockets
5901/tcp       raw VNC
6080/tcp       browser VNC backend
```

Security controls:

- Nginx Basic Auth protects the browser endpoint.
- TLS is enabled with the local snakeoil certificate by default.
- eDEX internal WebSocket servers bind to loopback.
- VNC and noVNC backends bind to loopback.
- Direct public internet exposure is out of scope.

## Installation Design

The installer script:

```bash
sudo scripts/install-edex-service-linux.sh
```

Responsibilities:

- install Debian/Ubuntu packages;
- install Node.js 22 when required;
- create the `edex` service user;
- copy source to `/opt/edex-ui`;
- run `npm run install-linux`;
- install `/etc/edex-ui/edex.env`;
- install `edex.service`;
- install Nginx auth/proxy configuration;
- enable and start services.

## Runtime Design

Configuration lives in:

```text
/etc/edex-ui/edex.env
```

Defaults:

```bash
EDEX_APP_DIR=/opt/edex-ui
EDEX_HOME=/var/lib/edex-ui
EDEX_DISPLAY=:1
EDEX_RESOLUTION=1600x900
EDEX_DEPTH=24
EDEX_DISPLAY_BACKEND=auto
EDEX_VNC_STACK=auto
EDEX_WEB_PORT=8443
EDEX_ELECTRON_FLAGS=--nointro --no-sandbox
```

Service state lives in:

```text
/var/lib/edex-ui
```

## Verification Design

The checker script:

```bash
sudo check-edex-service.sh
```

It reports:

- service status;
- LAN URL;
- GPU render node visibility;
- listener ports;
- relevant processes;
- recent `edex.service` journal entries.

Acceptance criteria:

- `edex.service` is active.
- Nginx listens on `8443`.
- browser opens `https://<server-ip>:8443/`;
- login prompt appears;
- eDEX UI is visible after login;
- ports `3000-3006`, `5901`, and `6080` are not LAN-exposed.


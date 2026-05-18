# Linux-Native eDEX-UI LAN Service Architecture

## Summary

This architecture runs eDEX-UI as a persistent Debian/Ubuntu Linux service and serves it to LAN browsers through an authenticated HTTPS endpoint. eDEX-UI remains an Electron desktop app; browser users see a streamed virtual display, not a rewritten web app.

## Target Platform

- Debian 12 or Ubuntu 24.04.
- LXD/LXC, Proxmox LXC, VM, or bare-metal Linux.
- systemd for service management.
- Nginx for TLS and Basic Auth.
- Xorg dummy or Xvfb for the virtual display.
- x11vnc/noVNC by default, with optional KasmVNC when available.

## Component Model

```text
Browser on LAN
  -> Nginx HTTPS on 8443
      -> noVNC/Kasm backend on 127.0.0.1:6080
          -> VNC on 127.0.0.1:5901
              -> X11 display :1
                  -> Openbox
                      -> eDEX-UI Electron
                          -> shell WebSockets on 127.0.0.1:3000-3006
```

Only `8443/tcp` is LAN-facing. Raw VNC, noVNC backend ports, and eDEX terminal WebSockets remain loopback-only.

## Files Implemented

- `deploy/linux/edex.env`
- `deploy/linux/edex.service`
- `deploy/linux/nginx-edex.conf`
- `scripts/install-edex-service-linux.sh`
- `scripts/run-edex-session-linux.sh`
- `scripts/check-edex-service.sh`
- `docs/lan-service-deployment.md`
- `docs/linux-debian-service-setup.md`

## Runtime Defaults

- Service user: `edex`
- App path: `/opt/edex-ui`
- Persistent home: `/var/lib/edex-ui`
- Display: `:1`
- Resolution: `1600x900x24`
- Browser URL: `https://<server-ip>:8443/`
- Build command: `npm run install-linux`
- Electron flags: `--nointro --no-sandbox`

## Security Posture

- Nginx Basic Auth protects browser entry.
- Internal terminal WebSocket server binds to `127.0.0.1`.
- VNC and noVNC backend ports bind to loopback.
- Public internet exposure requires a separate VPN or identity-aware gateway.


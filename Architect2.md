# Linux Deployment Runbook Architecture

## Core Principle

eDEX-UI is an Electron desktop application. The Linux service does not serve `ui.html` directly to browsers. It starts a complete Linux graphical session and streams that session to the browser.

## Layered Design

1. Debian/Ubuntu systemd host starts `edex.service`.
2. `edex.service` loads `/etc/edex-ui/edex.env`.
3. `run-edex-session-linux.sh` starts Xorg dummy or Xvfb.
4. Openbox provides a minimal window manager.
5. eDEX starts from `/opt/edex-ui`.
6. x11vnc/noVNC or KasmVNC exposes the virtual display on loopback.
7. Nginx exposes `https://<server-ip>:8443/` with Basic Auth.

## Display Decision

Use this order:

- `EDEX_DISPLAY_BACKEND=auto` for normal deployment.
- Xorg dummy is attempted when `/dev/dri/renderD128` exists.
- Xvfb is the fallback and the safest choice for containers.
- Keep `1600x900` unless `1920x1080` has been tested on the target hardware.

## Network Decision

Expose only:

```text
8443/tcp
```

Keep private:

```text
3000-3006/tcp
5901/tcp
6080/tcp
```

The service is LAN-first. Remote access should be layered through VPN or another authenticated gateway.

## Operational Decision

The service is intentionally single-session:

- browser disconnects should not stop eDEX;
- reconnecting should return to the same running Linux desktop session;
- restarting `edex.service` resets the virtual display and shell session;
- persistent files and eDEX config live under `/var/lib/edex-ui`.

## Acceptance Criteria

- Fresh Debian/Ubuntu install completes with `scripts/install-edex-service-linux.sh`.
- `systemctl status edex.service` is healthy.
- `sudo check-edex-service.sh` reports the expected listeners.
- LAN browser opens `https://<server-ip>:8443/` and prompts for credentials.
- eDEX terminal WebSocket listeners are loopback-only.


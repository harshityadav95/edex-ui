# Linux Service Migration Notes

## Migration Goal

Move from desktop-only usage to a Linux service deployment where eDEX-UI is available from LAN browsers with username/password authentication.

## What Changes

- Source-service installation is the supported Linux path.
- systemd owns the lifecycle.
- `/etc/edex-ui/edex.env` owns runtime settings.
- `/var/lib/edex-ui` owns persistent service state.
- Nginx owns the LAN-facing authenticated HTTPS endpoint.
- Internal shell WebSockets bind to loopback only.

## What Does Not Change

- eDEX remains an Electron app.
- The terminal backend still uses local WebSockets and `node-pty`.
- The renderer still runs inside Electron.
- The browser sees a streamed desktop session, not a web-native rewrite.

## Rollout Sequence

1. Create Debian/Ubuntu target.
2. Clone the repo.
3. Run `sudo scripts/install-edex-service-linux.sh`.
4. Confirm `edex.service` and `nginx` are active.
5. Open `https://<server-ip>:8443/`.
6. Run `sudo check-edex-service.sh`.
7. Tune `/etc/edex-ui/edex.env` if needed.

## Rollback

Disable the service:

```bash
sudo systemctl disable --now edex.service
sudo systemctl disable --now nginx
```

Remove installed service files if needed:

```bash
sudo rm -f /etc/systemd/system/edex.service
sudo rm -f /etc/nginx/sites-enabled/edex-ui
sudo rm -f /etc/nginx/sites-available/edex-ui
sudo systemctl daemon-reload
```

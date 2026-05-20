# eDEX-UI Debian/Ubuntu Service Setup

This is the primary runbook for running eDEX-UI as a Linux service and opening it from a LAN browser with username/password authentication. It also covers forwarding the same browser-rendered noVNC endpoint through Cloudflare Tunnel.

eDEX-UI is an Electron desktop application. This setup runs it on a virtual Linux display, streams that display through VNC/noVNC, and exposes a single authenticated Nginx HTTPS endpoint. Linux support is installed from source as a Debian/Ubuntu service.

## 1. Target System

Use one of:

- Debian 12 server or container.
- Ubuntu 24.04 server or container.
- LXD/LXC container.
- Proxmox LXC container.
- VM or bare-metal Linux host.

Minimum resources:

- 2 vCPU.
- 2 GB RAM.
- 10 GB disk.

Recommended resources:

- 2-4 vCPU.
- 4 GB RAM.
- Optional `/dev/dri/renderD*` GPU render node.

## 2. Prepare A Container Or Host

LXD example:

```bash
lxc launch ubuntu:24.04 edex-ui
lxc config set edex-ui security.nesting true
lxc config set edex-ui limits.cpu 2
lxc config set edex-ui limits.memory 2GiB
lxc exec edex-ui -- bash
```

Optional LXD GPU passthrough:

```bash
lxc config device add edex-ui gpu gpu
lxc restart edex-ui
```

Proxmox LXC notes:

- Enable nesting.
- Use Debian 12 or Ubuntu 24.04.
- Pass `/dev/dri/renderD128` only if hardware rendering is required.
- Ensure the container user can read the render device.

VM or bare-metal notes:

- Use the same installer.
- Open only port `8443/tcp` in the firewall for LAN use.
- For Cloudflare Tunnel use, no inbound port is required; `cloudflared` connects outbound to Cloudflare and forwards to local Nginx.

## 3. Clone The Repo

Inside the Debian/Ubuntu target:

```bash
apt update
apt install -y git sudo ca-certificates
git clone https://github.com/harshityadav95/edex-ui.git /root/edex-ui
cd /root/edex-ui
```

If the source is already available locally, copy it into the target and run commands from the repo root.

## 4. Install The Service

Interactive password prompt:

```bash
sudo scripts/install-edex-service-linux.sh
```

Non-interactive login setup:

```bash
sudo EDEX_WEB_USER=operator EDEX_WEB_PASSWORD='change-this-password' scripts/install-edex-service-linux.sh
```

The installer will:

- install Node.js 22 and required Debian/Ubuntu packages;
- create the `edex` service user;
- install source into `/opt/edex-ui`;
- build eDEX with `pnpm run install-linux`;
- install `/etc/edex-ui/edex.env`;
- install `edex.service`;
- install Nginx auth and proxy config;
- enable and start `edex.service` and `nginx`.

## 5. Open eDEX From The LAN

Find the server IP:

```bash
hostname -I
```

Open:

```text
https://<server-ip>:8443/vnc.html?autoconnect=1&resize=remote&path=websockify
```

Accept the local certificate warning, then log in with the configured username/password.

The installer and checker also print the exact URLs:

```bash
sudo check-edex-service.sh
```

## 6. Manage The Service

Status:

```bash
sudo systemctl status edex.service
sudo systemctl status nginx
```

Restart:

```bash
sudo systemctl restart edex.service nginx
```

Logs:

```bash
sudo journalctl -u edex.service -f
```

Health check:

```bash
sudo check-edex-service.sh
```

## 7. Configure Runtime Settings

Edit:

```bash
sudo nano /etc/edex-ui/edex.env
```

Common settings:

```bash
EDEX_RESOLUTION=1600x900
EDEX_DEPTH=24
EDEX_DISPLAY_BACKEND=auto
EDEX_VNC_STACK=novnc
EDEX_RAW_VNC_HOST=127.0.0.1
EDEX_WEB_PORT=8443
EDEX_ELECTRON_FLAGS="--no-sandbox"
```

Display backend choices:

- `EDEX_DISPLAY_BACKEND=auto`: try Xorg dummy with GPU render node, otherwise Xvfb.
- `EDEX_DISPLAY_BACKEND=xvfb`: most compatible software display path.
- `EDEX_DISPLAY_BACKEND=xorg-dri`: use only after GPU passthrough works.

VNC stack choices:

- `EDEX_VNC_STACK=novnc`: use x11vnc plus noVNC. This is the default Debian/Ubuntu service profile.
- `EDEX_VNC_STACK=auto`: prefer KasmVNC if configured, otherwise noVNC fallback.
- `EDEX_VNC_STACK=kasm`: require KasmVNC.

Apply changes:

```bash
sudo systemctl restart edex.service
sudo render-edex-nginx-config.sh
sudo nginx -t
sudo systemctl reload nginx
```

If you installed from a different source path, run `render-edex-nginx-config.sh` with that repo's `deploy/linux/nginx-edex.conf` template as the first argument.

## 8. Cloudflare Tunnel

Cloudflare Tunnel browser origins should use the LAN IP and HTTPS web port when `cloudflared` runs on a different machine than eDEX/Nginx. In that setup, `localhost` points at the `cloudflared` machine, not the eDEX service host:

```text
https://<server-ip>:8443
```

With the generated self-signed Nginx certificate, set `noTLSVerify` on the tunnel origin:

```yaml
ingress:
  - hostname: edex.example.com
    service: https://<server-ip>:8443
    originRequest:
      noTLSVerify: true
  - service: http_status:404
```

After the noVNC tunnel is created, open the Cloudflare hostname with:

```text
https://<cloudflare-hostname>/vnc.html?autoconnect=1&resize=remote&path=websockify
```

For a raw VNC client, use the VNC port only when you explicitly need direct VNC. Raw VNC is loopback-only by default and must be enabled intentionally before another LAN machine, including a separate `cloudflared` host, can reach it:

```bash
EDEX_RAW_VNC_HOST=0.0.0.0
EDEX_VNC_PASSWORD_FILE=/var/lib/edex-ui/.vnc/passwd
```

Create the password file as the service user:

```bash
sudo -u edex install -d -m 0700 /var/lib/edex-ui/.vnc
sudo -u edex x11vnc -storepasswd /var/lib/edex-ui/.vnc/passwd
```

Then configure the Cloudflare Tunnel raw VNC service as:

```text
tcp://<server-ip>:5901
```

Set `EDEX_PUBLIC_HOSTNAME=edex.example.com` in `/etc/edex-ui/edex.env` if you want `check-edex-service.sh` to print the final Cloudflare browser URL.

## 9. Network Security

Expose only:

```text
8443/tcp
```

Keep these private:

```text
3000-3006/tcp  internal eDEX shell WebSockets
5901/tcp       raw VNC
6080/tcp       noVNC/Kasm backend
```

The service binds internal eDEX terminal WebSockets to `127.0.0.1`. The VNC/noVNC backend also binds to loopback. Keep firewall and port-forwarding rules aligned with that model.

For remote access outside the LAN, use a VPN or identity-aware gateway rather than direct public port forwarding.

## 10. Troubleshooting

If the browser opens but eDEX does not appear:

```bash
sudo journalctl -u edex.service -n 200 --no-pager
```

If Nginx fails:

```bash
sudo nginx -t
sudo systemctl status nginx
```

If the Cloudflare hostname opens but the VNC canvas does not connect, confirm that the URL includes:

```text
path=websockify
```

Then check:

```bash
sudo check-edex-service.sh
```

If Electron reports sandbox errors inside an unprivileged container, keep:

```bash
EDEX_ELECTRON_FLAGS="--no-sandbox"
```

If performance is poor:

- keep `EDEX_RESOLUTION=1600x900`;
- disable audio with `EDEX_DISABLE_AUDIO=true`;
- pass through `/dev/dri/renderD128` if available;
- compare results with `sudo check-edex-service.sh`.

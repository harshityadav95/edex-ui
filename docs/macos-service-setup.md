# eDEX-UI macOS Service Setup

This runbook covers the macOS service profile for opening eDEX-UI from a browser on the same Mac or from another device on the LAN.

macOS does not provide a Linux-style Xvfb display for native Electron apps. This profile therefore runs eDEX-UI in the logged-in user's Aqua session and exposes the active Mac screen through native macOS Screen Sharing plus noVNC. Browser clients see and control the active Mac desktop session.

## 1. Requirements

- macOS with a logged-in desktop user.
- Homebrew.
- Screen Sharing enabled by the user in System Settings.
- LAN devices allowed to reach the Mac on the configured noVNC HTTP port.

Do not run the macOS installer with `sudo`. The service is installed as a per-user LaunchAgent.

## 2. Enable Screen Sharing

Open System Settings:

1. General > Sharing.
2. Enable Screen Sharing.
3. Open Screen Sharing settings / Computer Settings.
4. Enable `VNC viewers may control screen with password`.
5. Set a dedicated VNC password.

Use a VNC password that is not the same as your macOS login password.

## 3. Install The Service

From the repo root on the Mac:

```bash
./start.sh
```

or:

```bash
scripts/install-edex-service-darwin.sh
```

The installer will:

- install Homebrew dependencies for Node.js and Python;
- copy the app into `~/Library/Application Support/eDEX-UI-Service/app`;
- run `npm run install-darwin`;
- install pinned noVNC and websockify;
- install per-user LaunchAgents;
- start the menu-bar controller;
- start the eDEX service when Screen Sharing is already ready.

If Screen Sharing is not ready, the installer leaves the eDEX session service disabled and prints the manual setup steps. After enabling Screen Sharing, start the service from the top-bar menu or run:

```bash
"$HOME/Library/Application Support/eDEX-UI-Service/bin/edex-service-darwin.sh" start
```

## 4. Top-Bar Controller

The controller appears as an eDEX icon in the macOS top bar. It provides:

- Start Service
- Stop Service
- Restart Service
- Open Local URL
- Open LAN URL
- Copy Local URL
- Copy LAN URL
- Status / Setup Check

The controller is separate from the fullscreen eDEX app, so stopping the service does not quit the controller.

## 5. Browser URLs

Local browser URL:

```text
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=remote&path=websockify
```

LAN browser URL:

```text
http://<mac-lan-ip>:6080/vnc.html?autoconnect=1&resize=remote&path=websockify
```

The noVNC page connects to macOS Screen Sharing. Enter the VNC password configured in System Settings when prompted.

## 6. Manage From Terminal

```bash
SERVICE="$HOME/Library/Application Support/eDEX-UI-Service/bin/edex-service-darwin.sh"

"$SERVICE" status
"$SERVICE" start
"$SERVICE" stop
"$SERVICE" restart
"$SERVICE" urls
"$SERVICE" check
```

Logs are written under:

```text
~/Library/Logs/eDEX-UI-Service
```

LaunchAgents are installed under:

```text
~/Library/LaunchAgents/com.edex-ui.session.plist
~/Library/LaunchAgents/com.edex-ui.controller.plist
```

## 7. Configuration

Runtime configuration lives in:

```text
~/Library/Application Support/eDEX-UI-Service/edex.env
```

Common settings:

```bash
EDEX_WEB_HOST=0.0.0.0
EDEX_WEB_PORT=6080
EDEX_MAC_VNC_HOST=127.0.0.1
EDEX_MAC_VNC_PORT=5900
EDEX_ELECTRON_FLAGS="--nointro"
```

After changing config, restart the service:

```bash
"$HOME/Library/Application Support/eDEX-UI-Service/bin/edex-service-darwin.sh" restart
```

## 8. Security Notes

This macOS profile serves noVNC over HTTP by request. Use it only on a trusted LAN or behind a VPN.

The browser endpoint exposes access to the active Mac desktop session through Screen Sharing. Anyone who can reach the noVNC page and knows the VNC password can control that session.

For always-on LAN use, configure macOS power settings so the Mac does not sleep while the service should remain reachable.

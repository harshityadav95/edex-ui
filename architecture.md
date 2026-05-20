# eDEX-UI Service Architecture Reference

This document defines the architecture, component model, and operational specifications for running eDEX-UI as a persistent service on Debian/Ubuntu Linux and macOS (Darwin).

## 1. Core Architecture Principle

eDEX-UI is an Electron-based desktop terminal emulator application. It is not designed to be compiled or run natively as a server-side web application. 

To make eDEX-UI accessible over the network (e.g., in a LAN environment or browser tab), this project runs the complete desktop application inside a **virtual graphical session** on the host, and streams that session to client web browsers using a VNC-to-WebSocket gateway (noVNC).

---

## 2. Linux LAN Service Architecture

On Linux (Debian 12 or Ubuntu 24.04), eDEX-UI runs as a persistent service managed by `systemd` and fronted by `Nginx`.

### Component Model

```text
LAN Browser / Client
   │ (HTTPS / port 8443)
   ▼
[ Nginx Reverse Proxy & TLS / Basic Auth ]
   │ (Proxy to Loopback / port 6080)
   ▼
[ noVNC / Kasm Web Gateway ]
   │ (WebSockets / port 6080)
   ▼
[ VNC Server (x11vnc or KasmVNC) ]
   │ (RFB / port 5901)
   ▼
[ Virtual X11 Display (:1) ]
   │
   ├─► [ Openbox Window Manager ] (Provides window focus/boundaries)
   └─► [ eDEX-UI Electron Process ]
           │
           └─► [ node-pty ] (Native shell execution backend)
```

### Display Backends
The service runner automatically determines how to initialize the virtual X11 server using `EDEX_DISPLAY_BACKEND`:
- **Xorg dummy**: Preloaded if GPU rendering nodes (like `/dev/dri/renderD128`) are present.
- **Xvfb**: The fallback and safest choice for headless environments, Docker containers, and virtual machines.

### Security Controls
- **TLS & Basic Authentication**: Enforced by Nginx at the ingress boundary (default port `8443`).
- **Loopback Binding**: VNC (`5901`), noVNC (`6080`), and eDEX terminal WebSocket server ports (`3000-3006`) are explicitly bound to `127.0.0.1`.
- **User Sandboxing**: The entire session and Electron app run under a dedicated, low-privilege `edex` system user.

---

## 3. macOS (Darwin) Service Architecture

On macOS, the service integrates with native macOS capabilities (such as macOS Screen Sharing / VNC engine) and runs under the user's GUI session using `launchd`.

### Component Model

```text
LAN Browser / Client
   │ (HTTP / port 6080)
   ▼
[ noVNC Web Gateway ] (Static files served via WebSockets)
   │ (WebSockets / port 6080)
   ▼
[ python3 websockify Venv ]
   │ (Translates WebSockets to raw VNC)
   ▼
[ macOS Native Screen Sharing (VNC) ] (port 5900)
   │
   ▼
[ macOS User GUI Session ]
   │
   ├─► [ macOS Window Server (Quartz) ]
   ├─► [ eDEX-UI Electron Process ]
   └─► [ eDEX-UI Menu-Bar Controller ] (macOS status item control UI)
```

### LaunchAgent Design
Two per-user LaunchAgents manage the system:
1. `com.edex-ui.controller.plist`: Launches and keeps the macOS menu-bar controller active.
2. `com.edex-ui.session.plist`: Runs the session runner script (`run-edex-session-darwin.sh`), which boots `websockify`, `noVNC`, and the main eDEX Electron app.

### Security Controls
- **macOS Screen Sharing Authentication**: Uses the system VNC viewer password configuration.
- **Local Loopback Only**: The `websockify` gateway bridges connections locally to `127.0.0.1:5900`, preventing direct raw VNC exposure on the network.

---

## 4. Package & Build Architecture

To facilitate modern dependency management and fast builds, this project utilizes `pnpm` project-wide.

### Hoisted Layout (`node-linker=hoist`)
Electron uses Node.js native add-ons (like `node-pty` for terminal execution and `osx-temperature-sensor` for telemetry). By default, `pnpm` installs modules into a content-addressable store and links them using symbolic links.

Because Electron packaging/rebuild tools (`electron-rebuild` and `electron-builder`) require physical dependency structures, the project sets `node-linker=hoist` in `.npmrc` files. This instructs `pnpm` to construct a flat, physical `node_modules` structure similar to `npm`, ensuring compatibility with Electron native module compilation.

### Build Scripts Flow
- **install-linux / install-darwin**: Runs `pnpm install` in the root, followed by `pnpm install` in the `src/` app directory, and completes by triggering `electron-rebuild` to compile native C++ modules against the matching Electron headers.
- **prebuild-darwin**: Prepares and minifies source code into `prebuild-src` for distribution packaging.

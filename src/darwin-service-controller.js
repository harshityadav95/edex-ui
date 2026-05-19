const {app, Tray, Menu, shell, clipboard, nativeImage, dialog} = require("electron");
const {execFile} = require("child_process");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const serviceCli = process.env.EDEX_SERVICE_CLI || path.join(repoRoot, "scripts", "edex-service-darwin.sh");
let tray = null;
let serviceStatus = "checking";

function runService(args) {
    return new Promise(resolve => {
        execFile(serviceCli, args, {env: process.env}, (error, stdout, stderr) => {
            resolve({
                ok: !error,
                stdout: stdout.trim(),
                stderr: stderr.trim(),
                error
            });
        });
    });
}

async function getText(command) {
    const result = await runService([command]);
    if (!result.ok) {
        throw new Error(result.stderr || result.stdout || result.error.message);
    }
    return result.stdout;
}

async function refreshStatus() {
    const result = await runService(["status"]);
    serviceStatus = result.ok ? (result.stdout || "unknown") : "error";
    buildMenu();
}

function showError(title, message) {
    dialog.showErrorBox(title, message || "Command failed.");
}

async function serviceAction(command) {
    const result = await runService([command]);
    if (!result.ok) {
        showError("eDEX Service", result.stderr || result.stdout || result.error.message);
    }
    await refreshStatus();
}

async function openUrl(command) {
    try {
        const url = await getText(command);
        await shell.openExternal(url);
    } catch (error) {
        showError("eDEX Service URL", error.message);
    }
}

async function copyUrl(command) {
    try {
        clipboard.writeText(await getText(command));
    } catch (error) {
        showError("eDEX Service URL", error.message);
    }
}

async function showCheck() {
    const result = await runService(["check"]);
    dialog.showMessageBox({
        type: result.ok ? "info" : "warning",
        title: "eDEX Service Status",
        message: "eDEX Service Status",
        detail: result.stdout || result.stderr || "No status output.",
        buttons: ["OK"]
    });
}

function buildMenu() {
    if (!tray) return;

    const running = serviceStatus === "running";
    const label = `Status: ${serviceStatus}`;

    tray.setToolTip(`eDEX Service (${serviceStatus})`);
    tray.setContextMenu(Menu.buildFromTemplate([
        {label, enabled: false},
        {type: "separator"},
        {label: "Start Service", enabled: !running, click: () => serviceAction("start")},
        {label: "Stop Service", enabled: running, click: () => serviceAction("stop")},
        {label: "Restart Service", click: () => serviceAction("restart")},
        {type: "separator"},
        {label: "Open Local URL", click: () => openUrl("local-url")},
        {label: "Open LAN URL", click: () => openUrl("lan-url")},
        {label: "Copy Local URL", click: () => copyUrl("local-url")},
        {label: "Copy LAN URL", click: () => copyUrl("lan-url")},
        {type: "separator"},
        {label: "Status / Setup Check", click: showCheck},
        {label: "Refresh", click: refreshStatus},
        {type: "separator"},
        {label: "Quit Controller", click: () => app.quit()}
    ]));
}

function createTray() {
    const iconPath = path.join(repoRoot, "media", "icon.icns");
    let image = nativeImage.createFromPath(iconPath);
    if (!image.isEmpty()) {
        image = image.resize({width: 18, height: 18});
    }

    tray = new Tray(image);
    buildMenu();
}

app.whenReady().then(() => {
    if (process.platform === "darwin" && app.dock) {
        app.dock.hide();
    }
    createTray();
    refreshStatus();
    setInterval(refreshStatus, 15000);
});

app.on("window-all-closed", event => {
    event.preventDefault();
});

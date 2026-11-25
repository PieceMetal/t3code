// @effect-diagnostics nodeBuiltinImport:off - The Windows token check runs synchronously before the desktop runtime loads.
import * as NodeChildProcess from "node:child_process";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import { app, dialog } from "electron";

function startDesktop() {
  require("./compileCache.cjs");
  require("./main.cjs");
}

// oxlint-disable-next-line t3code/no-global-process-runtime -- Bootstrap must select the Windows launcher before the runtime loads.
if (process.platform !== "win32" || !app.isPackaged) {
  startDesktop();
} else {
  // Route Explorer, taskbar and direct EXE launches through the same Windows token check.
  const prepared = process.env.LOCAL_AGENT_DESK_DESKTOP_READY === "1";
  const powershell = NodePath.join(
    process.env.SystemRoot ?? "C:\\Windows",
    "System32",
    "WindowsPowerShell",
    "v1.0",
    "powershell.exe",
  );
  const result = NodeChildProcess.spawnSync(
    powershell,
    [
      "-NoLogo",
      "-NoProfile",
      "-NonInteractive",
      "-WindowStyle",
      "Hidden",
      "-File",
      NodePath.join(process.resourcesPath, "Start-LocalAgentDesk.ps1"),
      "-Desktop",
      prepared ? "-VerifyDesktop" : "-Prepare",
    ],
    { windowsHide: true, timeout: 30_000, stdio: "ignore" },
  );
  if (result.status !== 0) {
    dialog.showErrorBox(
      "Local Agent Desk",
      "Windows could not start the desktop app with standard-user rights. Check the app and private data directory permissions.",
    );
    app.exit(1);
  } else if (!prepared) {
    app.exit(0);
  } else {
    delete process.env.VITE_DEV_SERVER_URL;
    process.env.T3CODE_HOME = NodePath.join(NodeOS.homedir(), ".local-agent-desk", "data");
    process.env.T3CODE_PORT = "48773";
    process.env.T3CODE_NO_BROWSER = "true";
    startDesktop();
  }
}

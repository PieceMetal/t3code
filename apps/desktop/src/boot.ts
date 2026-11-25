import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";
import { app, dialog } from "electron";

function startDesktop() {
  require("./compileCache.cjs");
  require("./main.cjs");
}

if (process.platform !== "win32" || !app.isPackaged) {
  startDesktop();
} else {
  // Route Explorer, taskbar and direct EXE launches through the same Windows token check.
  const prepared = process.env.LOCAL_AGENT_DESK_DESKTOP_READY === "1";
  const powershell = join(
    process.env.SystemRoot ?? "C:\\Windows",
    "System32",
    "WindowsPowerShell",
    "v1.0",
    "powershell.exe",
  );
  const result = spawnSync(
    powershell,
    [
      "-NoLogo",
      "-NoProfile",
      "-NonInteractive",
      "-WindowStyle",
      "Hidden",
      "-File",
      join(process.resourcesPath, "Start-LocalAgentDesk.ps1"),
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
    process.env.T3CODE_HOME = join(homedir(), ".local-agent-desk", "data");
    process.env.T3CODE_PORT = "48773";
    process.env.T3CODE_NO_BROWSER = "true";
    startDesktop();
  }
}

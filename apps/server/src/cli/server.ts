import * as HostProcess from "@t3tools/shared/HostProcess";
import { windowsPowerShellPath } from "@t3tools/shared/windowsSystem";
import * as Effect from "effect/Effect";
import * as FileSystem from "effect/FileSystem";
import * as Option from "effect/Option";
import * as Schema from "effect/Schema";
import { Command, GlobalFlag } from "effect/cli";
import * as CliError from "effect/cli/CliError";

import { awaitServiceLauncherStop } from "../cloud/serviceLauncherClient.ts";
import * as ServerConfig from "../config.ts";
import { stopOnLauncherLoss } from "../launcherWatch.ts";
import * as DatabaseMaintenance from "../persistence/DatabaseMaintenance.ts";
import * as ProcessRunner from "../processRunner.ts";
import * as AutomaticPort from "./automaticPort.ts";
import { type CliServerFlags, resolveServerConfig, sharedServerCommandFlags } from "./config.ts";

const encodeCommand = Schema.encodeEffect(Schema.fromJsonString(Schema.String));

// A direct Windows invocation must satisfy the same OS boundary as the packaged launcher.
const checkWindowsProcessRights = Effect.gen(function* () {
  if ((yield* HostProcess.Platform) !== "win32") return;
  const reader = yield* ProcessRunner.ProcessRunner;
  const command = [
    "$ErrorActionPreference = 'Stop'",
    "$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())",
    "if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 1 }",
    "$whoami = [IO.Path]::Combine([Environment]::SystemDirectory, 'whoami.exe')",
    "$groups = & $whoami /groups /fo csv /nh",
    "if ($LASTEXITCODE -ne 0) { exit 1 }",
    String.raw`$label = [regex]::Match(($groups -join ' '), '"S-1-16-(\d+)"')`,
    "if (-not $label.Success -or [int]$label.Groups[1].Value -gt 8192) { exit 1 }",
    "[Console]::WriteLine('standard')",
  ].join("\n");
  const result = yield* reader.run({
    command: windowsPowerShellPath(yield* HostProcess.Environment),
    args: [
      "-NoLogo",
      "-NoProfile",
      "-NonInteractive",
      "-WindowStyle",
      "Hidden",
      "-Command",
      command,
    ],
    timeout: "10 seconds",
  });
  if (result.code !== 0 || result.stdout.trim() !== "standard") {
    return yield* new CliError.UserError({
      cause:
        "Open Start T3 Agent Desk.cmd. The server requires standard-user rights and medium or lower Windows integrity.",
    });
  }
}).pipe(Effect.provide(ProcessRunner.layer));

const runServerCommand = Effect.fn("server.runServerCommand")(function* (
  flags: CliServerFlags,
  options?: {
    readonly startupPresentation?: ServerConfig.StartupPresentation;
    readonly forceAutoBootstrapProjectFromCwd?: boolean;
    readonly rejectRunningServer?: boolean;
  },
) {
  // Before config resolution, which claims a port and creates directories.
  yield* checkWindowsProcessRights;
  const { runServer } = yield* Effect.promise(() => import("../server.ts"));
  const logLevel = yield* GlobalFlag.LogLevel;
  const selectAutomaticPort = yield* AutomaticPort.make.pipe(Effect.provide(ProcessRunner.layer));
  const config = yield* resolveServerConfig(flags, logLevel, { ...options, selectAutomaticPort });
  const run = Effect.raceFirst(
    runServer.pipe(Effect.provideService(ServerConfig.ServerConfig, config)),
    awaitServiceLauncherStop().pipe(Effect.andThen(Effect.interrupt)),
  ).pipe(
    // Settings' Reclaim stops the server; repair once the database is closed, before the restart.
    Effect.ensuring(
      DatabaseMaintenance.runRequestedReclaim(config.dbPath).pipe(
        Effect.provide(DatabaseMaintenance.layer),
      ),
    ),
  );
  if (config.mode !== "desktop" || config.desktopBootstrapToken === undefined) return yield* run;
  return yield* stopOnLauncherLoss(run);
});

export const runDefaultServerCommand = Effect.fn("server.runDefaultServerCommand")(function* (
  flags: CliServerFlags,
) {
  if (Option.isSome(flags.cwd)) {
    const cwd = flags.cwd.value.trim();
    const fs = yield* FileSystem.FileSystem;
    const platform = yield* HostProcess.Platform;
    const explicitPath =
      cwd === "." ||
      cwd === ".." ||
      cwd === "~" ||
      /[/\\]/.test(cwd) ||
      (platform === "win32" && /^[a-z]:/i.test(cwd));
    if (!explicitPath && (!(yield* fs.exists(cwd)) || (yield* fs.stat(cwd)).type !== "Directory")) {
      return yield* new CliError.UserError({
        cause: cwd,
        userMessage: `Unknown command ${yield* encodeCommand(cwd)}. Use "t3 --help" for commands or an explicit path such as "t3 ./my-project" for a new directory.`,
      });
    }
  }
  return yield* runServerCommand(flags, { rejectRunningServer: true });
});

export const startCommand = Command.make("start", { ...sharedServerCommandFlags }).pipe(
  Command.withDescription("Same as `t3`."),
  Command.unlisted,
  Command.withHandler((flags) => runServerCommand(flags, { rejectRunningServer: true })),
);

// Serve never bootstraps a project, so it does not offer the flag that asks for one.
const { autoBootstrapProjectFromCwd: _, ...serveCommandFlags } = sharedServerCommandFlags;

export const serveCommand = Command.make("serve", serveCommandFlags).pipe(
  Command.withShortDescription("Run T3 Agent Desk in this terminal, with no browser."),
  Command.withDescription(
    "Run T3 Agent Desk in this terminal without opening a browser, and print pairing details. The background service runs this. To set up access from your other devices, run `t3 up`.",
  ),
  Command.withHandler((flags) =>
    runServerCommand(
      { ...flags, autoBootstrapProjectFromCwd: Option.none() },
      {
        startupPresentation: "headless",
        forceAutoBootstrapProjectFromCwd: false,
      },
    ),
  ),
);

import {
  isAtomCommandInterrupted,
  squashAtomCommandFailure,
} from "@t3tools/client-runtime/state/runtime";
import type { EnvironmentThreadShell } from "@t3tools/client-runtime/state/models";
import { msg } from "gt-react";

import { stackedThreadToast, toastManager } from "../components/ui/toast";
import { m } from "../i18n/messages";
import { appAtomRegistry } from "../rpc/atomRegistry";
import { agentSessionImport } from "../state/agentSessions";
import { readEnvironmentProviders } from "../state/environments";
import { environmentPresentations } from "../state/presentation";
import { useAtomCommand } from "../state/use-atom-command";

export function canRefreshCodexHistory(thread: EnvironmentThreadShell) {
  return (
    thread.id.startsWith("import:") &&
    appAtomRegistry.get(environmentPresentations.serverConfigsAtom).get(thread.environmentId)
      ?.environment.capabilities.codexHistoryRefresh === true &&
    (readEnvironmentProviders(thread.environmentId)?.some(
      (provider) =>
        provider.instanceId === thread.providerInstanceId && provider.driver === "codex",
    ) ??
      thread.id.startsWith("import:codex:"))
  );
}

export function useRefreshCodexHistory() {
  const refresh = useAtomCommand(agentSessionImport, { reportFailure: false });
  return async (thread: EnvironmentThreadShell) => {
    if (!canRefreshCodexHistory(thread)) return;
    const result = await refresh({
      environmentId: thread.environmentId,
      input: { projectId: thread.projectId, threadId: thread.id },
    });
    if (result._tag === "Failure") {
      if (!isAtomCommandInterrupted(result)) {
        const error = squashAtomCommandFailure(result);
        toastManager.add(
          stackedThreadToast({
            type: "error",
            title: m(msg("Could not refresh Codex history")),
            description: error instanceof Error ? error.message : undefined,
          }),
        );
      }
      return;
    }
    toastManager.add(
      stackedThreadToast({
        type: result.value.skippedCount > 0 ? "error" : "success",
        title:
          result.value.skippedCount > 0
            ? m(msg("Could not refresh Codex history"))
            : result.value.importedCount > 0
              ? m(msg("Codex history updated"))
              : m(msg("Codex history is up to date")),
      }),
    );
  };
}

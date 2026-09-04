type GateApi = {
  on(
    event: "tool_call",
    handler: (
      event: { toolName: string },
      context: { sessionManager: { getSessionId(): string } },
    ) => { block: true; reason: string } | undefined,
  ): void;
};

const MUTATING_TOOLS = new Set(["edit", "write", "apply_patch"]);
const reminder =
  "Delegation gate: before the first file change in this session, decide whether delegation is useful. " +
  "If yes, state each lane or subagent's model, effort, scope, and parallelism, plus what stays in this session. " +
  "If delegation adds overhead, say why. Then retry the change.";

export default function delegationGate(pi: GateApi) {
  const promptedSessions = new Set<string>();

  pi.on("tool_call", (event, context) => {
    if (process.env.PIKIT_CHILD === "1" || !MUTATING_TOOLS.has(event.toolName)) return;
    const sessionId = context.sessionManager.getSessionId();
    if (promptedSessions.has(sessionId)) return;
    promptedSessions.add(sessionId);
    return { block: true as const, reason: reminder };
  });
}

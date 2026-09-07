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
  "Delegation gate: decide whether delegation is useful for this change; consult lanes_models or pickforge-lanes models for model and effort choices. Continue locally for tiny or tightly coupled work, or give a worker clear ownership. Retry the change without asking for permission again.";

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

/**
 * Delegation gate — blocks the first edit/write of the session and requests
 * the delegation plan from AGENTS.md "Model orchestration": chunks to lanes
 * or subagents with model and effort, what runs in parallel, what stays
 * in-session. The retry passes, so the gate fires exactly once per session.
 */
export default function (pi: any) {
  let planned = false;
  pi.on("tool_call", (event: any) => {
    if (event.toolName !== "edit" && event.toolName !== "write") return;
    if (planned) return;
    planned = true;
    return {
      block: true,
      reason:
        "Delegation gate: first edit of this session. Before implementing by hand, state the delegation plan: " +
        "1) Split the task: which self-contained chunks dispatch to lanes or subagents — model and effort for each, from the harness's model table — and which of them run in parallel. " +
        "2) The session's own model is the scarce pool, whichever model that is; route brute work outward to compatible lanes that are not the session's model. Spec-ready implementation goes to the cheapest capable lane at low effort under a written contract. " +
        "3) Say what stays in this session and why: taste-heavy ownership, synthesis, or a genuinely trivial change. " +
        "Load the model-orchestration skill for dispatch mechanics, present the plan, then retry the edit (the gate passes on retry this session).",
    };
  });
}

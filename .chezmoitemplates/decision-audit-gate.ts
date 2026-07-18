/**
 * Decision audit gate — blocks the first `git push` / `gh pr create` of the
 * session and requests the decision audit from AGENTS.md "Before finishing".
 * The retry passes, so the gate fires exactly once per session.
 */
export default function (pi: any) {
  let audited = false;
  pi.on("tool_call", (event: any) => {
    if (event.toolName !== "bash") return;
    const command = String(event.input?.command ?? "");
    const isShip =
      /\bgit\s+(?:-[cC]\s+\S+\s+|--?[\w-]+(?:=\S+)?\s+)*push\b|\bgh pr create\b/.test(
        command,
      );
    if (!isShip) return;
    if (audited) return;
    audited = true;
    return {
      block: true,
      reason:
        'Decision audit gate: before pushing or opening a PR, run the decision audit from AGENTS.md "Before finishing": ' +
        "1) Would you stand behind this branch as-is? If not, say exactly why. " +
        "2) List every choice the user or plan did not explicitly specify; flag low-confidence ones and plausible alternatives. " +
        "3) Surface incidental fixes (magic constants, coincidental sizes, special cases) as open decisions, not successes. " +
        "Present the audit to the user, then retry this command (the gate passes on retry this session).",
    };
  });
}

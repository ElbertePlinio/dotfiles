import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

// Injects the plan -> code -> review flow into the system prompt every run.
// Survives long sessions and compaction, unlike AGENTS.md context.
// Skipped inside subagent children so workers are not nagged to re-delegate.

const FLOW = `
## Model flow (enforced reminder)

For any non-trivial code change, run the loop automatically — never wait for a manual trigger:
1. Delegate planning to the \`planner\` agent (brief: files, approach, constraints, validation).
2. Delegate implementation to the \`coder\` agent with that brief. Do not write the implementation yourself.
3. Delegate the diff to the \`reviewer\` agent. Loop coder -> reviewer on corrections; after 3 failed loops, stop and report.

Skip the loop and handle directly: trivial edits (one-liners, typos, config tweaks), pure Q&A, and exploration.
Use the \`git\` agent for status/diff/commit-message chores. Pass compact artifacts, not transcripts.`;

export default function (pi: ExtensionAPI) {
	if (process.env.PI_SUBAGENT_CHILD) return;

	pi.on("before_agent_start", async (event) => {
		return { systemPrompt: event.systemPrompt + "\n" + FLOW };
	});
}

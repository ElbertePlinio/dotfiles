import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const TARGET_MODEL = {
  provider: "openai-codex",
  id: "gpt-5.6-sol",
} as const;
export const COMPACTION_THRESHOLD_TOKENS = 150_000;

type ModelRef = { provider: string; id: string } | undefined;

export function shouldAutoCompact(model: ModelRef, contextTokens: number | undefined): boolean {
  return (
    model?.provider === TARGET_MODEL.provider &&
    model.id === TARGET_MODEL.id &&
    contextTokens !== undefined &&
    contextTokens > COMPACTION_THRESHOLD_TOKENS
  );
}

export default function (pi: ExtensionAPI) {
  let compactionPending = false;

  pi.on("agent_end", (_event, ctx) => {
    if (compactionPending) return;

    const contextTokens = ctx.getContextUsage()?.tokens;
    if (!shouldAutoCompact(ctx.model, contextTokens)) return;

    compactionPending = true;
    ctx.compact({
      onComplete: () => {
        compactionPending = false;
      },
      onError: (error) => {
        compactionPending = false;
        if (ctx.hasUI) {
          ctx.ui.notify(`Automatic compaction failed: ${error.message}`, "error");
        }
      },
    });
  });
}

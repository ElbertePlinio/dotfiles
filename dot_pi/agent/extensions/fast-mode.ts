import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const STATE_ENTRY = "fast-mode-state";
const SUPPORTED_MODELS = new Set([
  "gpt-5.4",
  "gpt-5.5",
  "gpt-6-astra",
]);

type ModelRef = { provider: string; id: string } | undefined;

export function supportsFastMode(model: ModelRef): boolean {
  return model?.provider === "openai-codex" && SUPPORTED_MODELS.has(model.id);
}

export function applyFastServiceTier(payload: unknown): unknown {
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
    return payload;
  }
  return { ...payload, service_tier: "priority" };
}

export default function (pi: ExtensionAPI) {
  pi.registerFlag("fast", {
    description: "Enable OpenAI Codex Fast mode for this session",
    type: "boolean",
    default: false,
  });

  let enabled = pi.getFlag("fast") === true;

  const updateStatus = (ctx: { ui: { setStatus(key: string, value: string | undefined): void } }) => {
    ctx.ui.setStatus("fast-mode", enabled ? "fast" : undefined);
  };

  const save = (
    nextEnabled: boolean,
    ctx: { ui: { setStatus(key: string, value: string | undefined): void } },
  ) => {
    enabled = nextEnabled;
    pi.appendEntry(STATE_ENTRY, { enabled });
    updateStatus(ctx);
  };

  pi.on("session_start", (_event, ctx) => {
    enabled = pi.getFlag("fast") === true;
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type !== "custom" || entry.customType !== STATE_ENTRY) continue;
      const data = entry.data;
      if (typeof data === "object" && data !== null && "enabled" in data && typeof data.enabled === "boolean") {
        enabled = data.enabled;
      }
    }
    updateStatus(ctx);
  });

  pi.on("before_provider_request", (event, ctx) => {
    if (!enabled || !supportsFastMode(ctx.model)) return;
    return applyFastServiceTier(event.payload);
  });

  pi.registerCommand("fast", {
    description: "Control Codex Fast mode: /fast on|off|status",
    handler: async (args, ctx) => {
      const action = args.trim().toLowerCase() || "status";
      const modelName = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : "no model";

      if (action === "on") {
        if (!supportsFastMode(ctx.model)) {
          ctx.ui.notify(`Fast mode is unavailable for ${modelName}.`, "error");
          return;
        }
        save(true, ctx);
        ctx.ui.notify("Fast mode on: priority service tier enabled.", "warning");
        return;
      }

      if (action === "off") {
        save(false, ctx);
        ctx.ui.notify("Fast mode off.", "info");
        return;
      }

      if (action === "status") {
        const active = enabled && supportsFastMode(ctx.model);
        const detail = enabled && !active ? `on, but inactive for ${modelName}` : active ? `on for ${modelName}` : "off";
        ctx.ui.notify(`Fast mode: ${detail}.`, "info");
        return;
      }

      ctx.ui.notify("Usage: /fast on|off|status", "error");
    },
  });
}

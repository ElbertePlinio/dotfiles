/**
 * /btw — drop a side note to the agent without derailing the current work.
 *
 * - Agent idle: sends the note immediately as a normal user message.
 * - Agent streaming: queues it as steering, delivered after the current
 *   assistant turn finishes its tool calls (no interruption).
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("btw", {
    description: "Send a side note to the agent (queued as steering if it is busy)",
    handler: async (args, ctx) => {
      const note = args.trim();
      if (!note) {
        ctx.ui.notify("Usage: /btw <note>", "warning");
        return;
      }
      const message = `Btw (side note, do not drop current work): ${note}`;
      if (ctx.isIdle()) {
        pi.sendUserMessage(message);
      } else {
        pi.sendUserMessage(message, { deliverAs: "steer" });
        ctx.ui.notify("btw queued — delivered after the current turn", "info");
      }
    },
  });
}

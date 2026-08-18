// Enforces repository-independent model bans for lane dispatch.
//
// Every managed provider is available for repository and non-repository work.
// Selection belongs to orchestration policy; this module only blocks models that
// are explicitly retired or prohibited everywhere.

// Models banned everywhere: Anthropic Haiku, the GPT-5.6 Luna/Terra lanes, and
// retired Grok 4.5. Sol is the only GPT-5.6 lane.
const BANNED_MODEL = /haiku|luna|terra|grok-4\.5/i;

export function assertModelPermitted(model) {
  if (!BANNED_MODEL.test(String(model))) return;
  throw new Error(
    [
      `lane-policy: ${model} is a banned lane.`,
      "  Anthropic Haiku, GPT-5.6 Luna/Terra, and Grok 4.5 are never selectable;",
      "  use Sol for GPT-5.6 work and Grok 4.6 for xAI work.",
    ].join("\n"),
  );
}

// Kept as the dispatch-wrapper API. `cwd` no longer changes provider access.
export function assertModelAllowed(model, _cwd) {
  assertModelPermitted(model);
}

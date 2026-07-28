// Decides whether a non-approved provider may see this repository.
//
// The boundary is the git remote, not the directory. A worktree shares its
// repository's remote, so a client worktree parked under ~/Projects/.worktrees
// is restricted exactly like the repository it came from, and a personal clone
// keeps the full table wherever it lives.
//
// Fails closed: an unrecognised remote, a repository with no remote, and a
// directory that is not a repository at all are all treated as not personal.
import { execFileSync } from "node:child_process";

// Remotes whose code may reach every lane in the table. The host part accepts
// SSH config aliases like github.com-oElberte-dotfiles, which resolve to
// github.com for per-repository identity keys.
const PERSONAL_REMOTES = [
  /^(?:[a-z+]+:\/\/)?(?:[\w.-]+@)?github\.com(?:[-.][\w.-]*)?[/:]ElbertePlinio\//i,
  /^(?:[a-z+]+:\/\/)?(?:[\w.-]+@)?github\.com(?:[-.][\w.-]*)?[/:]pickforge\//i,
];

// Providers outside the Anthropic and OpenAI lanes. `:cloud` is here because
// fanout-review rewrites kimi-k3 to kimi-k3:cloud, which leaves the machine
// even though it is dispatched through the Ollama delegate.
const RESTRICTED_MODEL = /^(?:grok-|kimi-)|:cloud$/i;

// Models banned everywhere regardless of repository: Anthropic Haiku and the
// GPT-5.6 Luna/Terra lanes. Sol is the only GPT-5.6 lane.
const BANNED_MODEL = /haiku|luna|terra/i;

// Throws when `model` is a banned lane. Repository-independent.
export function assertModelPermitted(model) {
  if (!BANNED_MODEL.test(String(model))) return;
  throw new Error(
    [
      `lane-policy: ${model} is a banned lane.`,
      "  Anthropic Haiku and GPT-5.6 Luna/Terra are never selectable;",
      "  Sol is the only GPT-5.6 lane — shift its effort instead.",
    ].join("\n"),
  );
}

export function repoRemote(cwd) {
  try {
    return execFileSync("git", ["-C", cwd, "remote", "get-url", "origin"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

export function isPersonalRepo(cwd) {
  const remote = repoRemote(cwd);
  return remote !== "" && PERSONAL_REMOTES.some((re) => re.test(remote));
}

export function isRestrictedModel(model) {
  return RESTRICTED_MODEL.test(String(model));
}

// Throws unless `model` is allowed to see the repository at `cwd`.
export function assertModelAllowed(model, cwd) {
  assertModelPermitted(model);
  if (!isRestrictedModel(model)) return;
  if (isPersonalRepo(cwd)) return;

  const remote = repoRemote(cwd) || "(no git remote)";
  throw new Error(
    [
      `lane-policy: ${model} may not see this repository.`,
      `  remote: ${remote}`,
      `  cwd:    ${cwd}`,
      "  Outside personal repositories only the Anthropic and OpenAI lanes are",
      "  selectable. Re-run with an approved reviewer, or run from a personal",
      "  repository if this code is genuinely yours.",
    ].join("\n"),
  );
}

// Behavior fixture for the generated ai-memory Pi and OMP extensions. It loads
// one extension with a stubbed fetch inside a private temp tree, fires tool
// events per scenario and prints one redacted JSON line per step: disposition,
// fixture query params, body key names and the capture protocol. Payload
// values are never printed; a canary flag records whether they were sent.
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

type Expect = "keep" | "drop" | "metadata-only" | "passthrough";
type Step = { label: string; hook: "tool_call" | "tool_result"; tool: string; input: unknown; expect: Expect; callId?: string };
type Scenario = { name: string; cwd: string; steps: Step[] };
type Marker = { at: string; content: string | Buffer };
type Sent = { url: URL; body: Record<string, unknown> };
type Handler = (event: unknown, ctx: unknown) => unknown;

const extension = process.env.AI_MEMORY_EXTENSION;
const agent = process.env.AI_MEMORY_EXPECTED_AGENT;
if (!extension || !agent) throw new Error("AI_MEMORY_EXTENSION and AI_MEMORY_EXPECTED_AGENT are required");
if (existsSync("/tmp/.ai-memory.toml") || existsSync("/tmp/.git")) throw new Error("/tmp holds a marker or .git, so marker boundaries are ambiguous");

const CANARY = "ai-memory-capture-canary";
const PAYLOAD_KEYS = ["args", "output", "details", "prompt"];
// Bun resolves homedir() from the launch environment, so the fixture reruns
// itself with HOME and the data dir inside a private temp tree.
if (!process.env.AI_MEMORY_CAPTURE_ROOT) process.exit(runIsolated());
const root = process.env.AI_MEMORY_CAPTURE_ROOT as string;
const home = join(root, "home");
const sent: Sent[] = [];

function runIsolated(): number {
  const tree = mkdtempSync("/tmp/ai-memory-capture-");
  const env: Record<string, string | undefined> = { ...process.env, HOME: join(tree, "home"), AI_MEMORY_DATA_DIR: join(tree, "data"), AI_MEMORY_CAPTURE_ROOT: tree };
  for (const key of ["AI_MEMORY_AUTH_TOKEN", "AI_MEMORY_RUN_ID", "XDG_DATA_HOME"]) delete env[key];
  try {
    mkdirSync(join(tree, "home"));
    return spawnSync(process.execPath, [import.meta.path], { env, stdio: "inherit" }).status ?? 1;
  } finally {
    rmSync(tree, { recursive: true, force: true });
  }
}

function place(relative: string, content?: string | Buffer): string {
  const path = join(root, relative);
  mkdirSync(content === undefined ? path : dirname(path), { recursive: true });
  if (content !== undefined) writeFileSync(path, content);
  return path;
}

function scenario(name: string, cwd: string, steps: Step[], marker?: Marker): Scenario {
  if (marker) place(join(marker.at, ".ai-memory.toml"), marker.content);
  return { name, cwd: place(cwd), steps };
}

function gitInit(relative: string): void {
  execFileSync("git", ["init", "-q", place(relative)], { stdio: "ignore" });
}

function call(label: string, tool: string, input: unknown, expect: Expect): Step {
  return { label, hook: "tool_call", tool, input, expect };
}

function readSrc(label: string, expect: Expect): Step {
  return call(label, "read", { file_path: "src/x.ts", content: CANARY }, expect);
}

const capture = (items: string) => `[capture]\nignore_paths = ${items}\n`;
const patternList = (count: number) => capture(`[${Array.from({ length: count }, (_, i) => `"p${i}/**"`).join(", ")}]`);

const ACTIVE_MARKER = [
  'workspace = "ws-fixture"',
  'project = "proj-fixture"',
  'drop_subagent_captures = "true"',
  "default_global = true",
  "inject_on_session_start = false",
  "max_chars = 1200 # budget",
  "",
  "[capture]",
  "ignore_paths = [",
  '  "secrets/**", # comment with "quotes"',
  "  'config/*.pem',",
  '  "~/private/**",',
  '  "docs/\\u0073ecret.md",',
  '  "C:\\\\Users\\\\**",',
  "]",
].join("\n");

function activeSteps(): Step[] {
  return [
    readSrc("keep-src", "keep"),
    call("drop-dir", "read", { file_path: "secrets/api.txt", content: CANARY }, "drop"),
    call("drop-dir-root", "read", { file_path: "secrets" }, "drop"),
    call("drop-literal-string", "edit", { path: "config/server.pem", content: CANARY }, "drop"),
    call("keep-star-stops-at-slash", "edit", { path: "config/nested/server.pem" }, "keep"),
    call("drop-home-pattern", "read", { file_path: join(home, "private", "key.txt") }, "drop"),
    call("drop-unicode-escape", "read", { file_path: "docs/secret.md" }, "drop"),
    call("drop-windows-insensitive", "read", { file_path: "c:\\users\\fixture\\notes.txt" }, "drop"),
    call("keep-windows-other-drive", "read", { file_path: "D:\\data\\notes.txt" }, "keep"),
    call("drop-search", "grep", { pattern: CANARY }, "drop"),
    call("drop-multi-edit-any", "multi_edit", { edits: [{ file_path: "src/a.ts" }, { file_path: "secrets/b.ts" }] }, "drop"),
    call("keep-multi-edit", "multiedit", { file_path: "src/c.ts", edits: [{ file_path: "src/a.ts" }, { paths: ["src/b.ts"] }] }, "keep"),
    call("meta-empty-edits", "multi_edit", { edits: [], content: CANARY }, "metadata-only"),
    { ...call("meta-bad-path-type", "read", { file_path: 42, content: CANARY }, "metadata-only"), callId: "bad id!" },
    call("meta-blank-path", "write", { path: "   ", content: CANARY }, "metadata-only"),
    call("meta-bad-paths-array", "read", { paths: ["src/ok.ts", 7], content: CANARY }, "metadata-only"),
    call("meta-unnormalizable", "read", { file_path: "\\\\server", content: CANARY }, "metadata-only"),
    call("meta-match-budget", "read", { paths: Array.from({ length: 20 }, (_, i) => `src/${i}-${"a".repeat(3990)}`), content: CANARY }, "metadata-only"),
    call("keep-non-file", "bash", { command: CANARY }, "keep"),
    call("keep-unknown-tool", "custom_tool", { value: CANARY }, "keep"),
    { ...readSrc("keep-result", "keep"), hook: "tool_result" },
    { ...call("drop-result", "read", { file_path: "secrets/api.txt" }, "drop"), hook: "tool_result" },
  ];
}

const MALFORMED: [string, string | Buffer, Expect, string?][] = [
  ["unterminated-array", '[capture]\nignore_paths = ["a/**",\n[other]\n', "metadata-only"],
  ["unknown-capture-key", '[capture]\nother_key = ["a"]\n', "metadata-only"],
  ["second-capture-key", '[capture]\nignore_paths = ["a"]\nextra = 1\n', "metadata-only"],
  ["bad-escape", capture('["a\\q"]'), "metadata-only"],
  ["surrogate-escape", capture('["\\uD800"]'), "metadata-only"],
  ["short-unicode-escape", capture('["\\u12"]'), "metadata-only"],
  ["trailing-garbage", capture('["a"] x'), "metadata-only"],
  ["missing-comma", capture('["a" "b"]'), "metadata-only"],
  ["unquoted-item", capture("[a]"), "metadata-only"],
  ["unterminated-string", capture('["a]'), "metadata-only"],
  ["bad-table-header", '[capture\nignore_paths = ["a"]\n', "metadata-only"],
  ["brace-glob", capture('["{a,b}/**"]'), "metadata-only"],
  ["tilde-user", capture('["~other/x"]'), "metadata-only"],
  ["drive-relative", capture('["C:relative"]'), "metadata-only"],
  ["triple-star", capture('["a/***"]'), "metadata-only"],
  ["too-many-patterns", patternList(129), "metadata-only"],
  ["oversize-marker", `${capture('["a/**"]')}#${"x".repeat(70 * 1024)}\n`, "metadata-only"],
  ["invalid-utf8", Buffer.from([0x5b, 0x63, 0x5d, 0x0a, 0xff, 0x0a]), "metadata-only"],
  ["empty-array", capture("[]"), "passthrough"],
  ["no-capture-table", 'workspace = "w"\n', "passthrough"],
  ["other-table-only", '[other]\nignore_paths = ["src/**"]\n', "passthrough"],
  // 128 patterns stay an active policy, but their globs exhaust the shared match budget and fail closed.
  ["max-patterns", patternList(128), "metadata-only"],
  ["literal-backslash", capture("['src\\x.ts']"), "drop"],
  ["escaped-quote", capture('["src/\\"q\\".ts"]'), "drop", 'src/"q".ts'],
  ["crlf-multiline", '[capture]\r\nignore_paths = [\r\n  "src/**",\r\n]\r\n', "drop"],
];

function malformedScenarios(): Scenario[] {
  return MALFORMED.map(([name, content, expect, path]) => {
    const at = join("home", "malformed", name);
    const step = call(name, "read", { file_path: path ?? "src/x.ts", content: CANARY }, expect);
    return scenario(`malformed-${name}`, at, [step], { at, content });
  });
}

function routingScenarios(): Scenario[] {
  gitInit("repo-fixture");
  gitInit("repo-explicit");
  return [
    scenario("no-marker", "plain", [readSrc("passthrough-without-marker", "passthrough")]),
    scenario("nested-no-git", "nogit/sub", [readSrc("marker-above-start-dir-ignored", "passthrough")], { at: "nogit", content: 'workspace = "nogit"\n[capture]\nignore_paths = ["/**"]\n' }),
    scenario("git-repo-root", "repo-fixture/sub/deeper", [readSrc("repo-root-project", "passthrough")], { at: "repo-fixture", content: 'project_strategy = "repo-root"\n' }),
    scenario("explicit-project", "repo-explicit/sub", [readSrc("explicit-project-wins", "passthrough")], { at: "repo-explicit", content: 'project = "explicit-fixture"\nproject_strategy = "repo_root"\n' }),
    scenario("home-walk", "home/deep/a/b", [readSrc("marker-relative-pattern", "drop"), call("routed-keep", "read", { file_path: "/elsewhere/x.ts" }, "keep")], { at: "home/deep", content: 'workspace = "deep-fixture"\n[capture]\nignore_paths = ["a/b/**"]\n' }),
    scenario("home-stop", "home/nomarker/x", [readSrc("marker-above-home-ignored", "passthrough")], { at: ".", content: 'workspace = "above-home"\n[capture]\nignore_paths = ["/**"]\n' }),
  ];
}

function buildScenarios(): Scenario[] {
  return [
    scenario("active", "home/active", activeSteps(), { at: "home/active", content: ACTIVE_MARKER }),
    scenario("invalid-config", "home/invalid", [readSrc("meta-file", "metadata-only"), call("keep-search", "grep", { pattern: CANARY }, "keep"), call("keep-non-file", "bash", { command: CANARY }, "keep")], { at: "home/invalid", content: capture('["ok/**", "../escape/**"]') }),
    ...malformedScenarios(),
    ...routingScenarios(),
  ];
}

async function stubFetch(input: unknown, init?: { body?: unknown }): Promise<Response> {
  const url = new URL(String(input));
  if (url.pathname !== "/hook") return new Response(null, { status: 503 });
  sent.push({ url, body: JSON.parse(String(init?.body ?? "{}")) });
  return new Response(null, { status: 204 });
}

function context(item: Scenario): unknown {
  return { cwd: item.cwd, model: { id: "fixture-model" }, sessionManager: { getSessionId: () => `session-${item.name}` } };
}

function eventName(record: Sent): string | null {
  return record.url.searchParams.get("event");
}

async function settle(label: string): Promise<Sent[]> {
  for (let waited = 0; waited < 5000; waited += 5) {
    if (sent.some((r) => eventName(r) === "stop")) return sent.splice(0).filter((r) => eventName(r) !== "stop");
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  throw new Error(`timed out waiting for hook flush: ${label}`);
}

function toolRecords(records: Sent[]): Sent[] {
  return records.filter((r) => eventName(r) !== "session-start");
}

function disposition(records: Sent[]): string {
  const tools = toolRecords(records);
  if (tools.length === 0) return "drop";
  if (tools.length > 1) return "duplicate";
  const protocol = tools[0].body._ai_memory_capture as { disposition?: string } | undefined;
  return protocol?.disposition ?? "passthrough";
}

function carriesPayload(record: Sent): boolean {
  return JSON.stringify(record.body).includes(CANARY) || PAYLOAD_KEYS.some((key) => key in record.body);
}

function redactParam(key: string, value: string, cwd: string): string {
  if (key === "cwd") return value === cwd ? "<cwd>" : "<other-cwd>";
  if (key === "agent") return value === agent ? "<agent>" : value;
  return value;
}

function redact(record: Sent, cwd: string): Record<string, unknown> {
  const query: Record<string, string> = {};
  for (const [key, value] of record.url.searchParams) query[key] = redactParam(key, value, cwd);
  return { query, bodyKeys: Object.keys(record.body).sort(), capture: record.body._ai_memory_capture ?? null, canary: JSON.stringify(record.body).includes(CANARY) };
}

async function runScenario(handlers: Record<string, Handler>, item: Scenario, failures: string[]): Promise<void> {
  for (const step of item.steps) {
    handlers[step.hook]({ toolName: step.tool, toolCallId: step.callId ?? step.label, input: step.input, content: [{ type: "text", text: CANARY }], isError: false }, context(item));
    handlers.agent_end({}, context(item));
    const records = await settle(step.label);
    const actual = disposition(records);
    const id = `${item.name}/${step.label}`;
    if (actual !== step.expect) failures.push(`${id}: expected ${step.expect}, got ${actual}`);
    if (actual === "metadata-only" && toolRecords(records).some(carriesPayload)) failures.push(`${id}: metadata-only request carried payload values`);
    console.log(JSON.stringify({ scenario: item.name, step: step.label, disposition: actual, requests: records.map((r) => redact(r, item.cwd)) }));
  }
}

async function main(): Promise<void> {
  if (homedir() !== home) throw new Error("runtime did not honor the HOME override");
  const scenarios = buildScenarios();
  globalThis.fetch = stubFetch as typeof fetch;
  const handlers: Record<string, Handler> = {};
  const loaded = await import(extension as string);
  loaded.default({ on: (name: string, handler: Handler) => { handlers[name] = handler; }, registerTool: () => undefined });
  const failures: string[] = [];
  for (const item of scenarios) await runScenario(handlers, item, failures);
  for (const failure of failures) console.error(`FAIL ${failure}`);
  if (failures.length) process.exitCode = 1;
}

try {
  await main();
} finally {
  rmSync(root, { recursive: true, force: true });
}

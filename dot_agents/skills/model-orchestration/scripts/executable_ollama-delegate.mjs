#!/usr/bin/env node
import { spawn } from "node:child_process";
import { accessSync, closeSync, constants, openSync, readFileSync, readSync, realpathSync } from "node:fs";
import { delimiter, resolve } from "node:path";
import process from "node:process";

const MODES = ["scout", "implement", "review", "dissent"];
const DANGEROUS_CODEX_FLAGS = ["--dangerously-bypass-approvals-and-sandbox"];
const DEFAULT_MODEL = "glm-5.2:cloud";

const NO_VISION_RULE = [
  "You are GLM-5.2 running as a text-only model through Ollama.",
  "You do not have vision capabilities.",
  "Do not attempt to inspect, open, decode, OCR, or infer from image files, screenshots, diagrams, videos, or visual attachments.",
  "If the task references visual material, rely only on the text description supplied by the orchestrator.",
  "If no text description is supplied, say the visual evidence is unavailable to you and limit your review to text/code.",
  "Do not call image-capable tools or pass image attachments.",
].join("\n");

function usage(stream) {
  stream.write(
    [
      "ollama-delegate - run Ollama models through Codex OSS/local-provider lanes",
      "",
      "Usage:",
      "  ollama-delegate.mjs --mode <scout|implement|review|dissent> --prompt <text>",
      "  ollama-delegate.mjs --mode <mode> --prompt-file <path>",
      "",
      "Options:",
      "  --mode <mode>         scout, implement, review, or dissent",
      "  --model <model>       Ollama model (default: glm-5.2:cloud)",
      "  --prompt <text>       prompt text",
      "  --prompt-file <path>  read prompt from file",
      "  --cwd <path>          working directory (default: process cwd)",
      "  --json                emit a JSON result envelope",
      "  --output-last-message <path>",
      "  --persist-session     do not pass --ephemeral to Codex",
      "  --codex-bin <path>    use this Codex binary instead of resolving PATH",
      "  --extra-arg <arg>     pass a raw arg to codex (repeatable)",
      "  --dry-run             print the command without running it",
      "  -h, --help            show this help",
      "",
    ].join("\n") + "\n"
  );
}

function need(argv, i, flag) {
  const value = argv[i];
  if (value === undefined) throw new Error("missing value for " + flag);
  return value;
}

function parseArgs(argv) {
  const opts = {
    mode: "review",
    model: DEFAULT_MODEL,
    prompt: null,
    promptFile: null,
    cwd: process.cwd(),
    json: false,
    outputLastMessage: null,
    ephemeral: true,
    codexBin: null,
    extraArgs: [],
    dryRun: false,
    help: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--mode": opts.mode = need(argv, ++i, arg); break;
      case "--model": opts.model = need(argv, ++i, arg); break;
      case "--prompt": opts.prompt = need(argv, ++i, arg); break;
      case "--prompt-file": opts.promptFile = need(argv, ++i, arg); break;
      case "--cwd": opts.cwd = need(argv, ++i, arg); break;
      case "--json": opts.json = true; break;
      case "--output-last-message": opts.outputLastMessage = need(argv, ++i, arg); break;
      case "--persist-session": opts.ephemeral = false; break;
      case "--codex-bin": opts.codexBin = need(argv, ++i, arg); break;
      case "--extra-arg": opts.extraArgs.push(need(argv, ++i, arg)); break;
      case "--dry-run": opts.dryRun = true; break;
      case "-h":
      case "--help": opts.help = true; break;
      default: throw new Error("unknown argument " + JSON.stringify(arg));
    }
  }
  return opts;
}

function promptFrom(opts) {
  if (opts.promptFile) return readFileSync(opts.promptFile, "utf8");
  return opts.prompt;
}

function promptForMode(mode, prompt) {
  const header = [NO_VISION_RULE, ""];
  if (mode === "scout") {
    header.push(
      "You are a read-only scout in the model-orchestration workflow.",
      "Do not create, edit, delete, stage, commit, push, or otherwise mutate files or external systems.",
      "Map relevant context, risks, repo patterns, and validation options only.",
      ""
    );
  } else if (mode === "review") {
    header.push(
      "You are a read-only reviewer in the model-orchestration workflow.",
      "Do not create, edit, delete, stage, commit, push, or otherwise mutate files or external systems.",
      "Report only concrete findings, validation gaps, risks, and next actions.",
      ""
    );
  } else if (mode === "dissent") {
    header.push(
      "You are a read-only dissent reviewer in the model-orchestration workflow.",
      "Challenge assumptions, hidden coupling, incomplete contracts, and long-context interactions.",
      "Do not create, edit, delete, stage, commit, push, or otherwise mutate files or external systems.",
      ""
    );
  }
  header.push(prompt || "");
  return header.join("\n");
}

function quoteArg(arg) {
  if (/^[A-Za-z0-9_\-.\/=:,]+$/.test(arg)) return arg;
  return "'" + arg.replace(/'/g, "'\\''") + "'";
}

function isExecutable(path) {
  try { accessSync(path, constants.X_OK); return true; } catch (_err) { return false; }
}

function readPrefix(path) {
  let fd = null;
  try {
    fd = openSync(path, "r");
    const buffer = Buffer.alloc(65536);
    const bytes = readSync(fd, buffer, 0, buffer.length, 0);
    const prefix = buffer.subarray(0, bytes);
    return prefix.includes(0) ? "" : prefix.toString("utf8");
  } catch (_err) {
    return "";
  } finally {
    if (fd != null) closeSync(fd);
  }
}

function containsDangerousFlag(path, flags) {
  const prefix = readPrefix(path);
  return flags.some((flag) => prefix.includes(flag));
}

function resolveSafeExecutable(name, explicitPath, dangerousFlags) {
  if (explicitPath) {
    const resolved = resolve(explicitPath);
    if (!isExecutable(resolved)) throw new Error(name + " binary is not executable: " + resolved);
    if (containsDangerousFlag(resolved, dangerousFlags)) throw new Error(name + " binary contains a dangerous bypass flag: " + resolved);
    return resolved;
  }

  const seen = new Set();
  const skipped = [];
  for (const dir of String(process.env.PATH || "").split(delimiter).filter(Boolean)) {
    const candidate = resolve(dir, name);
    if (!isExecutable(candidate)) continue;
    const real = realpathSync(candidate);
    if (seen.has(real)) continue;
    seen.add(real);
    if (containsDangerousFlag(candidate, dangerousFlags) || containsDangerousFlag(real, dangerousFlags)) {
      skipped.push(candidate);
      continue;
    }
    return real;
  }
  const detail = skipped.length ? " Skipped wrappers: " + skipped.join(", ") : "";
  throw new Error("could not find a non-yolo " + name + " executable in PATH." + detail);
}

function buildCommand(opts, prompt) {
  const cwd = resolve(opts.cwd);
  const codexBin = resolveSafeExecutable("codex", opts.codexBin, DANGEROUS_CODEX_FLAGS);
  const sandbox = opts.mode === "implement" ? "workspace-write" : "read-only";
  const args = [
    "exec",
    "--oss",
    "--local-provider", "ollama",
    "-m", opts.model,
    "--cd", cwd,
    "--sandbox", sandbox,
    "--skip-git-repo-check",
  ];

  if (opts.outputLastMessage) args.push("--output-last-message", opts.outputLastMessage);
  if (opts.ephemeral) args.push("--ephemeral");
  for (const extra of opts.extraArgs) args.push(extra);
  if (prompt) args.push(prompt);
  return { cwd, command: [codexBin, ...args], args, codexBin, sandbox };
}

function run(command, args, cwd, capture) {
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(command, args, { cwd, stdio: capture ? ["ignore", "pipe", "pipe"] : "inherit" });
    let stdout = "";
    let stderr = "";
    if (capture) {
      child.stdout.on("data", (d) => { stdout += d.toString(); });
      child.stderr.on("data", (d) => { stderr += d.toString(); });
    }
    child.on("error", rejectRun);
    child.on("close", (exitCode, signal) => resolveRun({ stdout, stderr, exitCode, signal }));
  });
}

function emitJson(obj) {
  process.stdout.write(JSON.stringify(obj, null, 2) + "\n");
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
    if (opts.help) { usage(process.stdout); return; }
    if (!MODES.includes(opts.mode)) throw new Error("invalid --mode " + JSON.stringify(opts.mode));
  } catch (err) {
    process.stderr.write("Error: " + err.message + "\n\n");
    usage(process.stderr);
    process.exit(2);
    return;
  }

  let prompt = null;
  try { prompt = promptFrom(opts); } catch (err) {
    process.stderr.write("Error: cannot read prompt: " + err.message + "\n");
    process.exit(2);
    return;
  }

  if (!prompt && !opts.dryRun) {
    process.stderr.write("Error: a prompt is required unless --dry-run is used.\n\n");
    usage(process.stderr);
    process.exit(2);
    return;
  }

  let built;
  try { built = buildCommand(opts, promptForMode(opts.mode, prompt)); } catch (err) {
    process.stderr.write("Error: " + (err.message || err) + "\n");
    process.exit(2);
    return;
  }

  if (opts.dryRun) {
    const line = built.command.map(quoteArg).join(" ");
    if (opts.json) emitJson({ status: "dry-run", mode: opts.mode, model: opts.model, cwd: built.cwd, sandbox: built.sandbox, command: built.command });
    else process.stdout.write(line + "\n");
    return;
  }

  let result;
  try { result = await run(built.codexBin, built.args, built.cwd, opts.json); } catch (err) {
    const message = err && err.message ? err.message : String(err);
    if (opts.json) emitJson({ status: "error", mode: opts.mode, model: opts.model, cwd: built.cwd, command: built.command, error: message });
    else process.stderr.write("Error: failed to launch codex: " + message + "\n");
    process.exit(1);
    return;
  }

  const exitCode = result.exitCode == null ? (result.signal ? 1 : 0) : result.exitCode;
  if (opts.json) {
    emitJson({
      status: exitCode === 0 ? "ok" : "error",
      mode: opts.mode,
      model: opts.model,
      cwd: built.cwd,
      sandbox: built.sandbox,
      command: built.command,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
      signal: result.signal,
    });
  }
  process.exit(exitCode);
}

main().catch((err) => {
  process.stderr.write("Fatal: " + (err && err.stack ? err.stack : String(err)) + "\n");
  process.exit(1);
});

#!/usr/bin/env node
import { spawn } from "node:child_process";
import { accessSync, closeSync, constants, openSync, readFileSync, readSync, realpathSync } from "node:fs";
import { delimiter, resolve } from "node:path";
import process from "node:process";

const MODES = ["scout", "implement", "review"];
const DANGEROUS_CODEX_FLAGS = ["--dangerously-bypass-approvals-and-sandbox"];

function usage(stream) {
  stream.write(
    [
      "codex-delegate - run Codex CLI for model-orchestration lanes",
      "",
      "Usage:",
      "  codex-delegate.mjs --mode <scout|implement|review> --prompt <text>",
      "  codex-delegate.mjs --mode <mode> --prompt-file <path>",
      "",
      "Options:",
      "  --mode <mode>         scout, implement, or review",
      "  --model <model>       Codex model (default: gpt-5.6-sol)",
      "  --effort <effort>     optional reasoning effort override",
      "  --prompt <text>       prompt text",
      "  --prompt-file <path>  read prompt from file",
      "  --cwd <path>          working directory (default: process cwd)",
      "  --profile <name>      pass a Codex config profile",
      "  --base <branch>       review base branch",
      "  --commit <sha>        review one commit",
      "  --uncommitted         review uncommitted changes",
      "  --json                emit Codex JSONL events",
      "  --output-last-message <path>",
      "  --persist-session     persist scout/review sessions; implement sessions persist by default",
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
    mode: "scout",
    model: "gpt-5.6-sol",
    effort: null,
    prompt: null,
    promptFile: null,
    cwd: process.cwd(),
    profile: null,
    base: null,
    commit: null,
    uncommitted: false,
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
      case "--mode":
        opts.mode = need(argv, ++i, arg);
        break;
      case "--model":
        opts.model = need(argv, ++i, arg);
        break;
      case "--effort":
        opts.effort = need(argv, ++i, arg);
        break;
      case "--prompt":
        opts.prompt = need(argv, ++i, arg);
        break;
      case "--prompt-file":
        opts.promptFile = need(argv, ++i, arg);
        break;
      case "--cwd":
        opts.cwd = need(argv, ++i, arg);
        break;
      case "--profile":
        opts.profile = need(argv, ++i, arg);
        break;
      case "--base":
        opts.base = need(argv, ++i, arg);
        break;
      case "--commit":
        opts.commit = need(argv, ++i, arg);
        break;
      case "--uncommitted":
        opts.uncommitted = true;
        break;
      case "--json":
        opts.json = true;
        break;
      case "--output-last-message":
        opts.outputLastMessage = need(argv, ++i, arg);
        break;
      case "--persist-session":
        opts.ephemeral = false;
        break;
      case "--codex-bin":
        opts.codexBin = need(argv, ++i, arg);
        break;
      case "--extra-arg":
        opts.extraArgs.push(need(argv, ++i, arg));
        break;
      case "--dry-run":
        opts.dryRun = true;
        break;
      case "-h":
      case "--help":
        opts.help = true;
        break;
      default:
        throw new Error("unknown argument " + JSON.stringify(arg));
    }
  }
  return opts;
}

function promptFrom(opts) {
  if (opts.promptFile) return readFileSync(opts.promptFile, "utf8");
  return opts.prompt;
}

function promptForMode(mode, prompt) {
  if (!prompt) return prompt;
  if (mode === "scout") {
    return [
      "You are a read-only scout in the model-orchestration workflow.",
      "Do not create, edit, delete, stage, commit, push, or otherwise mutate files or external systems.",
      "Map relevant context, risks, repo patterns, and validation options only.",
      "",
      prompt,
    ].join("\n");
  }
  if (mode === "review") {
    return [
      "You are a read-only reviewer in the model-orchestration workflow.",
      "Do not create, edit, delete, stage, commit, push, or otherwise mutate files or external systems.",
      "Report only concrete findings, validation gaps, risks, and next actions.",
      "",
      prompt,
    ].join("\n");
  }
  return prompt;
}

function quoteArg(arg) {
  if (/^[A-Za-z0-9_\-.\/=:,]+$/.test(arg)) return arg;
  return "'" + arg.replace(/'/g, "'\\''") + "'";
}

function isExecutable(path) {
  try {
    accessSync(path, constants.X_OK);
    return true;
  } catch (_err) {
    return false;
  }
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
    if (!isExecutable(resolved)) {
      throw new Error(name + " binary is not executable: " + resolved);
    }
    if (containsDangerousFlag(resolved, dangerousFlags)) {
      throw new Error(name + " binary contains a dangerous bypass flag: " + resolved);
    }
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
  const args = ["exec"];

  if (opts.mode === "review") {
    args.push("review");
  }

  args.push("-m", opts.model);

  if (opts.effort) {
    args.push("-c", "model_reasoning_effort=" + JSON.stringify(opts.effort));
  }

  if (opts.profile) {
    args.push("--profile", opts.profile);
  }
  if (opts.json) {
    args.push("--json");
  }
  if (opts.outputLastMessage) {
    args.push("--output-last-message", opts.outputLastMessage);
  }
  if (opts.ephemeral && opts.mode !== "implement") {
    args.push("--ephemeral");
  }

  if (opts.mode !== "review") {
    args.push("--cd", cwd);
    args.push("--sandbox", opts.mode === "implement" ? "workspace-write" : "read-only");
  }

  args.push("--skip-git-repo-check");

  if (opts.mode === "review") {
    if (opts.base) args.push("--base", opts.base);
    if (opts.commit) args.push("--commit", opts.commit);
    if (opts.uncommitted) args.push("--uncommitted");
  }

  for (const extra of opts.extraArgs) {
    if (DANGEROUS_CODEX_FLAGS.some((flag) => extra.includes(flag))) {
      throw new Error("refusing dangerous extra arg " + JSON.stringify(extra));
    }
    args.push(extra);
  }

  if (prompt) {
    args.push("-");
  }

  return { cwd, command: [codexBin, ...args], args, codexBin, prompt };
}

function run(command, args, cwd, capture, prompt) {
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(command, args, {
      cwd,
      stdio: capture ? ["pipe", "pipe", "pipe"] : ["pipe", "inherit", "inherit"],
    });
    child.stdin.end(prompt || "");
    let stdout = "";
    let stderr = "";
    if (capture) {
      child.stdout.on("data", (d) => {
        stdout += d.toString();
      });
      child.stderr.on("data", (d) => {
        stderr += d.toString();
      });
    }
    child.on("error", rejectRun);
    child.on("close", (exitCode, signal) => {
      resolveRun({ stdout, stderr, exitCode, signal });
    });
  });
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
    if (opts.help) {
      usage(process.stdout);
      return;
    }
    if (!MODES.includes(opts.mode)) {
      throw new Error("invalid --mode " + JSON.stringify(opts.mode));
    }
  } catch (err) {
    process.stderr.write("Error: " + err.message + "\n\n");
    usage(process.stderr);
    process.exit(2);
    return;
  }

  let prompt = null;
  try {
    prompt = promptFrom(opts);
  } catch (err) {
    process.stderr.write("Error: cannot read prompt: " + err.message + "\n");
    process.exit(2);
    return;
  }

  if (!prompt && !opts.dryRun && opts.mode !== "review") {
    process.stderr.write("Error: a prompt is required unless --dry-run is used.\n\n");
    usage(process.stderr);
    process.exit(2);
    return;
  }

  let built;
  try {
    built = buildCommand(opts, promptForMode(opts.mode, prompt));
  } catch (err) {
    process.stderr.write("Error: " + (err.message || err) + "\n");
    process.exit(2);
    return;
  }

  if (opts.dryRun) {
    process.stdout.write(built.command.map(quoteArg).join(" ") + "\n");
    return;
  }

  let result;
  try {
    result = await run(built.codexBin, built.args, built.cwd, opts.json, built.prompt);
  } catch (err) {
    process.stderr.write("Error: failed to launch codex: " + (err.message || err) + "\n");
    process.exit(1);
    return;
  }

  if (opts.json) {
    process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
  }

  const exitCode = result.exitCode == null ? (result.signal ? 1 : 0) : result.exitCode;
  process.exit(exitCode);
}

main().catch((err) => {
  process.stderr.write("Fatal: " + (err && err.stack ? err.stack : String(err)) + "\n");
  process.exit(1);
});

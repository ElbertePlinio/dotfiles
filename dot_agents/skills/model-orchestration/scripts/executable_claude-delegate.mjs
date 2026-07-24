#!/usr/bin/env node
import { spawn } from "node:child_process";
import { accessSync, closeSync, constants, openSync, readFileSync, readSync, realpathSync } from "node:fs";
import { delimiter, resolve } from "node:path";
import process from "node:process";

const MODES = ["plan", "implement", "review", "design-review"];
const EFFORTS = ["low", "medium", "high", "xhigh", "max"];
const DANGEROUS_CLAUDE_FLAGS = [
  "--dangerously-skip-permissions",
  "--permission-mode bypassPermissions",
];

const READ_TOOLS = [
  "Read",
  "Glob",
  "Grep",
  "Bash(git *)",
  "Bash(find *)",
  "Bash(sed *)",
  "Bash(rg *)",
  "Bash(wc *)",
  "Bash(ls *)",
];

const WRITE_TOOLS = [
  "Write",
  "Edit",
  "MultiEdit",
  "Bash(bun *)",
  "Bash(node *)",
  "Bash(npm *)",
  "Bash(pnpm *)",
  "Bash(yarn *)",
  "Bash(git *)",
  "Bash(chmod *)",
  "Bash(python3 *)",
];

function usage(stream) {
  stream.write(
    [
      "claude-delegate - run Claude Code for model-orchestration lanes",
      "",
      "Usage:",
      "  claude-delegate.mjs --model <fable-5|opus-4.8|sonnet-5> --mode <mode> --prompt <text>",
      "  claude-delegate.mjs --model <model> --mode <mode> --prompt-file <path>",
      "",
      "Modes: plan, implement, review, design-review",
      "",
      "Options:",
      "  --model <model>       fable-5, opus-4.8, sonnet-5, fable, opus, sonnet, or full model id",
      "  --mode <mode>         one of: " + MODES.join(", "),
      "  --effort <level>      low, medium, high, xhigh, max (default by model)",
      "  --prompt <text>       prompt text",
      "  --prompt-file <path>  read prompt from file",
      "  --cwd <path>          working directory (default: process cwd)",
      "  --stream              stream tool events from Claude",
      "  --json                emit a JSON result envelope",
      "  --max-budget-usd <n>  optional user-requested hard budget cap",
      "  --claude-bin <path>   use this Claude binary instead of resolving PATH",
      "  --extra-arg <arg>     pass a raw arg to claude (repeatable)",
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
    model: null,
    mode: "plan",
    effort: null,
    prompt: null,
    promptFile: null,
    cwd: process.cwd(),
    stream: false,
    json: false,
    dryRun: false,
    maxBudget: null,
    claudeBin: null,
    extraArgs: [],
    help: false,
  };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--model":
        opts.model = need(argv, ++i, arg);
        break;
      case "--mode":
        opts.mode = need(argv, ++i, arg);
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
      case "--stream":
        opts.stream = true;
        break;
      case "--json":
        opts.json = true;
        break;
      case "--dry-run":
        opts.dryRun = true;
        break;
      case "--max-budget-usd":
        opts.maxBudget = need(argv, ++i, arg);
        break;
      case "--claude-bin":
        opts.claudeBin = need(argv, ++i, arg);
        break;
      case "--extra-arg":
        opts.extraArgs.push(need(argv, ++i, arg));
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

function normalizeModel(model) {
  const key = String(model || "").toLowerCase();
  if (key === "fable-5" || key === "fable5") return "fable";
  if (key === "opus-4.8" || key === "opus48" || key === "opus-48") return "opus";
  if (key === "sonnet-5" || key === "sonnet5") return "sonnet";
  return model;
}

function defaultEffort(model) {
  const key = String(model || "").toLowerCase();
  if (key.includes("sonnet")) return "medium";
  return "high";
}

function validateOptions(opts) {
  if (!opts.help && !opts.model) throw new Error("--model is required");
  if (!MODES.includes(opts.mode)) {
    throw new Error("invalid --mode " + JSON.stringify(opts.mode));
  }
  if (opts.effort != null && !EFFORTS.includes(opts.effort)) {
    throw new Error("invalid --effort " + JSON.stringify(opts.effort));
  }
  if (opts.stream && opts.json) {
    throw new Error("--stream and --json cannot be combined");
  }
  if (opts.maxBudget != null && !Number.isFinite(Number(opts.maxBudget))) {
    throw new Error("--max-budget-usd must be numeric");
  }
}

function allowedTools(mode) {
  if (mode === "implement") {
    return [...new Set([...READ_TOOLS, ...WRITE_TOOLS])];
  }
  return READ_TOOLS;
}

function resolvePrompt(opts) {
  if (opts.promptFile) return readFileSync(opts.promptFile, "utf8");
  return opts.prompt;
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

function run(command, args, cwd, capture) {
  return new Promise((resolveRun, rejectRun) => {
    const child = spawn(command, args, {
      cwd,
      stdio: capture ? ["inherit", "pipe", "pipe"] : "inherit",
    });
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

function emitJson(obj) {
  process.stdout.write(JSON.stringify(obj, null, 2) + "\n");
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
    if (opts.help) {
      usage(process.stdout);
      return;
    }
    validateOptions(opts);
  } catch (err) {
    process.stderr.write("Error: " + err.message + "\n\n");
    usage(process.stderr);
    process.exit(2);
    return;
  }

  const cwd = resolve(opts.cwd);
  let claudeBin;
  try {
    claudeBin = resolveSafeExecutable("claude", opts.claudeBin, DANGEROUS_CLAUDE_FLAGS);
  } catch (err) {
    process.stderr.write("Error: " + err.message + "\n");
    process.exit(2);
    return;
  }
  const model = normalizeModel(opts.model);
  const effort = opts.effort || defaultEffort(model);

  if (String(model).toLowerCase().includes("fable") && ["xhigh", "max"].includes(effort)) {
    process.stderr.write("Error: Fable effort must be high or lower.\n");
    process.exit(2);
    return;
  }

  let prompt = null;
  try {
    prompt = resolvePrompt(opts);
  } catch (err) {
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

  const args = [
    "-p",
    "--model",
    model,
    "--effort",
    effort,
    "--add-dir",
    cwd,
    "--allowedTools",
    allowedTools(opts.mode).join(","),
  ];

  if (opts.stream) {
    args.push("--output-format", "stream-json", "--include-partial-messages", "--verbose");
  }
  if (opts.maxBudget != null) {
    args.push("--max-budget-usd", String(opts.maxBudget));
  }
  for (const extra of opts.extraArgs) {
    args.push(extra);
  }
  if (prompt) {
    args.push("--", prompt);
  }

  const command = [claudeBin, ...args];

  if (opts.dryRun) {
    if (opts.json) {
      emitJson({ status: "dry-run", mode: opts.mode, model, effort, cwd, command });
    } else {
      process.stdout.write(command.map(quoteArg).join(" ") + "\n");
    }
    return;
  }

  let result;
  try {
    result = await run(claudeBin, args, cwd, opts.json);
  } catch (err) {
    const message = err && err.message ? err.message : String(err);
    if (opts.json) {
      emitJson({ status: "error", mode: opts.mode, model, effort, cwd, command, error: message });
    } else {
      process.stderr.write("Error: failed to launch claude: " + message + "\n");
    }
    process.exit(1);
    return;
  }

  const exitCode = result.exitCode == null ? (result.signal ? 1 : 0) : result.exitCode;
  if (opts.json) {
    emitJson({
      status: exitCode === 0 ? "ok" : "error",
      mode: opts.mode,
      model,
      effort,
      cwd,
      command,
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

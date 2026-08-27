#!/usr/bin/env node
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import process from "node:process";
import { assertModelAllowed } from "./lane-policy.mjs";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));

const ANTI_OVERENGINEERING_PROMPT = [
  "",
  "## Anti-overengineering gate",
  "",
  "Also run a simplification-focused review. Look only for:",
  "- abstractions introduced before repeated need exists",
  "- generic frameworks where direct code is clearer",
  "- config/options with no current caller",
  "- new layers that do not reduce complexity",
  "- premature caching, queues, factories, adapters, managers",
  "- too many files for a small behavior change",
  "- tests coupled to implementation details",
  "",
  "For each finding, answer:",
  "1. What is overengineered or speculative?",
  "2. Why is it unnecessary for the current requirement?",
  "3. What simpler design satisfies the same requirement now?",
  "4. What future signal would justify adding the abstraction later?",
  "5. Can we remove/simplify it safely in this diff?",
  "",
  "End with exactly one verdict token: keep, simplify_now, or defer.",
].join("\n");

function usage(stream) {
  stream.write(
    [
      "fanout-review - run read-only review across multiple model lanes",
      "",
      "Usage:",
      "  fanout-review.mjs --prompt-file review.md --reviewer grok-4.6",
      "",
      "Options:",
      "  --prompt <text>       review prompt text",
      "  --prompt-file <path>  read prompt from file",
      "  --cwd <path>          working directory (default: process cwd)",
      "  --reviewer <model>    gpt-5.6-sol, grok-4.6, kimi-k3, fable-5, or opus-5 (repeatable)",
      "  --anti-overengineering append the simplification/overengineering review gate",
      "  --json                emit JSON summary",
      "  --dry-run             print commands without running them",
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
    prompt: null,
    promptFile: null,
    cwd: process.cwd(),
    reviewers: [],
    antiOverengineering: false,
    json: false,
    dryRun: false,
    help: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--prompt":
        opts.prompt = need(argv, ++i, arg);
        break;
      case "--prompt-file":
        opts.promptFile = need(argv, ++i, arg);
        break;
      case "--cwd":
        opts.cwd = need(argv, ++i, arg);
        break;
      case "--reviewer":
        opts.reviewers.push(need(argv, ++i, arg));
        break;
      case "--anti-overengineering":
        opts.antiOverengineering = true;
        break;
      case "--json":
        opts.json = true;
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

function isCodex(model) {
  return String(model).toLowerCase().startsWith("gpt-");
}

function isOllama(model) {
  const key = String(model).toLowerCase();
  return key.startsWith("kimi-") || key.includes(":cloud");
}

function isGrok(model) {
  return String(model).toLowerCase().startsWith("grok-");
}

function buildReviewerCommand(model, cwd, promptFile) {
  assertModelAllowed(model, cwd);

  if (isCodex(model)) {
    return {
      model,
      command: "node",
      args: [
        resolve(SCRIPT_DIR, "codex-delegate.mjs"),
        "--mode",
        "review",
        "--model",
        model,
        "--cwd",
        cwd,
        "--prompt-file",
        promptFile,
        "--json",
      ],
    };
  }


  if (isOllama(model)) {
    return {
      model,
      command: "node",
      args: [
        resolve(SCRIPT_DIR, "ollama-delegate.mjs"),
        "--mode",
        "review",
        "--model",
        model === "kimi-k3" ? "opencode-go/kimi-k3" : model,
        "--cwd",
        cwd,
        "--prompt-file",
        promptFile,
        "--json",
      ],
    };
  }

  if (isGrok(model)) {
    return {
      model,
      command: "grok",
      args: [
        "--prompt-file",
        promptFile,
        "--model",
        model,
        "--reasoning-effort",
        "high",
        "--cwd",
        cwd,
        "--deny",
        "Write(*)",
        "--deny",
        "Edit(*)",
        "--deny",
        "Bash(*)",
      ],
    };
  }

  return {
    model,
    command: "node",
    args: [
      resolve(SCRIPT_DIR, "claude-delegate.mjs"),
      "--mode",
      "review",
      "--model",
      model,
      "--cwd",
      cwd,
      "--prompt-file",
      promptFile,
      "--json",
    ],
  };
}

function quoteArg(arg) {
  if (/^[A-Za-z0-9_\-.\/=:,]+$/.test(arg)) return arg;
  return "'" + arg.replace(/'/g, "'\\''") + "'";
}

function runOne(spec, cwd) {
  return new Promise((resolveRun) => {
    const child = spawn(spec.command, spec.args, {
      cwd,
      stdio: ["inherit", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => {
      stdout += d.toString();
    });
    child.stderr.on("data", (d) => {
      stderr += d.toString();
    });
    child.on("error", (err) => {
      resolveRun({
        model: spec.model,
        ok: false,
        exitCode: null,
        signal: null,
        stdout,
        stderr: stderr + String(err.message || err),
      });
    });
    child.on("close", (exitCode, signal) => {
      resolveRun({
        model: spec.model,
        ok: exitCode === 0,
        exitCode,
        signal,
        stdout,
        stderr,
      });
    });
  });
}

function renderMarkdown(report) {
  const lines = [];
  lines.push("# Fan-out Review");
  lines.push("");
  lines.push("- Status: " + report.status);
  lines.push("- CWD: " + report.cwd);
  lines.push("- Reviewers: " + report.reviewers.join(", "));
  lines.push("");

  if (report.dryRun) {
    lines.push("## Commands");
    lines.push("");
    for (const item of report.commands) {
      lines.push("### " + item.model);
      lines.push("");
      lines.push("```bash");
      lines.push([item.command, ...item.args].map(quoteArg).join(" "));
      lines.push("```");
      lines.push("");
    }
    return lines.join("\n");
  }

  for (const result of report.results) {
    lines.push("## " + result.model + (result.ok ? "" : " (failed)"));
    lines.push("");
    if (result.stdout.trim()) {
      lines.push(result.stdout.trim());
      lines.push("");
    }
    if (result.stderr.trim()) {
      lines.push("stderr:");
      lines.push("```text");
      lines.push(result.stderr.trim());
      lines.push("```");
      lines.push("");
    }
  }

  return lines.join("\n");
}

async function main() {
  let opts;
  try {
    opts = parseArgs(process.argv.slice(2));
    if (opts.help) {
      usage(process.stdout);
      return;
    }
  } catch (err) {
    process.stderr.write("Error: " + err.message + "\n\n");
    usage(process.stderr);
    process.exit(2);
    return;
  }

  const cwd = resolve(opts.cwd);
  if (!opts.reviewers.length) {
    process.stderr.write("Error: choose at least one --reviewer for this task.\n\n");
    usage(process.stderr);
    process.exit(2);
    return;
  }
  const reviewers = opts.reviewers;

  let prompt = "";
  try {
    prompt = promptFrom(opts) || "";
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

  if (opts.antiOverengineering) {
    prompt = [prompt, ANTI_OVERENGINEERING_PROMPT].join("\n");
  }

  let promptFile = opts.promptFile ? resolve(opts.promptFile) : null;
  let tempDir = null;
  if (!promptFile || opts.antiOverengineering) {
    tempDir = mkdtempSync(join(tmpdir(), "fanout-review-"));
    promptFile = join(tempDir, "review.md");
    writeFileSync(promptFile, prompt || "(dry run)", "utf8");
  }

  const commands = reviewers.map((model) => buildReviewerCommand(model, cwd, promptFile));

  if (opts.dryRun) {
    const report = { status: "dry-run", cwd, reviewers, antiOverengineering: opts.antiOverengineering, commands, dryRun: true };
    process.stdout.write(opts.json ? JSON.stringify(report, null, 2) + "\n" : renderMarkdown(report) + "\n");
    if (tempDir) rmSync(tempDir, { recursive: true, force: true });
    return;
  }

  const results = await Promise.all(commands.map((command) => runOne(command, cwd)));
  const status = results.every((result) => result.ok)
    ? "ok"
    : results.some((result) => result.ok)
      ? "partial"
      : "error";
  const report = { status, cwd, reviewers, antiOverengineering: opts.antiOverengineering, results, dryRun: false };

  process.stdout.write(opts.json ? JSON.stringify(report, null, 2) + "\n" : renderMarkdown(report) + "\n");
  if (tempDir) rmSync(tempDir, { recursive: true, force: true });
  process.exit(results.some((result) => result.ok) ? 0 : 1);
}

main().catch((err) => {
  process.stderr.write("Fatal: " + (err && err.stack ? err.stack : String(err)) + "\n");
  process.exit(1);
});

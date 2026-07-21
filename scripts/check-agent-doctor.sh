#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCTOR="$SCRIPT_DIR/agent-doctor.sh"
JQ="$(command -v jq)"
ORIGINAL_TMPDIR="${TMPDIR:-/tmp}"
ROOT=''
CASE_DIR=''
HOME_DIR=''
BIN_DIR=''
CATALOG=''
CONFIG=''
OUTPUT=''
RC=0
TESTS=0
FAILURES=0

cleanup() {
  [ -n "$ROOT" ] && rm -rf "$ROOT"
}
trap cleanup EXIT HUP INT TERM

fail() {
  FAILURES=$((FAILURES + 1))
  printf 'not ok %s - %s\n' "$TESTS" "$1"
  printf '%s\n' "$OUTPUT" | sed 's/^/  /'
}

pass() {
  printf 'ok %s - %s\n' "$TESTS" "$1"
}

assert_rc() {
  expected="$1"
  label="$2"
  if [ "$RC" -eq "$expected" ]; then pass "$label"; else fail "$label (expected rc $expected, got $RC)"; fi
}

assert_contains() {
  needle="$1"
  label="$2"
  if printf '%s' "$OUTPUT" | grep -F -- "$needle" >/dev/null 2>&1; then pass "$label"; else fail "$label (missing: $needle)"; fi
}

assert_not_contains() {
  needle="$1"
  label="$2"
  if printf '%s' "$OUTPUT" | grep -F -- "$needle" >/dev/null 2>&1; then fail "$label (unexpected: $needle)"; else pass "$label"; fi
}

assert_json() {
  filter="$1"
  label="$2"
  if printf '%s' "$OUTPUT" | "$JQ" -e "$filter" >/dev/null 2>&1; then pass "$label"; else fail "$label (jq assertion: $filter)"; fi
}

next_test() {
  TESTS=$((TESTS + 1))
}

link_tool() {
  name="$1"
  source_path="$(command -v "$name")"
  ln -s "$source_path" "$BIN_DIR/$name"
}

write_mock() {
  name="$1"
  body="$2"
  {
    printf '#!/bin/bash\n'
    printf '%s\n' "$body"
  } >"$BIN_DIR/$name"
  chmod +x "$BIN_DIR/$name"
}

write_catalog() {
  cat >"$CATALOG" <<'JSON'
{
  "version": 1,
  "bootstrap": ["bash", "jq"],
  "harnesses": {
    "alpha": {
      "displayName": "Alpha",
      "binary": "alpha",
      "versionArgs": ["--version"],
      "configPaths": ["~/.alpha/config.json", "~/.alpha/配置.json"],
      "mcp": {"path": "~/.alpha/mcp.json", "root": "mcpServers"}
    },
    "beta": {
      "displayName": "Beta",
      "binary": "beta",
      "versionArgs": ["--version"],
      "configPaths": ["~/.beta/config.json"]
    },
    "factory": {
      "displayName": "Factory",
      "binary": "droid",
      "versionArgs": ["--version"],
      "configPaths": ["~/.factory/settings.json"]
    },
    "pi": {
      "displayName": "Pi",
      "binary": "pi",
      "versionArgs": ["--version"],
      "configPaths": ["~/.pi/agent/settings.json"],
      "providerAuth": {"path": "~/.pi/agent/auth.json"},
      "mcp": {"path": "~/.pi/agent/mcp.json", "root": "mcpServers"}
    },
    "online": {
      "displayName": "Online",
      "binary": "online",
      "versionArgs": ["--version"],
      "configPaths": ["~/.online/config.json"],
      "onlineProbe": ["auth", "status"]
    },
    "deep": {
      "displayName": "Deep",
      "binary": "deep",
      "versionArgs": ["--version"],
      "configPaths": ["~/.deep/config.json"],
      "mcp": {"path": "~/.deep/mcp.json", "root": "mcpServers"}
    }
  }
}
JSON
}

write_requirements() {
  harnesses="$1"
  providers='{}'
  mcp='{}'
  [ "$#" -ge 2 ] && providers="$2"
  [ "$#" -ge 3 ] && mcp="$3"
  printf '{"version":1,"harnesses":%s,"providers":%s,"mcp":%s}\n' "$harnesses" "$providers" "$mcp" >"$CONFIG"
}

setup_case() {
  CASE_DIR="$ROOT/case $TESTS"
  HOME_DIR="$CASE_DIR/home with spaces"
  BIN_DIR="$CASE_DIR/mock bin"
  CATALOG="$CASE_DIR/catalog with spaces.json"
  CONFIG="$HOME_DIR/config with spaces.json"
  mkdir -p "$HOME_DIR" "$BIN_DIR"
  link_tool bash
  link_tool jq
  link_tool mktemp
  link_tool rm
  link_tool dirname
  link_tool pwd
  link_tool tr
  link_tool awk
  link_tool cat
  link_tool kill
  link_tool sleep
  link_tool grep
  link_tool tail
  link_tool sed
  link_tool printenv
  write_catalog
  unset NO_COLOR MOCK_ONLINE_MODE MOCK_CURL_MODE SECRET_SENTINEL NPM_MARKER
}

make_healthy_alpha() {
  mkdir -p "$HOME_DIR/.alpha"
  printf '{}\n' >"$HOME_DIR/.alpha/config.json"
  printf '{}\n' >"$HOME_DIR/.alpha/配置.json"
  write_mock alpha 'printf "%s\n" "alpha 1.0"'
  write_requirements '["alpha"]'
}

make_harness() {
  harness="$1"
  binary="$2"
  config="$3"
  mkdir -p "$(dirname "$HOME_DIR/$config")"
  case "$config" in *.json) printf '{}\n' >"$HOME_DIR/$config" ;; *) : >"$HOME_DIR/$config" ;; esac
  write_mock "$binary" 'printf "%s\n" "mock 1.0"'
  write_requirements "[\"$harness\"]"
}

run_doctor() {
  set +e
  OUTPUT="$(HOME="$HOME_DIR" PATH="$BIN_DIR" TMPDIR="$CASE_DIR" AGENT_DOCTOR_CATALOG="$CATALOG" /bin/bash "$DOCTOR" --config "$CONFIG" "$@" 2>&1)"
  RC=$?
  set -e
}

ROOT="$(mktemp -d "$ORIGINAL_TMPDIR/agent doctor fixtures.XXXXXX")" || exit 1
set -e
next_test; setup_case; make_healthy_alpha; run_doctor --color=never
assert_rc 0 'healthy required harness exits successfully'
next_test; assert_contains '✓ Alpha: alpha 1.0' 'healthy output uses Unicode status and natural harness name'
next_test; assert_not_contains 'harness.alpha.version' 'human output hides technical check IDs'
next_test; assert_contains '~/.alpha/配置.json exists and contains valid JSON' 'Unicode config path is preserved'
next_test; assert_contains 'healthy' 'healthy output includes a natural summary'

next_test; setup_case; make_healthy_alpha; run_doctor --json
assert_rc 0 'healthy JSON exits successfully'
next_test; assert_json '.version == 1 and .exitCode == 0 and (.checks | type == "array")' 'healthy JSON parses and has the documented envelope'
next_test; assert_json '[.checks[] | select(.required and .status == "fail")] | length == 0' 'healthy JSON has no required failures'
next_test; assert_not_contains "$(printf '\033')" 'JSON contains no ANSI escapes'

next_test; setup_case; make_healthy_alpha; run_doctor --ascii --color=never
assert_contains '[+] shared catalog schema v1 is valid' 'ASCII mode replaces Unicode pass icon'
next_test; assert_not_contains '✓' 'ASCII mode emits no Unicode pass icon'

next_test; setup_case; make_healthy_alpha; run_doctor --color=never
assert_not_contains "$(printf '\033')" 'color never emits no ANSI escapes'
next_test; setup_case; make_healthy_alpha; export NO_COLOR=1; run_doctor --color=always
assert_not_contains "$(printf '\033')" 'NO_COLOR overrides color always'

next_test; setup_case; make_healthy_alpha; run_doctor --json
assert_not_contains 'harness.beta.' 'catalogued but unlisted harness is ignored'

next_test; setup_case; write_requirements '["beta"]'; run_doctor --json
assert_rc 1 'missing required harness exits one'
next_test; assert_json 'any(.checks[]; .id == "harness.beta.executable" and .status == "fail" and .required)' 'missing required harness executable is a required failure'

next_test; setup_case; make_harness factory droid '.factory/settings.json'; run_doctor --json
assert_rc 0 'factory requirement resolves through droid'
next_test; assert_json 'any(.checks[]; .id == "harness.factory.executable" and .status == "pass" and (.message | startswith("droid resolves")))' 'factory executable assertion names droid'

next_test; setup_case; printf '{bad json\n' >"$CONFIG"; run_doctor --json
assert_rc 2 'malformed requirements exit two'
next_test; assert_json '.exitCode == 2 and any(.checks[]; .id == "requirements.invalid" and .status == "fail")' 'malformed requirements return structured failure'

next_test; setup_case; printf '{"version":2,"harnesses":[],"providers":{},"mcp":{}}\n' >"$CONFIG"; run_doctor --json
assert_rc 2 'unsupported requirements version exits two'
next_test; assert_json 'any(.checks[]; .id == "requirements.invalid")' 'unsupported requirements version is rejected'

next_test; setup_case; write_requirements '["alpha","alpha"]'; run_doctor --json
assert_rc 2 'duplicate requirement exits two'
next_test; assert_json 'any(.checks[]; .id == "requirements.invalid")' 'duplicate requirement is identified as invalid requirements'

next_test; setup_case; write_requirements '["unknown"]'; run_doctor --json
assert_rc 2 'unknown requirement exits two'
next_test; assert_json 'any(.checks[]; .id == "requirements.invalid")' 'unknown requirement is identified as invalid requirements'

next_test; setup_case; make_healthy_alpha; run_doctor --definitely-invalid
assert_rc 64 'invalid option exits EX_USAGE 64'
next_test; assert_contains 'unknown option: --definitely-invalid' 'invalid option explains the usage error'

next_test; setup_case; make_healthy_alpha; mkdir -p "$HOME_DIR/.beta"; printf '{}\n' >"$HOME_DIR/.beta/config.json"; write_mock beta 'exit 99'; write_requirements '["alpha","beta"]'; run_doctor --only alpha --json
assert_rc 0 '--only limits checks to the selected required harness'
next_test; assert_not_contains 'harness.beta.' '--only omits other required harness checks'
next_test; setup_case; make_healthy_alpha; run_doctor --only beta --json
assert_rc 64 '--only rejects a catalogued harness not required on this machine'

next_test; setup_case; write_requirements '["beta"]'; run_doctor --json
assert_json 'any(.checks[]; .id == "harness.beta.executable" and .status == "fail") and any(.checks[]; .id == "harness.beta.version" and .status == "skip")' 'missing command fails executable and skips version'
next_test; setup_case; mkdir -p "$HOME_DIR/.beta"; printf '{}\n' >"$HOME_DIR/.beta/config.json"; printf '#!/bin/bash\nexit 0\n' >"$BIN_DIR/beta"; chmod 0644 "$BIN_DIR/beta"; write_requirements '["beta"]'; run_doctor --json
assert_json 'any(.checks[]; .id == "harness.beta.executable" and .status == "fail") and any(.checks[]; .id == "harness.beta.version" and .status == "skip")' 'non-runnable command fails executable and skips version'
next_test; setup_case; make_healthy_alpha; printf '{invalid\n' >"$HOME_DIR/.alpha/config.json"; run_doctor --json
assert_rc 1 'malformed required JSON config exits one'
next_test; assert_json 'any(.checks[]; (.id | startswith("harness.alpha.config.")) and .status == "fail" and (.message | contains("not valid JSON")))' 'required JSON config is parsed without printing contents'

next_test; setup_case; make_harness pi pi '.pi/agent/settings.json'; mkdir -p "$HOME_DIR/.pi/agent"; printf '{"other":{"token":"CHILD_SECRET_SENTINEL"}}\n' >"$HOME_DIR/.pi/agent/auth.json"; write_requirements '["pi"]' '{"pi":["anthropic"]}'; run_doctor --json
assert_rc 1 'missing required Pi provider exits one'
next_test; assert_json 'any(.checks[]; .id == "provider.pi.anthropic" and .status == "fail" and (.message | contains("absent")))' 'missing Pi provider has a precise status'
next_test; assert_not_contains 'CHILD_SECRET_SENTINEL' 'Pi auth contents never leak'

next_test; setup_case; make_healthy_alpha; write_requirements '["alpha"]' '{}' '{"alpha":["context7"]}'; run_doctor --json
assert_rc 1 'missing MCP registration exits one'
next_test; assert_json 'any(.checks[]; .id == "mcp.alpha.context7.static" and .status == "fail")' 'missing MCP registry is a required failure'
next_test; setup_case; make_harness deep deep '.deep/config.json'; printf '%s\n' '{"mcpServers":{"worker":{"command":"missing-worker"}}}' >"$HOME_DIR/.deep/mcp.json"; write_requirements '["deep"]' '{}' '{"deep":["worker"]}'; run_doctor --json
assert_json 'any(.checks[]; .id == "mcp.deep.worker.static" and .status == "fail" and (.message | contains("unavailable")))' 'stdio MCP command must exist and be executable'
next_test; setup_case; make_harness deep deep '.deep/config.json'; write_mock worker 'exit 0'; printf '%s\n' '{"mcpServers":{"worker":{"command":"worker","env":{"TOKEN":"${REQUIRED_TOKEN}"}}}}' >"$HOME_DIR/.deep/mcp.json"; unset REQUIRED_TOKEN; write_requirements '["deep"]' '{}' '{"deep":["worker"]}'; run_doctor --json
assert_json 'any(.checks[]; .id == "mcp.deep.worker.env.REQUIRED_TOKEN" and .status == "fail" and (.message | contains("REQUIRED_TOKEN")))' 'recognized unset MCP environment variable fails by name'
next_test; assert_not_contains 'TOKEN_VALUE_SENTINEL' 'MCP environment checks never print values'
next_test; setup_case; make_harness alpha alpha '.alpha/config.json'; run_doctor --online --color=never
assert_contains 'unknown' 'unsupported requested online probe is visibly unknown rather than green'

next_test; setup_case; make_harness online online '.online/config.json'; write_mock online 'if [ "${1:-}" = "--version" ]; then echo "online 1"; exit 0; fi; case "${MOCK_ONLINE_MODE:-success}" in success) echo "logged in";; failure) echo "CHILD_SECRET_SENTINEL"; exit 9;; timeout) echo "CHILD_SECRET_SENTINEL"; sleep 20;; esac'; export MOCK_ONLINE_MODE=success; run_doctor --online --json
assert_json 'any(.checks[]; .id == "online.online.auth" and .status == "pass")' 'online success is normalized to pass'
next_test; setup_case; make_harness online online '.online/config.json'; write_mock online 'if [ "${1:-}" = "--version" ]; then echo "online 1"; exit 0; fi; echo "CHILD_SECRET_SENTINEL"; exit 9'; run_doctor --online --json
assert_rc 1 'nonzero documented authentication probe is required failure'
next_test; assert_json 'any(.checks[]; .id == "online.online.auth" and .status == "fail" and .required and (.message | contains("not logged in")))' 'online failure is normalized without child output'
next_test; assert_not_contains 'CHILD_SECRET_SENTINEL' 'failed online probe never leaks child secret'
next_test; setup_case; make_harness online online '.online/config.json'; write_mock online 'if [ "${1:-}" = "--version" ]; then echo "online 1"; exit 0; fi; echo "not logged in"'; run_doctor --online --json
assert_rc 1 'explicit logged-out authentication status is required failure'
next_test; setup_case; make_harness online online '.online/config.json'; write_mock online 'if [ "${1:-}" = "--version" ]; then echo "online 1"; exit 0; fi; echo "CHILD_SECRET_SENTINEL"; sleep 20'; run_doctor --online --json
assert_json 'any(.checks[]; .id == "online.online.auth" and .status == "unknown" and .required and (.message | contains("timed out")))' 'online timeout is normalized to required unknown'
next_test; assert_not_contains 'CHILD_SECRET_SENTINEL' 'timed-out online probe never leaks child secret'

next_test; setup_case; make_harness deep deep '.deep/config.json'; cat >"$HOME_DIR/.deep/mcp.json" <<'JSON'
{"mcpServers":{"remote":{"type":"http","url":"https://fixture.invalid/mcp"}}}
JSON
write_mock curl 'case "${MOCK_CURL_MODE:-success}" in success) printf 204;; failure) echo "CHILD_SECRET_SENTINEL"; exit 7;; timeout) echo "CHILD_SECRET_SENTINEL"; sleep 20;; esac'; write_requirements '["deep"]' '{}' '{"deep":["remote"]}'; export MOCK_CURL_MODE=success; run_doctor --deep --json
assert_json 'any(.checks[]; .id == "mcp.deep.remote.deep" and .status == "pass" and (.message | contains("204")))' 'deep HTTP success is reported without network access'
next_test; setup_case; make_harness deep deep '.deep/config.json'; printf '%s\n' '{"mcpServers":{"remote":{"type":"http","url":"https://fixture.invalid/mcp"}}}' >"$HOME_DIR/.deep/mcp.json"; write_mock curl 'echo "CHILD_SECRET_SENTINEL"; exit 7'; write_requirements '["deep"]' '{}' '{"deep":["remote"]}'; run_doctor --deep --json
assert_json 'any(.checks[]; .id == "mcp.deep.remote.deep" and .status == "fail" and (.message | contains("failed")))' 'deep HTTP failure is normalized'
next_test; assert_not_contains 'CHILD_SECRET_SENTINEL' 'failed deep probe never leaks child secret'
next_test; setup_case; make_harness deep deep '.deep/config.json'; printf '%s\n' '{"mcpServers":{"remote":{"type":"http","url":"https://fixture.invalid/mcp"}}}' >"$HOME_DIR/.deep/mcp.json"; write_mock curl 'echo "CHILD_SECRET_SENTINEL"; sleep 20'; write_requirements '["deep"]' '{}' '{"deep":["remote"]}'; run_doctor --deep --json
assert_json 'any(.checks[]; .id == "mcp.deep.remote.deep" and .status == "fail" and (.message | contains("timed out")))' 'deep HTTP timeout is normalized'
next_test; assert_not_contains 'CHILD_SECRET_SENTINEL' 'timed-out deep probe never leaks child secret'

next_test; setup_case; make_harness deep deep '.deep/config.json'; printf '%s\n' '{"mcpServers":{"unsafe":{"command":"npx","args":["-y","untrusted-package"]}}}' >"$HOME_DIR/.deep/mcp.json"; NPM_MARKER="$CASE_DIR/npx-ran"; export NPM_MARKER; write_mock npx 'printf ran >"$NPM_MARKER"'; write_mock curl 'exit 88'; write_requirements '["deep"]' '{}' '{"deep":["unsafe"]}'; run_doctor --deep --json
assert_json 'any(.checks[]; .id == "mcp.deep.unsafe.deep" and .status == "unknown" and (.message | contains("explicitly refuses npx -y")))' 'deep check explicitly refuses npx -y stdio transport'
next_test; if [ ! -e "$NPM_MARKER" ]; then pass 'deep refusal does not execute npx'; else fail 'deep refusal executed npx'; fi

next_test; setup_case; make_healthy_alpha; catalog_tmp="$CASE_DIR/catalog.tmp"; "$JQ" '.skills={"manifest":"~/.agents/skill-targets.json"}' "$CATALOG" >"$catalog_tmp"; cat "$catalog_tmp" >"$CATALOG"; mkdir -p "$HOME_DIR/.agents/skills/bro"; printf '%s\n' '{"canonical_root":"~/.agents/skills","harnesses":{"alpha":{"discovery":"canonical","skills_root":"~/.agents/skills"}},"skills":{"bro":["alpha"]}}' >"$HOME_DIR/.agents/skill-targets.json"; run_doctor --json
assert_json 'any(.checks[]; .id == "skill.alpha.bro" and .status == "pass")' 'valid skill manifest reaches portable skill checks'
next_test; assert_json 'all(.checks[]; .id != "skills.manifest")' 'valid skill manifest is not misclassified as invalid'

next_test; setup_case; make_healthy_alpha; link_tool git; source_dir="$CASE_DIR/git-source"; mkdir -p "$source_dir/dot_agents"; cp "$CATALOG" "$source_dir/dot_agents/catalog.json"; CATALOG="$source_dir/dot_agents/catalog.json"; git -C "$source_dir" init -q; git -C "$source_dir" config user.name Doctor; git -C "$source_dir" config user.email doctor@example.invalid; git -C "$source_dir" add dot_agents/catalog.json; git -C "$source_dir" commit -qm fixture; run_doctor --color=never
assert_contains 'source Git checkout is clean' 'Git source cleanliness is checked without filenames'
next_test; printf 'private\n' >"$source_dir/SECRET_PATH_SENTINEL"; run_doctor --color=never
assert_contains 'source Git checkout has 1 dirty item(s)' 'dirty Git source reports only a count'
next_test; assert_not_contains 'SECRET_PATH_SENTINEL' 'dirty Git source never prints paths'

next_test; setup_case; write_requirements '["beta"]'; run_doctor --json
assert_json '.exitCode == 1 and .summary.fail == ([.checks[] | select(.status == "fail")] | length) and ([.checks[] | select(.required and .status == "fail")] | length) > 0' 'JSON summary, required failures, and exit code agree'
next_test; assert_rc 1 'process exit agrees with JSON exitCode'

printf '1..%s\n' "$TESTS"
if [ "$FAILURES" -ne 0 ]; then
  printf '# %s of %s assertions failed\n' "$FAILURES" "$TESTS"
  exit 1
fi
printf '# all %s assertions passed\n' "$TESTS"

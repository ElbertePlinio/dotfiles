#!/usr/bin/env bash
set -uo pipefail

EX_USAGE=64
JSON_MODE=0
ONLINE=0
DEEP=0
VERBOSE=0
ASCII=0
COLOR_MODE=auto
ONLY=''
CONFIG="${HOME}/.config/agent-config-sync/doctor.json"
CATALOG="${AGENT_DOCTOR_CATALOG:-}"
TMP=''
RESULTS=''
SOURCE=''
ACTIVE_PID=''

usage() {
  cat <<'EOF'
Usage: agent-config-sync doctor [options]

  --config PATH          Machine-local requirements (default: ~/.config/agent-config-sync/doctor.json)
  --json                 Emit JSON
  --only NAME            Check one required harness
  --online               Run safe noninteractive authentication probes
  --deep                 Add safe MCP connectivity checks; implies --online
  --verbose              Include skipped checks
  --ascii                Use ASCII status icons
  --color=auto|always|never
  --help
EOF
}

usage_error() {
  printf 'agent-config-sync doctor: %s\n' "$1" >&2
  usage >&2
  exit "$EX_USAGE"
}

expand_home() {
  case "$1" in
    '~') printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s/%s\n' "$HOME" "${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

cleanup() {
  [[ -n "$TMP" ]] && rm -rf "$TMP"
}
handle_signal() {
  local signal="$1" code="$2"
  trap - INT TERM HUP
  if [[ -n "$ACTIVE_PID" ]]; then
    local attempts=0
    kill -"$signal" -- "-$ACTIVE_PID" 2>/dev/null || kill -"$signal" "$ACTIVE_PID" 2>/dev/null || true
    while kill -0 "$ACTIVE_PID" 2>/dev/null && [[ "$attempts" -lt 10 ]]; do
      sleep 0.1
      attempts=$((attempts + 1))
    done
    if kill -0 "$ACTIVE_PID" 2>/dev/null; then
      kill -KILL -- "-$ACTIVE_PID" 2>/dev/null || kill -KILL "$ACTIVE_PID" 2>/dev/null || true
    fi
    wait "$ACTIVE_PID" 2>/dev/null || true
    ACTIVE_PID=''
  fi
  exit "$code"
}
trap cleanup EXIT
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM
trap 'handle_signal HUP 129' HUP

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || usage_error '--config requires a path'
      CONFIG="$2"
      shift 2
      ;;
    --config=*) CONFIG="${1#*=}"; [[ -n "$CONFIG" ]] || usage_error '--config requires a path'; shift ;;
    --json) JSON_MODE=1; shift ;;
    --only)
      [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || usage_error '--only requires a harness name'
      ONLY="$2"
      shift 2
      ;;
    --only=*) ONLY="${1#*=}"; [[ -n "$ONLY" ]] || usage_error '--only requires a harness name'; shift ;;
    --online) ONLINE=1; shift ;;
    --deep) DEEP=1; ONLINE=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    --ascii) ASCII=1; shift ;;
    --color=auto|--color=always|--color=never) COLOR_MODE="${1#*=}"; shift ;;
    --color) usage_error '--color requires =auto, =always, or =never' ;;
    --help|-h) usage; exit 0 ;;
    --*) usage_error "unknown option: $1" ;;
    *) usage_error "unexpected argument: $1" ;;
  esac
done

CONFIG="$(expand_home "$CONFIG")"

if ! command -v jq >/dev/null 2>&1; then
  printf 'agent-config-sync doctor: jq is required; install jq and retry\n' >&2
  exit 2
fi

if ! TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-doctor.XXXXXX")"; then
  printf 'agent-config-sync doctor: cannot create temporary directory\n' >&2
  exit 2
fi
RESULTS="$TMP/checks.ndjson"
: >"$RESULTS"

if [[ -z "$CATALOG" ]]; then
  SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
  CATALOG="$SOURCE/dot_agents/doctor-targets.json"
else
  CATALOG="$(expand_home "$CATALOG")"
  SOURCE="$(cd "$(dirname "$CATALOG")/.." 2>/dev/null && pwd || true)"
fi

add_check() {
  local id="$1" status="$2" required="$3" harness="$4" message="$5"
  jq -cn \
    --arg id "$id" --arg status "$status" --argjson required "$required" \
    --arg harness "$harness" --arg message "$message" \
    '{id:$id,status:$status,required:$required,harness:(if $harness=="" then null else $harness end),message:$message}' \
    >>"$RESULTS"
}

emit_early_error() {
  local id="$1" message="$2"
  add_check "$id" fail true '' "$message"
  emit_output 2
  exit 2
}

validate_catalog() {
  jq -e '
    type == "object" and .version == 1 and
    (.bootstrap | type == "array" and all(.[]; type == "string" and length > 0)) and
    (.harnesses | type == "object" and length > 0 and
      all(to_entries[];
        (.key | type == "string" and length > 0) and
        (.value | type == "object") and
        (.value.displayName | type == "string" and length > 0) and
        (.value.binary | type == "string" and length > 0) and
        (.value.versionArgs | type == "array" and all(.[]; type == "string")) and
        (.value.configPaths | type == "array" and all(.[]; type == "string" and length > 0)) and
        ((.value.mcp? // null) as $m | $m == null or
          ($m | type == "object" and (.path | type == "string" and length > 0) and
            (.root | type == "string" and length > 0) and
            ((has("disabledKey") | not) or (.disabledKey | type == "string" and length > 0)))))) and
    (.harnesses.pi.providerAuth as $auth |
      ($auth.path | type == "string" and length > 0) and
      ($auth.modelsPath | type == "string" and length > 0) and
      ($auth.env | type == "object" and all(.[]; type == "array" and all(.[]; type == "string" and length > 0)))) and
    ((.lanes? // null) as $lanes | $lanes == null or (
      ($lanes.runtime.root | type == "string" and length > 0) and
      (($lanes.runtime.packageFile? // "package.json") | type == "string" and length > 0) and
      (($lanes.runtime.tableEntry? // "src/table.ts") | type == "string" and length > 0) and
      (($lanes.runtime.requiredFiles? // []) | type == "array" and all(.[]; type == "string" and length > 0) and length == (unique | length)) and
      ($lanes.pi.settingsPath | type == "string" and length > 0) and
      (($lanes.pi.packagesKey? // "packages") | type == "string" and length > 0) and
      ($lanes.claudeCode.binary | type == "string" and length > 0) and
      ($lanes.claudeCode.minVersion | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))
    ))
  ' "$CATALOG" >/dev/null 2>&1
}

validate_requirements() {
  jq -e --slurpfile cat "$CATALOG" '
    . as $req |
    type == "object" and .version == 1 and
    (.harnesses | type == "array" and all(.[]; type == "string" and length > 0)) and
    ((.harnesses | length) == (.harnesses | unique | length)) and
    (.providers | type == "object") and
    (.mcp | type == "object") and
    (($req.harnesses - ($cat[0].harnesses | keys)) | length == 0) and
    (($req.providers | keys) - ["pi"] | length == 0) and
    ((($req.providers | keys) - $req.harnesses) | length == 0) and
    ((($req.mcp | keys) - $req.harnesses) | length == 0) and
    (all(.providers[];
      type == "array" and all(.[]; type == "string" and length > 0) and length == (unique | length))) and
    (all(.mcp[];
      type == "array" and all(.[]; type == "string" and length > 0) and length == (unique | length))) and
    (((.lanes? // {}) | type) == "object") and
    (((.lanes? // {}) | keys) - ["pi","claude-code"] | length == 0) and
    ((.lanes.pi? // []) | type == "array" and all(.[]; type == "string" and length > 0) and length == (unique | length)) and
    ((.lanes["claude-code"]? // []) | type == "array" and all(.[]; type == "string" and length > 0) and length == (unique | length)) and
    ((((.lanes.pi? // []) | length) == 0) or (.harnesses | index("pi") != null)) and
    ((((.lanes["claude-code"]? // []) | length) == 0) or (.harnesses | index("claude") != null))
  ' "$CONFIG" >/dev/null 2>&1
}

sanitize_line() {
  LC_ALL=C tr '\r\n\t' '   ' <"$1" | tr -cd '[:print:] ' | awk '{gsub(/[[:space:]]+/," "); sub(/^ /,""); print substr($0,1,160); exit}'
}

run_capture() {
  local seconds="$1" output="$2"
  shift 2
  local pid ticks=0 max_ticks rc
  max_ticks=$((seconds * 10))
  # Monitor mode gives the child its own process group on Bash 3.2.
  set -m
  "$@" </dev/null >"$output" 2>&1 &
  pid=$!
  ACTIVE_PID="$pid"
  set +m
  while kill -0 "$pid" 2>/dev/null; do
    if [[ "$ticks" -ge "$max_ticks" ]]; then
      kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      sleep 0.1
      kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      ACTIVE_PID=''
      return 124
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done
  if wait "$pid"; then rc=0; else rc=$?; fi
  ACTIVE_PID=''
  return "$rc"
}

check_bootstrap() {
  local command_name
  while IFS= read -r command_name; do
    if command -v "$command_name" >/dev/null 2>&1; then
      add_check "bootstrap.$command_name" pass true '' "$command_name is available"
    else
      add_check "bootstrap.$command_name" fail true '' "$command_name is required by doctor"
    fi
  done < <(jq -r '.bootstrap[]' "$CATALOG")
  if [[ "$DEEP" -eq 1 ]]; then
    if command -v curl >/dev/null 2>&1; then
      add_check bootstrap.curl pass true '' 'curl is available for deep HTTP checks'
    else
      add_check bootstrap.curl fail true '' 'curl is required for deep HTTP checks'
    fi
  fi
}

selected_harnesses() {
  if [[ -n "$ONLY" ]]; then
    jq -r --arg only "$ONLY" '.harnesses[] | select(. == $only)' "$CONFIG"
  else
    jq -r '.harnesses[]' "$CONFIG"
  fi
}

check_harness() {
  local harness="$1" binary resolved output rc summary path expanded config_id
  binary="$(jq -r --arg h "$harness" '.harnesses[$h].binary' "$CATALOG")"
  resolved="$(command -v "$binary" 2>/dev/null || true)"
  if [[ -z "$resolved" ]]; then
    add_check "harness.$harness.executable" fail true "$harness" "$binary was not found on PATH"
    add_check "harness.$harness.version" skip true "$harness" 'version check skipped because executable is missing'
  elif [[ ! -x "$resolved" ]]; then
    add_check "harness.$harness.executable" fail true "$harness" "$resolved is not executable"
    add_check "harness.$harness.version" skip true "$harness" 'version check skipped because executable is not runnable'
  else
    add_check "harness.$harness.executable" pass true "$harness" "$binary resolves to $resolved"
    output="$TMP/version-$harness"
    while IFS= read -r path; do
      VERSION_ARGS+=("$path")
    done < <(jq -r --arg h "$harness" '.harnesses[$h].versionArgs[]' "$CATALOG")
    if run_capture 5 "$output" "$resolved" "${VERSION_ARGS[@]}"; then
      summary="$(sanitize_line "$output")"
      [[ -n "$summary" ]] || summary='version command succeeded'
      add_check "harness.$harness.version" pass true "$harness" "$summary"
    else
      rc=$?
      if [[ "$rc" -eq 124 ]]; then summary='version command timed out'; else summary='version command failed'; fi
      add_check "harness.$harness.version" fail true "$harness" "$summary"
    fi
    VERSION_ARGS=()
  fi

  while IFS= read -r path; do
    expanded="$(expand_home "$path")"
    config_id="harness.$harness.config.$(printf '%s' "$path" | tr -c 'A-Za-z0-9' '.')"
    if [[ ! -e "$expanded" && ! -L "$expanded" ]]; then
      add_check "$config_id" fail true "$harness" "$path is missing"
    elif [[ "$path" == *.json ]] && ! jq -e . "$expanded" >/dev/null 2>&1; then
      add_check "$config_id" fail true "$harness" "$path is not valid JSON"
    elif [[ "$path" == *.json ]]; then
      add_check "$config_id" pass true "$harness" "$path exists and contains valid JSON"
    else
      add_check "$config_id" pass true "$harness" "$path exists"
    fi
  done < <(jq -r --arg h "$harness" '.harnesses[$h].configPaths[]' "$CATALOG")
}

check_providers() {
  local harness provider auth_path models_path api_key env_name present=0
  while IFS=$'\t' read -r harness provider; do
    present=0
    auth_path="$(expand_home "$(jq -r '.harnesses.pi.providerAuth.path' "$CATALOG")")"
    models_path="$(expand_home "$(jq -r '.harnesses.pi.providerAuth.modelsPath' "$CATALOG")")"
    if [[ -f "$auth_path" ]] && jq -e --arg provider "$provider" 'type == "object" and has($provider)' "$auth_path" >/dev/null 2>&1; then
      present=1
    fi
    while [[ "$present" -eq 0 ]] && IFS= read -r env_name; do
      [[ -n "$env_name" ]] && printenv "$env_name" >/dev/null 2>&1 && present=1
    done < <(jq -r --arg provider "$provider" '.harnesses.pi.providerAuth.env[$provider][]? // empty' "$CATALOG")
    api_key=''
    if [[ "$present" -eq 0 && -f "$models_path" ]]; then
      api_key="$(jq -r --arg provider "$provider" '(.providers[$provider].apiKey // .[$provider].apiKey // empty) | select(type == "string")' "$models_path" 2>/dev/null || true)"
      case "$api_key" in
        '') ;;
        '! '*) present=1 ;;
        '!'*) present=1 ;;
        '${'*'}') env_name="${api_key#'${'}"; env_name="${env_name%'}'}"; printenv "$env_name" >/dev/null 2>&1 && present=1 ;;
        '$'*) env_name="${api_key#'$'}"; [[ "$env_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && printenv "$env_name" >/dev/null 2>&1 && present=1 ;;
        *) present=1 ;;
      esac
    fi
    if [[ "$present" -eq 1 ]]; then
      add_check "provider.$harness.$provider" pass true "$harness" "provider credential configuration for $provider is present; remote validity was not checked"
    else
      add_check "provider.$harness.$provider" fail true "$harness" "provider credential configuration for $provider is absent"
    fi
  done < <(jq -r --arg only "$ONLY" '.providers | to_entries[] | select($only == "" or .key == $only) | .key as $h | .value[] | [$h,.] | @tsv' "$CONFIG")
}

mcp_descriptor() {
  jq -e --arg h "$1" '.harnesses[$h].mcp // empty' "$CATALOG" >/dev/null 2>&1
}

check_mcp() {
  local harness server configured_path path root disabled_key type url status output code command_name resolved env_name static_ok args_y
  while IFS=$'\t' read -r harness server; do
    command_name=''
    if ! mcp_descriptor "$harness"; then
      add_check "mcp.$harness.$server.static" unknown true "$harness" 'static MCP inspection is not supported'
      [[ "$DEEP" -eq 1 ]] && add_check "mcp.$harness.$server.deep" unknown true "$harness" 'deep MCP inspection is not supported'
      continue
    fi
    configured_path="$(jq -r --arg h "$harness" '.harnesses[$h].mcp.path' "$CATALOG")"
    root="$(jq -r --arg h "$harness" '.harnesses[$h].mcp.root' "$CATALOG")"
    path="$(expand_home "$configured_path")"
    if [[ ! -f "$path" ]]; then
      add_check "mcp.$harness.$server.static" fail true "$harness" "$configured_path is missing"
      [[ "$DEEP" -eq 1 ]] && add_check "mcp.$harness.$server.deep" skip true "$harness" 'deep check skipped because static config is missing'
      continue
    fi
    if ! jq -e --arg root "$root" --arg server "$server" 'type == "object" and (.[$root] | type == "object" and has($server) and (.[$server] | type == "object"))' "$path" >/dev/null 2>&1; then
      add_check "mcp.$harness.$server.static" fail true "$harness" "MCP server $server is absent or invalid"
      [[ "$DEEP" -eq 1 ]] && add_check "mcp.$harness.$server.deep" skip true "$harness" 'deep check skipped because static registry entry is missing'
      continue
    fi
    disabled_key="$(jq -r --arg h "$harness" '.harnesses[$h].mcp.disabledKey // empty' "$CATALOG")"
    if ! jq -e --arg root "$root" --arg server "$server" --arg disabled "$disabled_key" '
      ((.[$root][$server] | has("enabled") | not) or .[$root][$server].enabled != false)
      and ($disabled == "" or (((.[$disabled] // []) | type) == "array" and ((.[$disabled] // []) | index($server)) == null))
    ' "$path" >/dev/null 2>&1; then
      add_check "mcp.$harness.$server.static" fail true "$harness" "MCP server $server is disabled"
      [[ "$DEEP" -eq 1 ]] && add_check "mcp.$harness.$server.deep" skip true "$harness" 'deep check skipped because the server is disabled'
      continue
    fi
    type="$(jq -r --arg root "$root" --arg server "$server" '.[$root][$server] | if has("type") then .type elif (.url? | type) == "string" then "http" else "stdio" end | if type == "string" then . else "__invalid__" end' "$path" 2>/dev/null || true)"
    url="$(jq -r --arg root "$root" --arg server "$server" '.[$root][$server].url // empty | if type == "string" then . else "" end' "$path" 2>/dev/null || true)"
    static_ok=1
    case "$type" in
      http|remote)
        if [[ ! "$url" =~ ^https?://[^/[:space:]]+(/[^[:space:]]*)?$ ]]; then
          add_check "mcp.$harness.$server.static" fail true "$harness" "MCP server $server remote registration has an invalid HTTP URL"
          static_ok=0
        elif ! jq -e --arg root "$root" --arg server "$server" '
          .[$root][$server] as $entry
          | ((($entry.headers // {}) | type) == "object" and all(($entry.headers // {})[]; type == "string"))
            and ((($entry.env // {}) | type) == "object" and all(($entry.env // {})[]; type == "string"))
        ' "$path" >/dev/null 2>&1; then
          add_check "mcp.$harness.$server.static" fail true "$harness" "MCP server $server remote registration is malformed"
          static_ok=0
        fi
        ;;
      stdio|local) ;;
      *)
        add_check "mcp.$harness.$server.static" fail true "$harness" "MCP server $server has an unsupported transport type"
        static_ok=0
        ;;
    esac
    if [[ "$static_ok" -eq 1 && "$type" != http && "$type" != remote ]]; then
      if ! jq -e --arg root "$root" --arg server "$server" '
        .[$root][$server] as $entry
        | (($entry.command | type == "string" and length > 0)
            or ($entry.command | type == "array" and length > 0 and all(.[]; type == "string")))
          and ((($entry.args // []) | type) == "array" and all($entry.args[]?; type == "string"))
          and ((($entry.env // {}) | type) == "object" and all(($entry.env // {})[]; type == "string"))
      ' "$path" >/dev/null 2>&1; then
        add_check "mcp.$harness.$server.static" fail true "$harness" "MCP server $server stdio registration is malformed"
        static_ok=0
      fi
      if [[ "$static_ok" -eq 1 ]]; then
        command_name="$(jq -r --arg root "$root" --arg server "$server" '.[$root][$server].command | if type == "array" then .[0] else . end' "$path")"
        case "$command_name" in
          '~'|'~/'*) resolved="$(expand_home "$command_name")" ;;
          */*) resolved="$command_name" ;;
          *) resolved="$(command -v "$command_name" 2>/dev/null || true)" ;;
        esac
        if [[ -z "$resolved" || ! -x "$resolved" ]]; then
          add_check "mcp.$harness.$server.static" fail true "$harness" "MCP server $server command is unavailable or not executable"
          static_ok=0
        fi
      fi
    fi
    while [[ "$static_ok" -eq 1 ]] && IFS= read -r env_name; do
      [[ -n "$env_name" ]] || continue
      if ! printenv "$env_name" >/dev/null 2>&1; then
        add_check "mcp.$harness.$server.env.$env_name" fail true "$harness" "MCP server $server requires unset environment variable $env_name"
        static_ok=0
      else
        add_check "mcp.$harness.$server.env.$env_name" pass true "$harness" "MCP server $server environment variable $env_name is set"
      fi
    done < <(jq -r --arg root "$root" --arg server "$server" '
      [((.[$root][$server].env // {}) | to_entries[]?.value), ((.[$root][$server].headers // {}) | to_entries[]?.value)][]
      | select(type == "string")
      | if test("^\\$[A-Za-z_][A-Za-z0-9_]*$") then sub("^\\$"; "")
        elif test("^\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}$") then sub("^\\$\\{"; "") | sub("\\}$"; "")
        elif test("^\\{env:[A-Za-z_][A-Za-z0-9_]*\\}$") then sub("^\\{env:"; "") | sub("\\}$"; "")
        else empty end
    ' "$path" 2>/dev/null)
    if [[ "$static_ok" -eq 1 ]]; then
      add_check "mcp.$harness.$server.static" pass true "$harness" "MCP server $server registration is valid"
    fi
    [[ "$DEEP" -eq 1 ]] || continue
    if [[ "$type" != http && "$type" != remote ]]; then
      args_y="$(jq -r --arg root "$root" --arg server "$server" '[.[$root][$server].args[]?, (.[$root][$server].command | arrays[]?)] | map(select(. == "-y" or . == "--yes")) | length' "$path")"
      if [[ "$command_name" == npx && "$args_y" -gt 0 ]]; then
        add_check "mcp.$harness.$server.deep" unknown true "$harness" 'deep check explicitly refuses npx -y stdio execution'
      else
        add_check "mcp.$harness.$server.deep" unknown true "$harness" 'stdio MCP transports are not executed'
      fi
      continue
    fi
    if [[ ! "$url" =~ ^https?:// ]]; then
      add_check "mcp.$harness.$server.deep" unknown true "$harness" 'HTTP MCP endpoint is missing or unsupported'
      continue
    fi
    if ! command -v curl >/dev/null 2>&1; then
      add_check "mcp.$harness.$server.deep" unknown true "$harness" 'curl is unavailable'
      continue
    fi
    output="$TMP/mcp-$harness-$(printf '%s' "$server" | tr -c 'A-Za-z0-9' '_')"
    if run_capture 7 "$output" curl --silent --show-error --output /dev/null --write-out '%{http_code}' --connect-timeout 4 --max-time 6 "$url"; then
      code="$(tr -cd '0-9' <"$output" | tail -c 3)"
      case "$code" in
        401|403) add_check "mcp.$harness.$server.deep" warn true "$harness" "endpoint is reachable and requires authentication ($code)" ;;
        2??|3??|4??) add_check "mcp.$harness.$server.deep" pass true "$harness" "endpoint is reachable ($code)" ;;
        *) add_check "mcp.$harness.$server.deep" fail true "$harness" 'endpoint did not return an HTTP response' ;;
      esac
    else
      status=$?
      if [[ "$status" -eq 124 ]]; then
        add_check "mcp.$harness.$server.deep" fail true "$harness" 'endpoint connectivity check timed out'
      else
        add_check "mcp.$harness.$server.deep" fail true "$harness" 'endpoint connectivity check failed'
      fi
    fi
  done < <(jq -r --arg only "$ONLY" '.mcp | to_entries[] | select($only == "" or .key == $only) | .key as $h | .value[] | [$h,.] | @tsv' "$CONFIG")
}

lane_sanitize_id() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9' '.'
}

# Rejects only the known literal bypass flags below; this is not an
# exhaustive detector for every way a wrapper could grant bypass permissions.
wrapper_has_permission_bypass() {
  local path="$1" shebang
  shebang="$(head -c 2 "$path" 2>/dev/null)" || return 0
  [[ "$shebang" == '#!' ]] || return 1
  if head -c 65536 "$path" 2>/dev/null | grep -aFq -- '--dangerously-skip-permissions'; then return 0; fi
  if head -c 65536 "$path" 2>/dev/null | grep -aEq -- '--permission-mode(=|[[:space:]]+)bypassPermissions'; then return 0; fi
  return 1
}

version_at_least() {
  local left="$1" right="$2" l1 l2 l3 r1 r2 r3
  IFS='.' read -r l1 l2 l3 <<<"$left"
  IFS='.' read -r r1 r2 r3 <<<"$right"
  l1="${l1:-0}"; l2="${l2:-0}"; l3="${l3:-0}"
  r1="${r1:-0}"; r2="${r2:-0}"; r3="${r3:-0}"
  if [[ "$l1" -gt "$r1" ]]; then return 0; fi
  if [[ "$l1" -lt "$r1" ]]; then return 1; fi
  if [[ "$l2" -gt "$r2" ]]; then return 0; fi
  if [[ "$l2" -lt "$r2" ]]; then return 1; fi
  [[ "$l3" -ge "$r3" ]]
}

check_lane_route_selectors() {
  local route="$1" key="$2" selector sid row found_route
  while IFS= read -r selector; do
    [[ -n "$selector" ]] || continue
    sid="$(lane_sanitize_id "$selector")"
    row="$(jq -c --arg s "$selector" 'map(select(.selector == $s)) | .[0] // null' <<<"$LANE_TABLE_JSON")"
    found_route="$(jq -r 'if . == null then "" else (.route // "") end' <<<"$row")"
    if [[ -z "$found_route" ]]; then
      add_check "lanes.$key.selector.$sid.model" fail true '' "model selector $selector is not present in the runtime model table"
      continue
    fi
    if [[ "$found_route" != "$route" ]]; then
      add_check "lanes.$key.selector.$sid.model" fail true '' "model selector $selector routes through $found_route, not $route"
      continue
    fi
    add_check "lanes.$key.selector.$sid.model" pass true '' "model selector $selector routes through $route"
    if jq -e '(.origins | type == "array") and (.origins | index("pi") != null)' <<<"$row" >/dev/null 2>&1; then
      add_check "lanes.$key.selector.$sid.origin" pass true '' "model selector $selector supports the Pi lane origin"
    else
      add_check "lanes.$key.selector.$sid.origin" fail true '' "model selector $selector is missing the required pi origin in the runtime model table"
    fi
  done < <(jq -r --arg k "$key" '(.lanes[$k] // [])[]' "$CONFIG")
}

check_lane_pi_providers() {
  local selector sid provider present
  while IFS= read -r selector; do
    [[ -n "$selector" ]] || continue
    sid="$(lane_sanitize_id "$selector")"
    provider="${selector%%/*}"
    if [[ -z "$provider" || "$provider" == "$selector" ]]; then
      add_check "lanes.pi.selector.$sid.provider" fail true '' "$selector has no provider prefix before the / separator"
      continue
    fi
    if [[ "$provider" == "anthropic" ]]; then
      add_check "lanes.pi.selector.$sid.provider" fail true '' "$selector is Anthropic-routed and must not be required as a Pi provider"
      continue
    fi
    present="$(jq -r --arg p "$provider" '(.providers.pi // []) | any(. == $p)' "$CONFIG")"
    if [[ "$present" == true ]]; then
      add_check "lanes.pi.selector.$sid.provider" pass true '' "required Pi provider $provider for $selector is declared in providers.pi"
    else
      add_check "lanes.pi.selector.$sid.provider" fail true '' "required Pi provider $provider for $selector is missing from providers.pi"
    fi
  done < <(jq -r '(.lanes.pi // [])[]' "$CONFIG")
}

check_lane_pi_settings() {
  local root="$1" settings_path settings_key resolved_settings settings_dir entry candidate found=0
  settings_path="$(jq -r '.lanes.pi.settingsPath // empty' "$CATALOG")"
  settings_key="$(jq -r '.lanes.pi.packagesKey // "packages"' "$CATALOG")"
  resolved_settings="$(expand_home "$settings_path")"
  if [[ ! -f "$resolved_settings" ]] || ! jq -e . "$resolved_settings" >/dev/null 2>&1; then
    add_check lanes.pi.settings fail true '' "$settings_path is missing or invalid"
    return
  fi
  settings_dir="$(dirname "$resolved_settings")"
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    case "$entry" in
      npm:*) continue ;;
      '~') candidate="$(expand_home "$entry")" ;;
      '~/'*) candidate="$(expand_home "$entry")" ;;
      /*) candidate="$entry" ;;
      *) candidate="$(cd "$settings_dir" 2>/dev/null && cd "$entry" 2>/dev/null && pwd)" ;;
    esac
    [[ -n "$candidate" ]] || continue
    candidate="$(cd "$candidate" 2>/dev/null && pwd)" || continue
    if [[ "$candidate" == "$root" ]]; then
      found=1
      break
    fi
  done < <(jq -r --arg k "$settings_key" '(.[$k] // [])[]' "$resolved_settings")
  if [[ "$found" -eq 1 ]]; then
    add_check lanes.pi.settings pass true '' "$settings_path loads the runtime package"
  else
    add_check lanes.pi.settings fail true '' "$settings_path does not load the runtime package"
  fi
}

check_lane_claude_executable() {
  local binary min_version dir path resolved is_dup version output found_version='' unsupported=''
  local -a safe=() seen_realpaths=()
  binary="$(jq -r '.lanes.claudeCode.binary // "claude"' "$CATALOG")"
  min_version="$(jq -r '.lanes.claudeCode.minVersion // empty' "$CATALOG")"
  local saved_ifs="$IFS"
  IFS=':'
  local -a path_dirs=($PATH)
  IFS="$saved_ifs"
  for dir in "${path_dirs[@]}"; do
    [[ -n "$dir" ]] || continue
    path="$dir/$binary"
    [[ -x "$path" ]] || continue
    resolved="$(cd "$dir" 2>/dev/null && pwd -P)/$binary"
    [[ -f "$resolved" ]] || continue
    is_dup=0
    for seen in "${seen_realpaths[@]:-}"; do
      [[ "$seen" == "$resolved" ]] && { is_dup=1; break; }
    done
    [[ "$is_dup" -eq 1 ]] && continue
    seen_realpaths+=("$resolved")
    [[ -x "$resolved" ]] || continue
    wrapper_has_permission_bypass "$resolved" && continue
    safe+=("$resolved")
  done
  if [[ "${#safe[@]}" -eq 0 ]]; then
    add_check lanes.claude-code.executable fail true '' 'no eligible Claude Code executable (no known bypass wrapper) was found on PATH'
    add_check lanes.claude-code.version skip true '' 'version check skipped because no eligible executable was found'
    return
  fi
  add_check lanes.claude-code.executable pass true '' "${#safe[@]} eligible Claude Code executable(s) (no known bypass wrapper) found on PATH"

  for resolved in "${safe[@]}"; do
    output="$TMP/lane-claude-version-$(lane_sanitize_id "$resolved")"
    if run_capture 5 "$output" "$resolved" --version; then
      version="$(grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' "$output" | head -n1)"
      [[ -n "$version" ]] || continue
      if version_at_least "$version" "$min_version"; then
        found_version="$version"
        break
      else
        unsupported="$version"
      fi
    fi
  done
  if [[ -n "$found_version" ]]; then
    add_check lanes.claude-code.version pass true '' "Claude Code $found_version satisfies the minimum $min_version"
  elif [[ -n "$unsupported" ]]; then
    add_check lanes.claude-code.version fail true '' "Claude Code $unsupported is older than the required minimum $min_version"
  else
    add_check lanes.claude-code.version fail true '' 'no supported Claude Code executable version could be determined'
  fi
}

LANE_TABLE_JSON=''

check_lanes() {
  local lanes_pi_count lanes_claude_count run_pi=0 run_claude=0
  lanes_pi_count="$(jq -r '(.lanes.pi // []) | length' "$CONFIG")"
  lanes_claude_count="$(jq -r '(.lanes["claude-code"] // []) | length' "$CONFIG")"
  if [[ "$lanes_pi_count" -gt 0 && ( -z "$ONLY" || "$ONLY" == pi ) ]]; then run_pi=1; fi
  if [[ "$lanes_claude_count" -gt 0 && ( -z "$ONLY" || "$ONLY" == claude ) ]]; then run_claude=1; fi
  [[ "$run_pi" -eq 1 || "$run_claude" -eq 1 ]] || return

  local root_cfg root package_file package_path table_entry table_path bun_bin output

  root_cfg="$(jq -r '.lanes.runtime.root // empty' "$CATALOG")"
  root="$(expand_home "$root_cfg")"
  if [[ -z "$root_cfg" || ! -d "$root" ]]; then
    add_check lanes.runtime.dir fail true '' "${root_cfg:-lanes.runtime.root} is missing"
    add_check lanes.runtime.package skip true '' 'runtime package check skipped because the runtime directory is missing'
    add_check lanes.runtime.bun skip true '' 'bun check skipped because the runtime directory is missing'
    add_check lanes.runtime.table skip true '' 'model table check skipped because the runtime directory is missing'
    if [[ "$run_pi" -eq 1 ]]; then
      add_check lanes.pi.settings skip true '' 'Pi settings check skipped because the runtime directory is missing'
      add_check lanes.pi.selectors skip true '' 'Pi lane selector checks skipped because the runtime directory is missing'
    fi
    [[ "$run_claude" -eq 1 ]] && add_check lanes.claude-code.selectors skip true '' 'Claude Code lane selector checks skipped because the runtime directory is missing'
    return
  fi
  root="$(cd "$root" && pwd)"
  add_check lanes.runtime.dir pass true '' "$root_cfg is present"

  package_file="$(jq -r '.lanes.runtime.packageFile // "package.json"' "$CATALOG")"
  package_path="$root/$package_file"
  if [[ ! -f "$package_path" ]] || ! jq -e . "$package_path" >/dev/null 2>&1; then
    add_check lanes.runtime.package fail true '' "$package_file is missing or invalid in the runtime package"
  elif ! jq -e '(.pi.extensions // []) | index("extensions/lanes.ts") != null' "$package_path" >/dev/null 2>&1; then
    add_check lanes.runtime.package fail true '' "$package_file does not declare extensions/lanes.ts under .pi.extensions"
  else
    add_check lanes.runtime.package pass true '' "$package_file is present, valid, and declares extensions/lanes.ts"
  fi

  local required_file required_sid required_path
  while IFS= read -r required_file; do
    [[ -n "$required_file" ]] || continue
    required_sid="$(lane_sanitize_id "$required_file")"
    required_path="$root/$required_file"
    if [[ -f "$required_path" ]]; then
      add_check "lanes.runtime.file.$required_sid" pass true '' "$required_file is present in the runtime package"
    else
      add_check "lanes.runtime.file.$required_sid" fail true '' "$required_file is missing in the runtime package"
    fi
  done < <(jq -r '(.lanes.runtime.requiredFiles // [])[]' "$CATALOG")

  table_entry="$(jq -r '.lanes.runtime.tableEntry // "src/table.ts"' "$CATALOG")"
  table_path="$root/$table_entry"
  bun_bin="$(command -v bun 2>/dev/null || true)"
  if [[ -z "$bun_bin" ]]; then
    add_check lanes.runtime.bun fail true '' 'bun is required to read the runtime model table'
    add_check lanes.runtime.table skip true '' 'model table check skipped because bun is unavailable'
  elif [[ ! -f "$table_path" ]]; then
    add_check lanes.runtime.bun pass true '' "bun resolves to $bun_bin"
    add_check lanes.runtime.table fail true '' "$table_entry is missing in the runtime package"
  else
    add_check lanes.runtime.bun pass true '' "bun resolves to $bun_bin"
    # This parser only ever reads the runtime table as text (readFileSync + regex/
    # brace-depth scanning). It must never import(), require(), or eval() the
    # runtime file, since that file is untrusted input, not trusted code.
    cat >"$TMP/lane-table.mjs" <<'JS'
import { readFileSync } from "node:fs";

function fail(reason) {
  process.stderr.write(`table-invalid: ${reason}\n`);
  process.exit(1);
}

function findMatching(text, openIdx, openChar, closeChar) {
  let depth = 0;
  let inString = null;
  for (let i = openIdx; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (ch === "\\") { i++; continue; }
      if (ch === inString) inString = null;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === "`") { inString = ch; continue; }
    if (ch === openChar) depth++;
    else if (ch === closeChar) {
      depth--;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function splitTopLevelObjects(text) {
  const entries = [];
  let inString = null;
  let depth = 0;
  let start = -1;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (ch === "\\") { i++; continue; }
      if (ch === inString) inString = null;
      continue;
    }
    if (ch === '"' || ch === "'" || ch === "`") { inString = ch; continue; }
    if (ch === "{") {
      if (depth === 0) start = i;
      depth++;
    } else if (ch === "}") {
      depth--;
      if (depth === 0 && start !== -1) {
        entries.push(text.slice(start, i + 1));
        start = -1;
      }
    }
  }
  if (depth !== 0) fail("unbalanced braces in MODEL_TABLE array");
  return entries;
}

function extractField(entryText, name) {
  const re = new RegExp(`(?:^|[,{\\s])${name}\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"`);
  const m = re.exec(entryText);
  return m ? m[1] : null;
}

function extractQuotedStrings(text) {
  const out = [];
  const re = /"((?:[^"\\]|\\.)*)"/g;
  let m;
  while ((m = re.exec(text)) !== null) out.push(m[1]);
  return out;
}

function extractSpreadIdentifiers(text) {
  const out = [];
  const re = /\.\.\.([A-Za-z_$][A-Za-z0-9_$]*)/g;
  let m;
  while ((m = re.exec(text)) !== null) out.push(m[1]);
  return out;
}

function resolveTopLevelArrayConst(source, identifier) {
  const declRe = new RegExp(
    `(?:^|\\n)\\s*(?:export\\s+)?const\\s+${identifier}\\b[^=\\n]*=\\s*\\[`,
  );
  const m = declRe.exec(source);
  if (!m) fail(`spread reference ${identifier} has no resolvable top-level const array`);
  const openIdx = m.index + m[0].length - 1;
  const closeIdx = findMatching(source, openIdx, "[", "]");
  if (closeIdx === -1) fail(`spread reference ${identifier} array is unterminated`);
  const arrayBody = source.slice(openIdx + 1, closeIdx);
  if (/\.\.\./.test(arrayBody)) {
    fail(`spread reference ${identifier} resolves to a nested spread, which is unsupported`);
  }
  return extractQuotedStrings(arrayBody);
}

function extractOrigins(entryText, source) {
  const m = /origins\s*:\s*\[([^\]]*)\]/.exec(entryText);
  if (!m) return null;
  const body = m[1];
  const origins = new Set(extractQuotedStrings(body));
  for (const identifier of extractSpreadIdentifiers(body)) {
    for (const value of resolveTopLevelArrayConst(source, identifier)) origins.add(value);
  }
  return [...origins];
}

function main() {
  const tablePath = process.argv[2];
  if (!tablePath) fail("missing table path");
  let source;
  try {
    source = readFileSync(tablePath, "utf8");
  } catch {
    fail("runtime model table could not be read");
  }

  const declRe = /(?:^|\n)\s*export\s+const\s+MODEL_TABLE\b[^=\n]*=\s*\[/;
  const declMatch = declRe.exec(source);
  if (!declMatch) fail("MODEL_TABLE declaration was not found");

  const openIdx = declMatch.index + declMatch[0].length - 1;
  const closeIdx = findMatching(source, openIdx, "[", "]");
  if (closeIdx === -1) fail("MODEL_TABLE array is unterminated");

  const arrayBody = source.slice(openIdx + 1, closeIdx);
  const entries = splitTopLevelObjects(arrayBody);
  if (entries.length === 0) fail("MODEL_TABLE has no rows");

  const seenSelectors = new Set();
  const rows = entries.map((entryText) => {
    const selector = extractField(entryText, "selector");
    const route = extractField(entryText, "route");
    const origins = extractOrigins(entryText, source);
    if (!selector) fail("a MODEL_TABLE row is missing a quoted selector");
    if (!route) fail("a MODEL_TABLE row is missing a quoted route");
    if (!origins) fail("a MODEL_TABLE row is missing an origins array");
    if (seenSelectors.has(selector)) fail(`duplicate MODEL_TABLE selector: ${selector}`);
    seenSelectors.add(selector);
    return { selector, route, origins };
  });

  process.stdout.write(JSON.stringify(rows));
}

main();
JS
    output="$TMP/lane-table.json"
    if run_capture 10 "$output" "$bun_bin" --no-install "$TMP/lane-table.mjs" "$table_path" \
      && LANE_TABLE_JSON="$(jq -c '.' "$output" 2>/dev/null)" \
      && jq -e 'type == "array" and all(.[]; (.selector | type == "string" and length > 0) and (.route | type == "string" and length > 0) and (.origins | type == "array" and all(.[]; type == "string"))) and ((map(.selector) | length) == (map(.selector) | unique | length))' <<<"$LANE_TABLE_JSON" >/dev/null 2>&1; then
      output="$(jq -r 'length' <<<"$LANE_TABLE_JSON")"
      add_check lanes.runtime.table pass true '' "runtime model table loaded $output model(s) via bun"
    else
      LANE_TABLE_JSON=''
      add_check lanes.runtime.table fail true '' 'runtime model table could not be read or is invalid'
    fi
  fi

  if [[ -z "$LANE_TABLE_JSON" ]]; then
    [[ "$run_pi" -eq 1 ]] && add_check lanes.pi.selectors skip true '' 'Pi lane selector checks skipped because the runtime model table is unavailable'
    [[ "$run_claude" -eq 1 ]] && add_check lanes.claude-code.selectors skip true '' 'Claude Code lane selector checks skipped because the runtime model table is unavailable'
  else
    [[ "$run_pi" -eq 1 ]] && check_lane_route_selectors pi pi
    [[ "$run_claude" -eq 1 ]] && check_lane_route_selectors claude-code "claude-code"
  fi

  if [[ "$run_pi" -eq 1 ]]; then
    check_lane_pi_settings "$root"
    check_lane_pi_providers
  fi
  [[ "$run_claude" -eq 1 ]] && check_lane_claude_executable
}

check_online() {
  local harness binary resolved output rc text
  [[ "$ONLINE" -eq 1 ]] || return
  while IFS= read -r harness; do
    if ! jq -e --arg h "$harness" '.harnesses[$h].onlineProbe | type == "array" and length > 0' "$CATALOG" >/dev/null 2>&1; then
      add_check "online.$harness.auth" unknown true "$harness" 'no documented noninteractive authentication probe is supported'
      continue
    fi
    binary="$(jq -r --arg h "$harness" '.harnesses[$h].binary' "$CATALOG")"
    resolved="$(command -v "$binary" 2>/dev/null || true)"
    if [[ -z "$resolved" ]]; then
      add_check "online.$harness.auth" unknown true "$harness" 'authentication probe is unavailable because the executable is missing'
      continue
    fi
    PROBE_ARGS=()
    while IFS= read -r text; do PROBE_ARGS+=("$text"); done < <(jq -r --arg h "$harness" '.harnesses[$h].onlineProbe[]' "$CATALOG")
    output="$TMP/online-$harness"
    if run_capture 7 "$output" "$resolved" "${PROBE_ARGS[@]}"; then
      if grep -Eqi 'could not determine if authenticated' "$output"; then
        add_check "online.$harness.auth" unknown true "$harness" 'authentication status response could not be normalized'
      elif grep -Eqi 'not[ -]?(logged|authenticated)|loggedIn[^[:alnum:]]*false|authenticated[^[:alnum:]]*false|0 credentials|no credentials' "$output"; then
        add_check "online.$harness.auth" fail true "$harness" 'authentication probe reports no active credential'
      elif grep -Eqi '(^|[^[:alnum:]])(logged[ -]?in|authenticated[^[:alnum:]]*true|loggedIn[^[:alnum:]]*true|[1-9][0-9]* credentials?)' "$output"; then
        add_check "online.$harness.auth" pass true "$harness" 'authentication probe reports configured credentials'
      else
        add_check "online.$harness.auth" unknown true "$harness" 'authentication status response could not be normalized'
      fi
    else
      rc=$?
      if [[ "$rc" -eq 124 ]]; then
        add_check "online.$harness.auth" unknown true "$harness" 'authentication status probe timed out'
      else
        add_check "online.$harness.auth" fail true "$harness" 'authentication status probe reports not logged in'
      fi
    fi
  done < <(selected_harnesses)
}

check_skill_links() {
  local manifest harness skill discovery root target canonical
  manifest="$(jq -r '.skills.manifest // empty' "$CATALOG")"
  [[ -n "$manifest" ]] || return
  manifest="$(expand_home "$manifest")"
  if [[ ! -f "$manifest" ]] || ! jq -e '(.harnesses | type == "object") and (.skills | type == "object")' "$manifest" >/dev/null 2>&1; then
    add_check skills.manifest warn false '' "$manifest is unavailable or invalid"
    return
  fi
  canonical="$(jq -r '.canonical_root' "$manifest")"
  canonical="$(expand_home "$canonical")"
  while IFS=$'\t' read -r harness skill; do
    [[ -n "$ONLY" && "$harness" != "$ONLY" ]] && continue
    if ! jq -e --arg h "$harness" '.harnesses | index($h) != null' "$CONFIG" >/dev/null 2>&1; then continue; fi
    discovery="$(jq -r --arg h "$harness" '.harnesses[$h].discovery' "$manifest")"
    root="$(jq -r --arg h "$harness" '.harnesses[$h].skills_root' "$manifest")"
    root="$(expand_home "$root")"
    target="$root/$skill"
    if [[ "$discovery" == canonical ]]; then
      target="$canonical/$skill"
      if [[ -d "$target" ]]; then
        add_check "skill.$harness.$skill" pass false "$harness" "$skill is present in the canonical skill root"
      else
        add_check "skill.$harness.$skill" fail false "$harness" "$target is missing"
      fi
    elif [[ -L "$target" && -d "$target" ]]; then
      add_check "skill.$harness.$skill" pass false "$harness" "$target is a valid skill link"
    elif [[ -L "$target" ]]; then
      add_check "skill.$harness.$skill" fail false "$harness" "$target is a broken skill link"
    else
      add_check "skill.$harness.$skill" fail false "$harness" "$target is not a managed skill link"
    fi
  done < <(jq -r '.skills | to_entries[] | .key as $skill | .value[] | [.,$skill] | @tsv' "$manifest")
}

check_git_source() {
  local git_bin output count ahead behind
  git_bin="$(command -v git 2>/dev/null || true)"
  if [[ -z "$git_bin" || -z "$SOURCE" ]] || ! "$git_bin" -C "$SOURCE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return
  fi
  output="$TMP/git-status"
  if run_capture 8 "$output" "$git_bin" -C "$SOURCE" status --porcelain --untracked-files=normal; then
    count="$(awk 'NF {n++} END {print n+0}' "$output")"
    if [[ "$count" -eq 0 ]]; then
      add_check source.git.clean pass false '' 'source Git checkout is clean'
    else
      add_check source.git.clean warn false '' "source Git checkout has $count dirty item(s)"
    fi
  else
    add_check source.git.clean unknown false '' 'source Git checkout cleanliness could not be checked'
  fi
  output="$TMP/git-upstream"
  if ! "$git_bin" -C "$SOURCE" rev-parse --verify '@{upstream}' >/dev/null 2>&1; then
    add_check source.git.upstream unknown false '' 'source Git checkout has no available upstream'
  elif run_capture 8 "$output" "$git_bin" -C "$SOURCE" rev-list --left-right --count 'HEAD...@{upstream}'; then
    read -r ahead behind <"$output"
    ahead="${ahead:-0}"
    behind="${behind:-0}"
    if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
      add_check source.git.upstream pass false '' 'source Git checkout matches upstream'
    else
      add_check source.git.upstream warn false '' "source Git checkout is $ahead ahead and $behind behind upstream"
    fi
  else
    add_check source.git.upstream unknown false '' 'source Git checkout upstream state could not be checked'
  fi
}

check_drift() {
  local chezmoi_bin output count path
  chezmoi_bin="$(command -v chezmoi 2>/dev/null || true)"
  if [[ -z "$chezmoi_bin" || -z "$SOURCE" || ! -f "$SOURCE/scripts/check-agent-config-sync.sh" ]]; then
    add_check drift.summary unknown false '' 'canonical/live drift check is unavailable'
    return
  fi
  DRIFT_PATHS=()
  while IFS= read -r path; do DRIFT_PATHS+=("$(expand_home "$path")"); done < <(jq -r '.drift.paths[]' "$CATALOG")
  output="$TMP/drift"
  if run_capture 10 "$output" "$chezmoi_bin" --source "$SOURCE" status --no-pager -- "${DRIFT_PATHS[@]}"; then
    count="$(awk 'NF {n++} END {print n+0}' "$output")"
    if [[ "$count" -eq 0 ]]; then
      add_check drift.summary pass false '' 'scoped canonical/live targets have no drift'
    else
      add_check drift.summary warn false '' "$count scoped canonical/live target(s) differ"
    fi
  else
    add_check drift.summary unknown false '' 'scoped canonical/live drift check could not run'
  fi
}

emit_output() {
  local forced_exit="${1:-}" counts failures exit_code color=0 line status icon ansi reset message harness display footer value
  counts="$(jq -s 'reduce .[] as $c ({pass:0,warn:0,fail:0,unknown:0,skip:0,info:0}; .[$c.status] += 1)' "$RESULTS")"
  failures="$(jq -s '[.[] | select(.required == true and .status == "fail")] | length' "$RESULTS")"
  if [[ -n "$forced_exit" ]]; then exit_code="$forced_exit"; elif [[ "$failures" -gt 0 ]]; then exit_code=1; else exit_code=0; fi
  if [[ "$JSON_MODE" -eq 1 ]]; then
    jq -s --argjson summary "$counts" --argjson exitCode "$exit_code" '{version:1,checks:.,summary:$summary,exitCode:$exitCode}' "$RESULTS"
    return "$exit_code"
  fi
  if [[ -z "${NO_COLOR:-}" && "$COLOR_MODE" == always ]]; then color=1
  elif [[ -z "${NO_COLOR:-}" && "$COLOR_MODE" == auto && -t 1 ]]; then color=1
  fi
  while IFS= read -r line; do
    status="$(jq -r '.status' <<<"$line")"
    [[ "$status" == skip && "$VERBOSE" -ne 1 ]] && continue
    harness="$(jq -r '.harness // empty' <<<"$line")"
    message="$(jq -r '.message' <<<"$line")"
    if [[ -n "$harness" ]]; then
      display="$(jq -r --arg h "$harness" '.harnesses[$h].displayName // $h' "$CATALOG" 2>/dev/null || printf '%s' "$harness")"
      message="$display: $message"
    fi
    case "$status" in
      pass) icon='✓'; ansi='32' ;;
      warn) icon='!'; ansi='33' ;;
      fail) icon='✗'; ansi='31' ;;
      unknown) icon='?'; ansi='36' ;;
      skip) icon='–'; ansi='2' ;;
      info) icon='·'; ansi='34' ;;
    esac
    if [[ "$ASCII" -eq 1 ]]; then
      case "$status" in pass) icon='[+]' ;; warn) icon='[!]' ;; fail) icon='[x]' ;; unknown) icon='[?]' ;; skip) icon='[-]' ;; info) icon='[i]' ;; esac
    fi
    if [[ "$color" -eq 1 ]]; then reset=$'\033[0m'; printf '\033[%sm%s%s %s\n' "$ansi" "$icon" "$reset" "$message"
    else printf '%s %s\n' "$icon" "$message"
    fi
  done <"$RESULTS"
  footer=''
  for status in pass warn fail unknown; do
    value="$(jq -r --arg status "$status" '.[$status]' <<<"$counts")"
    [[ "$value" -eq 0 ]] && continue
    case "$status" in pass) message='healthy' ;; warn) message='warnings' ;; fail) message='problems' ;; unknown) message='unknown' ;; esac
    [[ -n "$footer" ]] && footer="$footer · "
    footer="$footer$value $message"
  done
  if [[ "$VERBOSE" -eq 1 ]]; then
    value="$(jq -r '.skip' <<<"$counts")"
    if [[ "$value" -gt 0 ]]; then [[ -n "$footer" ]] && footer="$footer · "; footer="$footer$value skipped"; fi
  fi
  printf '%s\n' "$footer"
  return "$exit_code"
}

if [[ ! -f "$CATALOG" ]]; then
  emit_early_error catalog.missing "doctor catalog is missing: $CATALOG"
fi
if ! validate_catalog; then
  emit_early_error catalog.invalid "doctor catalog is invalid: $CATALOG"
fi
if [[ ! -f "$CONFIG" ]]; then
  add_check requirements.missing fail true '' "requirements file is missing: $CONFIG; create it with {\"version\":1,\"harnesses\":[\"pi\"],\"providers\":{\"pi\":[\"anthropic\"]},\"mcp\":{\"pi\":[\"context7\"]}}"
  emit_output 2
  exit 2
fi
if ! validate_requirements; then
  emit_early_error requirements.invalid "requirements file is invalid: $CONFIG"
fi
if [[ -n "$ONLY" ]] && ! jq -e --arg only "$ONLY" '.harnesses | index($only) != null' "$CONFIG" >/dev/null 2>&1; then
  usage_error "harness is not required on this machine: $ONLY"
fi

add_check catalog.valid pass true '' 'shared catalog schema v1 is valid'
add_check requirements.valid pass true '' 'machine-local requirements schema v1 is valid'
check_bootstrap
VERSION_ARGS=()
while IFS= read -r HARNESS; do check_harness "$HARNESS"; done < <(selected_harnesses)
check_providers
check_mcp
check_lanes
check_online
check_skill_links
check_git_source
check_drift
emit_output
exit $?

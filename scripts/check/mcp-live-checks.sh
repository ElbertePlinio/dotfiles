check_mcp_registry_and_config() {
  need "$MCP_REGISTRY"
  need "$OMP_MCP"
  [[ -f "$MCP_REGISTRY" && -f "$OMP_MCP" ]] || return

  if jq -e . "$MCP_REGISTRY" >/dev/null 2>&1; then
    pass 'MCP target registry JSON valid'
  else
    err "MCP target registry is not valid JSON: $MCP_REGISTRY"
    return
  fi
  if jq -e . "$OMP_MCP" >/dev/null 2>&1; then
    pass 'OMP MCP config JSON valid'
  else
    err "OMP MCP config is not valid JSON: $OMP_MCP"
    return
  fi

  if jq -e '
    def unique_nonempty_strings:
      type == "array"
      and all(.[]; type == "string" and length > 0)
      and (length == (unique | length));

    type == "object"
    and keys == ["omp", "version"]
    and .version == 1
    and (.omp
      | type == "object"
      and keys == ["externallyImported", "native", "pluginRetained", "suppressed"]
      and all(
        .native,
        .externallyImported,
        .pluginRetained,
        .suppressed;
        unique_nonempty_strings)
      and all(.native[], .externallyImported[]; contains(":") | not))
  ' "$MCP_REGISTRY" >/dev/null; then
    pass 'MCP target registry shape valid'
  else
    err 'MCP target registry shape invalid'
  fi

  if jq -e '
    def optional_type($key; $kind):
      (has($key) | not) or (getpath([$key]) | type == $kind);
    def string_map:
      type == "object" and all(to_entries[]; .value | type == "string");
    def string_array:
      type == "array" and all(.[]; type == "string");
    def unique_nonempty_strings:
      string_array
      and all(.[]; length > 0)
      and (length == (unique | length));
    def allowed_keys($allowed):
      ((keys - $allowed) | length == 0);
    def shared_fields:
      optional_type("enabled"; "boolean")
      and ((has("timeout") | not) or (.timeout | type == "number" and . >= 0));
    def stdio_server:
      type == "object"
      and allowed_keys(["args", "command", "cwd", "enabled", "env", "timeout", "type"])
      and ((has("type") | not) or .type == "stdio")
      and (.command | type == "string" and length > 0)
      and (has("url") | not)
      and ((has("args") | not) or (.args | string_array))
      and ((has("env") | not) or (.env | string_map))
      and optional_type("cwd"; "string")
      and shared_fields;
    def remote_server:
      type == "object"
      and allowed_keys(["enabled", "headers", "oauth", "timeout", "type", "url"])
      and (.type == "http" or .type == "sse")
      and (.url | type == "string" and length > 0)
      and (has("command") | not)
      and ((has("headers") | not) or (.headers | string_map))
      and shared_fields;
    def valid_server:
      stdio_server or remote_server;
    def optional_unique_names($key):
      (has($key) | not) or (getpath([$key]) | unique_nonempty_strings);

    type == "object"
    and ((keys - ["$schema", "disabledServers", "enabledServers", "mcpServers"]) | length == 0)
    and optional_type("$schema"; "string")
    and (.mcpServers | type == "object")
    and all(.mcpServers | keys[]; test("^[a-zA-Z0-9_.-]{1,100}$"))
    and all(.mcpServers[]; valid_server)
    and optional_unique_names("disabledServers")
    and optional_unique_names("enabledServers")
  ' "$OMP_MCP" >/dev/null; then
    pass 'OMP MCP documented schema subset valid'
  else
    err 'OMP MCP has an invalid top-level key or transport shape'
  fi

  if jq -e '
    [.. | objects | to_entries[]
      | select((.key | ascii_downcase) == "auth")]
    | length == 0
  ' "$OMP_MCP" >/dev/null; then
    pass 'OMP MCP has no auth blocks'
  else
    err 'OMP MCP must not contain auth blocks'
  fi

  if jq -e '
    ([paths as $path
      | select(
          ($path | length) > 0
          and ($path[-1] | type) == "string"
          and ($path[-1] | ascii_downcase) == "oauth"
        )
      | $path] == [["mcpServers", "stripe", "oauth"]])
    and (.mcpServers.stripe.oauth
      | type == "object"
      and keys == ["callbackPath", "callbackPort", "clientId", "redirectUri"]
      and .clientId == "oacli_UsBlZ6jiucaNw9"
      and (.clientId | test("^oacli_[A-Za-z0-9]+$"))
      and .redirectUri == "http://127.0.0.1:3000/callback"
      and .callbackPort == 3000
      and .callbackPath == "/callback")
  ' "$OMP_MCP" >/dev/null; then
    pass 'OMP MCP OAuth is restricted to the approved Stripe public client'
  else
    err 'OMP MCP OAuth must be exactly the approved Stripe public client configuration'
  fi

  if jq -e '
    [.. | objects | to_entries[]
      | select((.key | ascii_downcase) == "clientsecret")]
    | length == 0
  ' "$OMP_MCP" >/dev/null; then
    pass 'OMP MCP has no clientSecret fields'
  else
    err 'OMP MCP must not contain clientSecret fields'
  fi

  if jq -e '
    [.. | objects | to_entries[]
      | select((.key | ascii_downcase) == "authorization")]
    | length == 0
  ' "$OMP_MCP" >/dev/null; then
    pass 'OMP MCP has no literal Authorization header'
  else
    err 'OMP MCP must not contain a literal Authorization header'
  fi

  if validate_omp_mcp_credentials "$OMP_MCP"; then
    pass 'OMP MCP has no suspicious literals and only the approved Sentry credential command'
  else
    err 'OMP MCP contains a suspicious literal or unapproved credential command'
  fi

  local credential_probe
  credential_probe="$(mktemp "${TMPDIR:-/tmp}/agent-config-sync-mcp-probe.XXXXXX")"
  if jq '.mcpServers.sentry.env.SENTRY_ACCESS_TOKEN = "!cat /tmp/unapproved-token"' \
    "$OMP_MCP" >"$credential_probe"; then
    if validate_omp_mcp_credentials "$credential_probe"; then
      err 'OMP MCP negative probe accepted an unapproved credential command'
    else
      pass 'OMP MCP credential validator rejects a mutated unapproved command'
    fi
  else
    err 'OMP MCP negative probe could not create the mutated config'
  fi
  rm -f "$credential_probe"

  if jq -e '
    def credential_key:
      ascii_downcase
      | test("(^|[_-])(token|secret|api[_-]?key|access[_-]?key)($|[_-])");
    ([.. | objects | to_entries[]
      | select(
          (.key | credential_key)
          and (.value | type == "string")
          and (.value | length > 0)
          and ((.value | startswith("!")) | not)
        )]
      | length == 0)
    and
    ([.. | strings
      | select(test(
          "^(bearer[[:space:]]+|sk_(live|test)_|sk-(proj-)?|gh[pousr]_|xox[baprs]-|eyJ[A-Za-z0-9_-]+\\\\.)";
          "i"
        ))]
      | length == 0)
  ' "$OMP_MCP" >/dev/null; then
    pass 'OMP MCP has no suspicious literal credential values'
  else
    err 'OMP MCP contains a suspicious literal token, secret, or key value'
  fi
  if jq -e -n --slurpfile registry "$MCP_REGISTRY" --slurpfile config "$OMP_MCP" '
    ($registry[0].omp.native | sort)
    ==
    ($config[0].mcpServers | keys | sort)
  ' >/dev/null; then
    pass 'registry native OMP names match mcpServers'
  else
    err 'registry native OMP names do not match mcpServers'
  fi

  if jq -e -n --slurpfile registry "$MCP_REGISTRY" --slurpfile config "$OMP_MCP" '
    ($registry[0].omp.suppressed | sort)
    ==
    ($config[0].disabledServers | sort)
  ' >/dev/null; then
    pass 'registry suppressed names match disabledServers'
  else
    err 'registry suppressed names do not match disabledServers'
  fi
}

check_live_portable_links() {
  local skill harness root link target expected_prefix canon
  canon_root="$(expand_home "$(jq -r '.canonical_root' "$MANIFEST")")"
  while IFS=$'\t' read -r skill harness; do
    local discovery
    discovery="$(jq -r --arg h "$harness" '.harnesses[$h].discovery' "$MANIFEST")"
    if [[ "$discovery" == "canonical" ]]; then
      continue
    fi
    root="$(expand_home "$(jq -r --arg h "$harness" '.harnesses[$h].skills_root' "$MANIFEST")")"
    expected_prefix="$(jq -r --arg h "$harness" '.harnesses[$h].relative_prefix' "$MANIFEST")"
    link="${root}/${skill}"
    canon="${canon_root}/${skill}"

    if [[ ! -e "$link" && ! -L "$link" ]]; then
      if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
        pass "live link not yet applied: $harness/$skill"
      else
        err "live link missing: $link"
      fi
      continue
    fi

    if [[ -L "$link" ]]; then
      target="$(readlink "$link")"
      if [[ "$target" != "${expected_prefix}/${skill}" ]]; then
        err "live link $link expected '${expected_prefix}/${skill}' got '$target'"
        continue
      fi
      if [[ ! -e "$link" ]]; then
        err "live link broken: $link -> $target"
        continue
      fi
      pass "live link ok: $harness/$skill"
      continue
    fi

    if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
      if [[ -d "$canon" && -d "$link" ]] && dirs_identical "$link" "$canon"; then
        pass "live path identical to canonical (migratable): $harness/$skill"
      elif managed_directory_unchanged "$link"; then
        pass "live managed path unchanged (migratable): $harness/$skill"
      else
        err "live non-symlink path has unmanaged or modified content: $link"
      fi
      continue
    fi

    err "live path is not a symlink: $link"
  done < <(jq -r '.skills | to_entries[] | .key as $s | .value[] | "\($s)\t\(.)"' "$MANIFEST")
}

check_live_primary_global_targets() {
  local target_root="${1:-$HOME}"
  local -a targets=(
    "${target_root}/.claude/CLAUDE.md"
    "${target_root}/.claude/agents/final-reviewer.md"
    "${target_root}/.claude/agents/final-reviewer-high.md"
    "${target_root}/.claude/settings.json"
    "${target_root}/.claude/skills"
    "${target_root}/.zshrc"
    "${target_root}/.bashrc"
  )

  if chezmoi "${SRC[@]}" --destination "$target_root" verify "${targets[@]}" >/dev/null 2>&1; then
    pass 'live global Claude policy, settings, rules, skills, and shell targets match managed state'
  else
    err 'live global Claude policy, settings, rules, skills, or shell target differs from managed state'
  fi
}





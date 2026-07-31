check_doctor_sources() {
  local doctor="$ROOT/scripts/agent-doctor.sh"
  local doctor_tests="$ROOT/scripts/check-agent-doctor.sh"
  local catalog="$ROOT/dot_agents/doctor-targets.json"

  need "$doctor"
  need "$doctor_tests"
  need "$catalog"
  if [[ -f "$catalog" ]] && jq -e '
    .version == 1
    and (.bootstrap | type == "array")
    and (.harnesses | type == "object" and length > 0)
    and all(.harnesses[];
      (.displayName | type == "string" and length > 0)
      and (.binary | type == "string" and length > 0)
      and (.versionArgs | type == "array")
      and (.configPaths | type == "array"))
  ' "$catalog" >/dev/null 2>&1; then
    pass 'doctor catalog JSON and source invariants valid'
  else
    err 'doctor catalog JSON or source invariants invalid'
  fi
  if [[ -f "$doctor" ]] && bash -n "$doctor" \
    && [[ -f "$doctor_tests" ]] && bash -n "$doctor_tests"; then
    pass 'doctor scripts have valid Bash syntax'
  else
    err 'doctor script Bash syntax invalid'
  fi
  if [[ -f "$doctor" ]] && bash "$doctor" --help >/dev/null; then
    pass 'doctor help smoke test passes'
  else
    err 'doctor help smoke test failed'
  fi
}

check_manifest_and_sources() {
  need "$MANIFEST"
  local portable_policy="$ROOT/scripts/check/portable-skill-policy.py"
  need "$portable_policy"
  if python3 "$portable_policy" "$ROOT" "$MANIFEST" >/dev/null; then
    pass 'portable skill source policy valid'
  else
    err 'portable skill source policy invalid'
  fi

  local mutation_root="$TMP/portable-policy-mutation"
  rm -rf "$mutation_root"
  mkdir -p "$mutation_root/.chezmoitemplates" "$mutation_root/dot_agents"
  cp -R "$ROOT/dot_agents/skills" "$mutation_root/dot_agents/skills"
  cp "$ROOT/.chezmoitemplates/agents-shared.md" "$mutation_root/.chezmoitemplates/agents-shared.md"
  cp "$MANIFEST" "$mutation_root/dot_agents/skill-targets.json"
  jq 'del(.skills["plan-issue"])' "$MANIFEST" >"$mutation_root/missing.json"
  if ! python3 "$portable_policy" "$mutation_root" "$mutation_root/missing.json" >/dev/null 2>&1; then
    pass 'portable skill policy rejects missing plan-issue registry entry'
  else
    err 'portable skill policy accepted missing plan-issue registry entry'
  fi
  jq 'del(.skills["ship-pr"])' "$MANIFEST" >"$mutation_root/missing.json"
  if ! python3 "$portable_policy" "$mutation_root" "$mutation_root/missing.json" >/dev/null 2>&1; then
    pass 'portable skill policy rejects missing ship-pr registry entry'
  else
    err 'portable skill policy accepted missing ship-pr registry entry'
  fi
  local protected_skill
  for protected_skill in diagnosing-bugs flutter-bloc flutter-widget; do
    jq --arg skill "$protected_skill" 'del(.skills[$skill])' "$MANIFEST" >"$mutation_root/missing.json"
    if ! python3 "$portable_policy" "$mutation_root" "$mutation_root/missing.json" >/dev/null 2>&1; then
      pass "portable skill policy rejects missing $protected_skill registry entry"
    else
      err "portable skill policy accepted missing $protected_skill registry entry"
    fi
  done
  printf '\nUse `%s` for this workflow.\n' 'missing-workflow' >>"$mutation_root/.chezmoitemplates/agents-shared.md"
  if ! python3 "$portable_policy" "$mutation_root" "$MANIFEST" >/dev/null 2>&1; then
    pass 'portable skill policy rejects shared-policy skill without canonical source'
  else
    err 'portable skill policy accepted shared-policy skill without canonical source'
  fi
  cp "$ROOT/.chezmoitemplates/agents-shared.md" "$mutation_root/.chezmoitemplates/agents-shared.md"
  mkdir -p "$mutation_root/dot_codex/skills/duplicate"
  cp "$ROOT/dot_agents/skills/ship-pr/SKILL.md" "$mutation_root/dot_codex/skills/duplicate/private_SKILL.md.tmpl"
  if ! python3 "$portable_policy" "$mutation_root" "$MANIFEST" >/dev/null 2>&1; then
    pass 'portable skill policy rejects attributed duplicate outside the registry source roots'
  else
    err 'portable skill policy accepted attributed duplicate outside the registry source roots'
  fi

  if ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
    err "manifest is not valid JSON: $MANIFEST"
    return
  fi
  pass "manifest JSON valid"

  if jq -e '.harnesses | has("claude-portable") | not' "$MANIFEST" >/dev/null; then
    pass 'manifest has no retired claude-portable harness'
  else
    err 'manifest still defines retired claude-portable harness'
  fi
  if jq -e '.skills | all(.[]; all(.[]; . != "claude-portable"))' "$MANIFEST" >/dev/null; then
    pass 'manifest skill targets exclude retired claude-portable harness'
  else
    err 'manifest skill targets still contain retired claude-portable harness'
  fi

  local skill harness src_root rel_prefix expected link_src
  local -a skills

  skills=()
  while IFS= read -r skill; do
    skills+=("$skill")
  done < <(jq -r '.skills | keys[]' "$MANIFEST")
  [[ "${#skills[@]}" -gt 0 ]] || err 'manifest has no skills'

  for skill in "${skills[@]}"; do
    local age="$ROOT/dot_agents/skills/${skill}/encrypted_SKILL.md.age"
    local plain="$ROOT/dot_agents/skills/${skill}/SKILL.md"
    local head name
    if [[ -f "$age" && -f "$plain" ]]; then
      err "duplicate canonical skill sources: $skill"
      continue
    elif [[ -f "$age" ]]; then
      head="$(set +o pipefail; chezmoi "${SRC[@]}" decrypt "$age" 2>/dev/null | head -n 20)"
    elif [[ -f "$plain" ]]; then
      head="$(head -n 20 "$plain")"
    else
      err "canonical skill source missing: $skill"
      continue
    fi
    pass "canonical source exists: $skill"
    if [[ -z "$head" ]]; then
      err "canonical source unreadable: $skill"
      continue
    fi
    if [[ "$head" != ---$'\n'* ]]; then
      err "frontmatter missing for $skill"
      continue
    fi
    name="$(awk 'BEGIN{fm=0} /^---$/{fm++; next} fm==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit}' <<<"$head")"
    if [[ "$name" == "$skill" ]]; then
      pass "frontmatter name=$skill"
    else
      err "frontmatter name mismatch for $skill (got: ${name:-empty})"
    fi
  done

  if [[ -e "$ROOT/dot_claude/skills/context7-mcp" ]]; then
    err 'duplicate Context7 skill source still present: dot_claude'
  else
    pass 'no duplicate Context7 skill directory: dot_claude'
  fi

  while IFS=$'\t' read -r skill harness; do
    [[ -n "$skill" && -n "$harness" ]] || continue
    local discovery
    discovery="$(jq -r --arg h "$harness" '.harnesses[$h].discovery' "$MANIFEST")"
    if [[ "$discovery" == "canonical" ]]; then
      pass "codex/canonical uses $skill without harness symlink"
      continue
    fi
    src_root="$(jq -r --arg h "$harness" '.harnesses[$h].source_root' "$MANIFEST")"
    rel_prefix="$(jq -r --arg h "$harness" '.harnesses[$h].relative_prefix' "$MANIFEST")"
    expected="${rel_prefix}/${skill}"
    link_src="$ROOT/${src_root}/symlink_${skill}"
    if [[ ! -f "$link_src" ]]; then
      err "missing symlink source: $link_src"
      continue
    fi
    local got
    got="$(tr -d '\n' <"$link_src")"
    if [[ "$got" == "$expected" ]]; then
      pass "symlink source $harness/$skill -> $expected"
    else
      err "symlink source $link_src expected '$expected' got '$got'"
    fi
  done < <(jq -r '.skills | to_entries[] | .key as $s | .value[] | "\($s)\t\(.)"' "$MANIFEST")
}

check_legacy_model_skill_absence() {
  local managed_log="$TMP/managed-legacy-model-skills.log"
  if jq -e '.skills | (has("codex") | not) and (has("grok") | not)' \
    "$MANIFEST" >/dev/null 2>&1; then
    pass 'manifest has no legacy codex/grok skill entries'
  else
    err 'manifest still contains a legacy codex/grok skill entry'
  fi

  if chezmoi "${SRC[@]}" managed --include=files,symlinks --path-style=absolute \
    >"$managed_log" \
    && ! grep -Eq '/\.claude/skills/(codex|grok)(/|$)' "$managed_log"; then
    pass 'managed targets have no legacy Claude codex/grok skill paths'
  else
    err 'managed targets contain or could not check legacy Claude codex/grok skill paths'
  fi
}

check_skill_lock_retirements() {
  need "$SKILL_LOCK"
  [[ -f "$SKILL_LOCK" ]] || return 0
  if ! jq -e . "$SKILL_LOCK" >/dev/null 2>&1; then
    err "skill lock is not valid JSON: $SKILL_LOCK"
    return
  fi
  pass 'skill lock JSON valid'

  local retired_json present
  retired_json="$(printf '%s\n' "${RETIRED_SKILL_LOCK_ENTRIES[@]}" | jq -R . | jq -s .)"
  if jq -e --argjson retired "$retired_json" '
    .skills as $skills
    | all($retired[]; . as $skill | $skills | has($skill) | not)
  ' "$SKILL_LOCK" >/dev/null; then
    pass 'skill lock excludes retired caveman entries'
  else
    present="$(jq -r --argjson retired "$retired_json" '
      .skills as $skills
      | $retired
      | map(select(. as $skill | $skills | has($skill)))
      | join(", ")
    ' "$SKILL_LOCK")"
    err "skill lock still contains retired entries: $present"
  fi

  if chezmoi "${SRC[@]}" cat "$HOME/.claude/settings.json" \
    | jq -e '
      ((.enabledPlugins // {}) | has("caveman@caveman") | not)
      and ((.extraKnownMarketplaces // {}) | has("caveman") | not)
    ' >/dev/null; then
    pass 'Claude settings exclude retired Caveman plugin and marketplace'
  else
    err 'Claude settings still contain retired Caveman plugin or marketplace'
  fi
}

validate_omp_mcp_credentials() {
  local config="$1"
  jq -e '
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
    ([paths(strings) as $path
      | select(getpath($path) | startswith("!"))
      | $path] as $commands
      | ($commands == [])
        or (
          $commands == [["mcpServers", "sentry", "env", "SENTRY_ACCESS_TOKEN"]]
          and .mcpServers.sentry.env.SENTRY_ACCESS_TOKEN == "!cat ~/.pickforge-keys/sentry-token"
        ))
    and
    ([.. | strings
      | select(test(
          "^(bearer[[:space:]]+|sk_(live|test)_|sk-(proj-)?|gh[pousr]_|xox[baprs]-|eyJ[A-Za-z0-9_-]+\\\\.)";
          "i"
        ))]
      | length == 0)
  ' "$config" >/dev/null
}

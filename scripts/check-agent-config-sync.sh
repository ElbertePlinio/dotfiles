#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SRC=(--source "$ROOT")
fail=0
MODE=default
REQUIRE_PORTABLE_LINKS=0
STRICT_PREFLIGHT=0
for arg in "$@"; do
  case "$arg" in
    --check-live-migration) MODE=live ;;
    --require-portable-links) REQUIRE_PORTABLE_LINKS=1 ;;
    --strict-preflight) STRICT_PREFLIGHT=1 ;;
  esac
done

pass() { printf 'OK  %s\n' "$*"; }
err()  { printf 'ERR %s\n' "$*" >&2; fail=1; }
need() { [[ -f "$1" ]] || err "missing: $1"; }

expand_home() {
  local p="$1"
  if [[ "$p" == "~/"* ]]; then
    printf '%s\n' "${HOME}/${p#"~/"}"
  elif [[ "$p" == "~" ]]; then
    printf '%s\n' "$HOME"
  else
    printf '%s\n' "$p"
  fi
}

dirs_identical() {
  local a="$1" b="$2"
  [[ -d "$a" && -d "$b" ]] || return 1
  diff -rq "$a" "$b" >/dev/null 2>&1
}

MANIFEST="$ROOT/dot_agents/skill-targets.json"

RUNTIME_SOURCE_PATHS=(
  private_dot_hermes/private_skills/dot_curator_backups
  private_dot_hermes/private_skills/encrypted_empty_dot_usage.json.lock.age
  private_dot_hermes/private_skills/encrypted_private_dot_bundled_manifest.age
  private_dot_hermes/private_skills/encrypted_private_dot_curator_state.age
  private_dot_hermes/private_skills/encrypted_private_dot_usage.json.age
  private_dot_hermes/private_skills/dot_hub/encrypted_private_lock.json.age
  dot_pi/agent/sessions
  dot_pi/agent/encrypted_run-history.jsonl.age
  dot_pi/agent/encrypted_mcp-cache.json.age
  dot_pi/agent/encrypted_mcp-npx-cache.json.age
  dot_pi/agent/encrypted_mcp-onboarding.json.age
  dot_pi/agent/pi-hermes-memory/encrypted_dot_skills-migrated-to-extension-storage.age
  private_dot_factory/private_background-processes.json
  private_dot_factory/private_background-tasks.json
  private_dot_factory/certs/system-certs-cache.json
  private_dot_factory/cli-hints.json
  private_dot_factory/private_host.json
  private_dot_factory/bin/dot_rg-version
)

RUNTIME_IGNORE_PATHS=(
  .hermes/skills/.bundled_manifest
  .hermes/skills/.curator_backups
  .hermes/skills/.curator_state
  .hermes/skills/.usage.json
  .hermes/skills/.usage.json.lock
  .hermes/skills/.hub/lock.json
  .pi/agent/sessions
  .pi/agent/run-history.jsonl
  .pi/agent/mcp-cache.json
  .pi/agent/mcp-npx-cache.json
  .pi/agent/mcp-onboarding.json
  .pi/agent/pi-hermes-memory/.skills-migrated-to-extension-storage
  .factory/background-processes.json
  .factory/background-tasks.json
  .factory/certs/system-certs-cache.json
  .factory/cli-hints.json
  .factory/host.json
  .factory/bin/.rg-version
)

check_runtime_exclusions() {
  local path
  for path in "${RUNTIME_SOURCE_PATHS[@]}"; do
    [[ ! -e "$ROOT/$path" ]] || err "runtime state still tracked: $path"
  done
  for path in "${RUNTIME_IGNORE_PATHS[@]}"; do
    grep -Fxq "$path" "$ROOT/.chezmoiignore" || err "runtime ignore missing: $path"
  done
  [[ "$fail" -eq 0 ]] && pass 'runtime state excluded from chezmoi source'
}

check_manifest_and_sources() {
  need "$MANIFEST"
  if ! jq -e . "$MANIFEST" >/dev/null 2>&1; then
    err "manifest is not valid JSON: $MANIFEST"
    return
  fi
  pass "manifest JSON valid"

  local skill harness src_root rel_prefix expected link_src
  local -a skills

  mapfile -t skills < <(jq -r '.skills | keys[]' "$MANIFEST")
  [[ "${#skills[@]}" -gt 0 ]] || err 'manifest has no skills'

  for skill in "${skills[@]}"; do
    local age="$ROOT/dot_agents/skills/${skill}/encrypted_SKILL.md.age"
    if [[ ! -f "$age" ]]; then
      err "canonical skill source missing: $age"
      continue
    fi
    pass "canonical source exists: $skill"
    local head name
    head="$(set +o pipefail; chezmoi "${SRC[@]}" decrypt "$age" 2>/dev/null | head -n 20)"
    if [[ -z "$head" ]]; then
      err "decrypt failed: $age"
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
    err 'duplicate Claude context7 source still present (expected symlink only)'
  else
    pass 'no duplicate Claude context7 source directory'
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
      if [[ "$REQUIRE_PORTABLE_LINKS" -eq 1 ]]; then
        err "live link missing: $link"
      else
        pass "live link not yet applied: $harness/$skill"
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

    if [[ "$REQUIRE_PORTABLE_LINKS" -eq 1 ]]; then
      err "live path is not a symlink: $link"
      continue
    fi

    if [[ ! -d "$canon" ]]; then
      err "canonical skill missing for comparison: $canon"
      continue
    fi
    if [[ -d "$link" ]] && dirs_identical "$link" "$canon"; then
      pass "live path identical to canonical (migratable): $harness/$skill"
    else
      err "live non-symlink path differs from canonical: $link"
    fi
  done < <(jq -r '.skills | to_entries[] | .key as $s | .value[] | "\($s)\t\(.)"' "$MANIFEST")
}

if [[ "$MODE" == live ]]; then
  if [[ "$STRICT_PREFLIGHT" -eq 1 ]]; then
    echo "== agent-config-sync strict live preflight (read-only) =="
  else
    echo "== agent-config-sync live migration (read-only) =="
  fi
  GROK_LIVE="${HOME}/.grok/AGENTS.md"
  SOUL_LIVE="${HOME}/.hermes/SOUL.md"
  NOUS_DEFAULT='You are Hermes Agent, an intelligent AI assistant created by Nous Research.'

  if [[ ! -e "$GROK_LIVE" ]]; then
    err "live Grok AGENTS missing: $GROK_LIVE"
  elif [[ -L "$GROK_LIVE" ]]; then
    target="$(readlink "$GROK_LIVE")"
    if [[ "$target" == *'/.codex/AGENTS.md' || "$target" == '../.codex/AGENTS.md' || "$target" == *'codex/AGENTS.md' ]]; then
      pass "live Grok AGENTS is expected Codex symlink ($target)"
    else
      err "live Grok AGENTS symlink is unexpected: $target"
    fi
  elif grep -q '^# Personal Grok Notes' "$GROK_LIVE"; then
    pass 'live Grok AGENTS already rendered (Personal Grok Notes)'
  else
    err 'live Grok AGENTS is neither Codex symlink nor rendered Grok adapter'
  fi

  if [[ ! -f "$SOUL_LIVE" ]]; then
    err "live Hermes SOUL missing: $SOUL_LIVE"
  elif grep -q '^# Hermes' "$SOUL_LIVE" && grep -q '/home/dev/AgentMemory' "$SOUL_LIVE"; then
    pass 'live Hermes SOUL already rendered (managed identity)'
  elif grep -Fq "$NOUS_DEFAULT" "$SOUL_LIVE" && ! grep -Fq 'I like short, practical work' "$SOUL_LIVE"; then
    pass 'live Hermes SOUL is known Nous default one-line identity'
  else
    err 'live Hermes SOUL is neither Nous default nor rendered managed SOUL'
  fi

  if [[ -f "$MANIFEST" ]]; then
    check_live_portable_links
  else
    err "manifest missing for live portable checks: $MANIFEST"
  fi

  echo
  [[ "$fail" -eq 0 ]] && { echo "PASSED: live migration checks"; exit 0; }
  echo "FAILED: live migration checks"; exit 1
fi

echo "== agent-config-sync checks =="
echo "source: $ROOT"

SHARED=(
  .chezmoitemplates/agents-shared.md
  .chezmoitemplates/agents-shared-before-worktrees.md
  .chezmoitemplates/agents-shared-after-git.md
)
HARNESS=(
  'dot_claude/CLAUDE.md.tmpl|# Global Claude Rules|# Personal Codex Notes'
  'dot_codex/AGENTS.md.tmpl|# Personal Codex Notes|# Global Claude Rules'
  'dot_grok/AGENTS.md.tmpl|# Personal Grok Notes|# Personal Codex Notes'
  'dot_pi/agent/AGENTS.md.tmpl|# Personal Pi Notes|# Personal Codex Notes'
  'private_dot_factory/AGENTS.md.tmpl|# Personal Droid Notes|# Personal Codex Notes'
)
SOUL=private_dot_hermes/SOUL.md.tmpl
SHARED_MAX_BYTES=6100
REQUIRED_SHARED_INVARIANTS=(
  'I like short, practical work. Read the repo, make the smallest clean change, and show proof before calling something done.'
  '- Be direct: no filler or ceremony. Fix root causes, not symptoms.'
  '- No hacks, monkey patches, fake fixes, temporary workarounds, or unrelated refactors.'
  'Dictation can corrupt names, model IDs, and technical terms. Confirm suspicious or contradictory wording instead of following it literally.'
  '- Never expose, print, commit, or send secrets or private production data.'
  '- Destructive filesystem, Git, account, or external-service actions require explicit confirmation.'
  '- Public actions (posts, replies, likes, follows, DMs, publishing) are drafts only; the user performs them.'
  '- Never use Anthropic Haiku, directly, indirectly, or as a fallback.'
  'verify-personal-github` to verify `ElbertePlinio`'
  '- Protect user work: check status before staging, committing, merging, or cleaning; untracked files are user-owned.'
  '- Push only when asked, except in clearly identified Pickforge or Personal repos'
  '- Use English Conventional Commits. No attribution, trailers, bot/noreply/model names, AI signatures, or `Claude`.'
  '`$local-review` is the shipping review source. GitHub-hosted Codex review is optional escalation, not a default prerequisite'
  'Never merge with failing or in-flight required checks, unanswered valid findings, or an unreviewed current HEAD.'
  '~/Projects/.worktrees/<repo-name>/<branch-name>'
  'Run the narrowest behavioral validation that proves the change.'
  '/home/dev/AgentMemory'
  'Never store secrets in memory.'
  'never edit only a rendered `$HOME` file'
  '- Use `context7-mcp` or native Context7 when current library/API docs matter.'
  '- Use `design-director` for material UI/UX work, plus any repo-specific design skill.'
  '- For ship/open-PR/review-and-merge requests, use `ship-pr` where available'
)

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-config-sync.XXXXXX")"
DEST="$(mktemp -d "${TMPDIR:-/tmp}/chezmoi-dest.XXXXXX")"
trap 'rm -rf "$TMP" "$DEST"' EXIT
render() { chezmoi "${SRC[@]}" execute-template --file "$1" >"$2"; }

for f in "${SHARED[@]}"; do need "$f"; done
[[ -f .chezmoitemplates/agents-shared.md ]] && \
  grep -q 'agents-shared-before-worktrees.md' .chezmoitemplates/agents-shared.md && \
  grep -q 'agents-shared-after-git.md' .chezmoitemplates/agents-shared.md && \
  pass 'agents-shared.md composes parts' || err 'agents-shared.md must include before/after parts'

shared_source_bytes=$((
  $(wc -c <.chezmoitemplates/agents-shared-before-worktrees.md) +
  $(wc -c <.chezmoitemplates/agents-shared-after-git.md)
))
if ((shared_source_bytes <= SHARED_MAX_BYTES)); then
  pass "shared source size ${shared_source_bytes} bytes (budget ${SHARED_MAX_BYTES})"
else
  err "shared source size ${shared_source_bytes} bytes exceeds ${SHARED_MAX_BYTES}-byte regression budget (recorded baseline: 11400)"
fi

if render .chezmoitemplates/agents-shared.md "$TMP/agents-shared.md"; then
  shared_output_bytes="$(wc -c <"$TMP/agents-shared.md")"
  if ((shared_output_bytes <= SHARED_MAX_BYTES)); then
    pass "shared rendered size ${shared_output_bytes} bytes (budget ${SHARED_MAX_BYTES})"
  else
    err "shared rendered size ${shared_output_bytes} bytes exceeds ${SHARED_MAX_BYTES}-byte regression budget"
  fi
  for invariant in "${REQUIRED_SHARED_INVARIANTS[@]}"; do
    grep -Fq -- "$invariant" "$TMP/agents-shared.md" \
      && pass "shared output invariant: $invariant" || err "shared output invariant missing: $invariant"
  done
else
  err 'shared template render failed'
fi


need "$SOUL"
grep -q '/home/dev/AgentMemory' "$SOUL" || err 'Hermes SOUL missing AgentMemory'
grep -qi 'public' "$SOUL" || err 'Hermes SOUL missing public-action boundary'
grep -qi 'memory' "$SOUL" || err 'Hermes SOUL missing memory boundary'
grep -qE 'I like short, practical work|Fix root causes, not symptoms' "$SOUL" \
  && err 'Hermes SOUL must not dump full coding policy' || pass 'Hermes SOUL identity-oriented'

[[ -L dot_grok/AGENTS.md.tmpl || -L dot_grok/AGENTS.md ]] && err 'Grok AGENTS must not be a symlink'
need dot_grok/AGENTS.md.tmpl
if [[ -f dot_grok/AGENTS.md.tmpl ]]; then
  grep -qE 'codex/AGENTS|\.\./\.codex|Personal Codex Notes' dot_grok/AGENTS.md.tmpl \
    && err 'Grok adapter links to or reuses Codex' || pass 'Grok adapter not Codex-linked'
  grep -q 'gpt-5.6-luna' dot_grok/AGENTS.md.tmpl \
    && err 'Grok adapter still embeds full model table' || pass 'Grok has no full model table'
  grep -q 'model-orchestration' dot_grok/AGENTS.md.tmpl \
    && pass 'Grok references model-orchestration skill' || err 'Grok missing model-orchestration reference'
fi

check_manifest_and_sources
check_runtime_exclusions


for entry in "${HARNESS[@]}"; do
  IFS='|' read -r path want forbid <<<"$entry"
  if [[ ! -f "$path" ]]; then err "missing: $path"; continue; fi
  grep -Eq 'template "(agents-shared\.md|agents-shared-before-worktrees\.md)"' "$path" \
    || err "missing shared include: $path"
  for bad in 'I like short, practical work' 'names, model IDs, and technical terms' '/home/dev/AgentMemory'; do
    grep -Fq "$bad" "$path" && err "duplicate shared policy in $path: $bad"
  done
  out="$TMP/$(echo "$path" | tr '/' '_')"
  if ! render "$path" "$out"; then err "render failed: $path"; continue; fi
  pass "rendered $path"
  grep -Fq "$want" "$out" || err "missing heading in $path: $want"
  grep -Fq "$forbid" "$out" && err "forbidden heading in $path: $forbid"
  [[ "$(grep -c 'I like short, practical work' "$out" || true)" -eq 1 ]] || err "shared intro count != 1 in $path"
  grep -q PickScribe "$out" || err "missing PickScribe in $path"
  grep -q '/home/dev/AgentMemory' "$out" || err "missing AgentMemory in $path"
done

render "$SOUL" "$TMP/SOUL.md" && pass 'rendered Hermes SOUL' || err 'Hermes SOUL render failed'

TARGETS=(
  "$DEST/.claude/CLAUDE.md" "$DEST/.codex/AGENTS.md" "$DEST/.grok/AGENTS.md"
  "$DEST/.pi/agent/AGENTS.md" "$DEST/.factory/AGENTS.md" "$DEST/.hermes/SOUL.md"
)
EXPECTED=(
  dot_claude/CLAUDE.md.tmpl dot_codex/AGENTS.md.tmpl dot_grok/AGENTS.md.tmpl
  dot_pi/agent/AGENTS.md.tmpl private_dot_factory/AGENTS.md.tmpl private_dot_hermes/SOUL.md.tmpl
)
if chezmoi "${SRC[@]}" --destination "$DEST" source-path "${TARGETS[@]}" >"$TMP/sp.txt" 2>"$TMP/sp.err"; then
  for e in "${EXPECTED[@]}"; do
    grep -Fq "$e" "$TMP/sp.txt" && pass "source-path $e" || err "source-path missing $e"
  done
else
  err "source-path failed: $(tr '\n' ' ' <"$TMP/sp.err")"
fi
chezmoi "${SRC[@]}" --destination "$DEST" --dry-run status >/dev/null 2>"$TMP/st.err" \
  && pass 'dry-run status (temp dest)' || err "dry-run status failed: $(tr '\n' ' ' <"$TMP/st.err")"

mkdir -p "$DEST/.grok" "$DEST/.hermes" \
  "$DEST/.claude/skills" "$DEST/.pi/agent/skills" "$DEST/.factory/skills" \
  "$DEST/.grok/skills" "$DEST/.hermes/skills" "$DEST/.agents/skills"
ln -s ../.codex/AGENTS.md "$DEST/.grok/AGENTS.md"
printf '%s\n' 'You are Hermes Agent, an intelligent AI assistant created by Nous Research.' >"$DEST/.hermes/SOUL.md"

if ! chezmoi "${SRC[@]}" --destination "$DEST" apply "$DEST/.agents/skills" \
  "$DEST/.grok/AGENTS.md" "$DEST/.hermes/SOUL.md"; then
  err 'temp seed apply (canonical skills / adapters) failed'
else
  [[ ! -L "$DEST/.grok/AGENTS.md" ]] && grep -q '^# Personal Grok Notes' "$DEST/.grok/AGENTS.md" \
    && pass 'temp migration replaces Grok symlink safely' || err 'temp Grok symlink migration failed'
  grep -q '^# Hermes' "$DEST/.hermes/SOUL.md" && grep -q '/home/dev/AgentMemory' "$DEST/.hermes/SOUL.md" \
    && pass 'temp migration replaces default Hermes SOUL safely' || err 'temp Hermes SOUL migration failed'
fi

if [[ -d "$DEST/.agents/skills/context7-mcp" ]]; then
  rm -rf "$DEST/.claude/skills/context7-mcp"
  cp -a "$DEST/.agents/skills/context7-mcp" "$DEST/.claude/skills/context7-mcp"
  if dirs_identical "$DEST/.claude/skills/context7-mcp" "$DEST/.agents/skills/context7-mcp"; then
    pass 'seeded Claude context7 as identical regular directory'
  else
    err 'failed to seed identical Claude context7 directory'
  fi
else
  err 'canonical context7-mcp missing after seed apply'
fi

mapfile -t PORTABLE_TARGETS < <(jq -r --arg dest "$DEST" '
  . as $root
  | .skills | to_entries[]
  | .key as $skill
  | .value[] as $harness
  | $root.harnesses[$harness] as $h
  | select($h.discovery == "symlink")
  | ($h.skills_root | sub("^~"; $dest)) + "/" + $skill
' "$MANIFEST")

if ((${#PORTABLE_TARGETS[@]})); then
  if chezmoi "${SRC[@]}" --destination "$DEST" apply "${PORTABLE_TARGETS[@]}"; then
    pass "temp applied ${#PORTABLE_TARGETS[@]} portable skill links"
  else
    err 'temp portable skill apply failed'
  fi
fi

while IFS=$'\t' read -r skill harness; do
  discovery="$(jq -r --arg h "$harness" '.harnesses[$h].discovery' "$MANIFEST")"
  [[ "$discovery" == "symlink" ]] || continue
  root="$(jq -r --arg h "$harness" --arg dest "$DEST" \
    '.harnesses[$h].skills_root | sub("^~"; $dest)' "$MANIFEST")"
  expected_prefix="$(jq -r --arg h "$harness" '.harnesses[$h].relative_prefix' "$MANIFEST")"
  link="${root}/${skill}"
  want="${expected_prefix}/${skill}"
  if [[ ! -L "$link" ]]; then
    err "temp portable link missing or not symlink: $harness/$skill ($link)"
    continue
  fi
  got="$(readlink "$link")"
  if [[ "$got" != "$want" ]]; then
    err "temp readlink $harness/$skill expected '$want' got '$got'"
    continue
  fi
  if [[ ! -e "$link/SKILL.md" ]]; then
    err "temp resolved SKILL.md missing: $harness/$skill"
    continue
  fi
  if ! cmp -s "$link/SKILL.md" "$DEST/.agents/skills/${skill}/SKILL.md"; then
    err "temp SKILL.md mismatch vs canonical: $harness/$skill"
    continue
  fi
  pass "temp portable ok: $harness/$skill"
done < <(jq -r '.skills | to_entries[] | .key as $s | .value[] | "\($s)\t\(.)"' "$MANIFEST")

bash -n "$ROOT/scripts/check-agent-config-sync.sh" && pass 'bash -n' || err 'bash -n failed'
if [[ -f "$ROOT/dot_local/bin/executable_agent-config-sync" ]]; then
  bash -n "$ROOT/dot_local/bin/executable_agent-config-sync" && pass 'bash -n agent-config-sync' \
    || err 'bash -n agent-config-sync failed'
fi

echo
[[ "$fail" -eq 0 ]] && { echo "PASSED: agent-config-sync checks"; exit 0; }
echo "FAILED: agent-config-sync checks"; exit 1

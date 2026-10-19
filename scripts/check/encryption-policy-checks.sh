# Encryption policy. age encryption exists here for credentials, nothing else.
#
# Blanket `chezmoi add --encrypt` over whole directories once left 719 of 1148
# tracked files as opaque blobs in a public repo while only 6 held secrets. That
# also cost real coverage: several content checks skip `*.age`, so an unportable
# Linux path and two retired harness references sat unnoticed inside encrypted
# files. chezmoi has no `.chezmoiattributes`, so encryption cannot be declared
# by pattern, this gate is the only place the policy can be enforced.
#
# Both directions are checked. A policy that only catches an unencrypted secret
# still lets the tree quietly re-close around readable content.

# Source globs allowed to be encrypted, each with the reason it must stay so.
ENCRYPTION_ALLOWED_SOURCES=(
  '.secrets.json.age|static API keys shared by readable target templates'
)

# Rendered target basenames that must never be committed in plaintext.
ENCRYPTION_REQUIRED_BASENAMES=(
  .env
  auth.json
  credentials.json
  tokens.json
  key.txt
  .secrets.json
  secrets.json
  id_rsa
  id_ed25519
)

# Rendered target basename suffixes that must never be committed in plaintext.
ENCRYPTION_REQUIRED_SUFFIXES=(
  .pem
  .key
)

# Trees that must not return to the source state at all, with the reason.
UNVERSIONED_SOURCE_TREES=(
  'dot_pi/agent/npm|Pi npm workspace is reconstructible with npm ci'
  'dot_config/chezmoi|holds the age identity that decrypts everything else'
  'dot_pi/agent/encrypted_private_auth.json.age|live Pi provider auth state'
  'dot_pi/agent/private_auth.json|live Pi provider auth state'
  'dot_pi/agent/auth.json|live Pi provider auth state'
  'dot_pi/agent/encrypted_auth.json.age|live Pi provider auth state'
  'dot_pi/agent/mcp-oauth|live MCP OAuth token state'
  'dot_context7|live Context7 OAuth token state'
  'dot_pi/agent/private_mcp-oauth|live MCP OAuth token state'
  'private_dot_context7|live Context7 OAuth token state'
)

# .gitignore must cover the plaintext spelling too, not only the encrypted one.
ENCRYPTION_GITIGNORE_LINES=(
  dot_codex/private_auth.json
  dot_codex/private_config.toml
  dot_pi/agent/run-history.jsonl
  dot_pi/agent/mcp-cache.json
  dot_pi/agent/mcp-npx-cache.json
  dot_pi/agent/mcp-onboarding.json
  dot_config/chezmoi/
  .secrets.json
)

# Strip chezmoi attribute prefixes and suffixes to get the rendered basename.
encryption_target_basename() {
  local name="$1" changed=1 prefix
  while [[ "$changed" -eq 1 ]]; do
    changed=0
    for prefix in encrypted_ private_ readonly_ empty_ exact_ executable_ \
      symlink_ create_ modify_ remove_ run_ literal_ once_ onchange_ \
      before_ after_ external_; do
      if [[ "$name" == "$prefix"* ]]; then
        name="${name#"$prefix"}"
        changed=1
      fi
    done
  done
  name="${name%.age}"
  name="${name%.tmpl}"
  name="${name%.literal}"
  [[ "$name" == dot_* ]] && name=".${name#dot_}"
  printf '%s\n' "$name"
}

# Ignored files count too. chezmoi does not read .gitignore, and a forced
# `git add` commits an ignored file.
encryption_source_files() {
  local rel
  while IFS= read -r rel; do
    [[ -f "$ROOT/$rel" ]] && printf '%s\n' "$rel"
  done < <(cd "$ROOT" && git ls-files --cached --others | sort -u)
  return 0
}

check_secret_templates() {
  local source
  for source in dot_pi/agent/private_mcp.json.tmpl \
    dot_agents/private_deepseek.env.tmpl dot_agents/private_stripe.env.tmpl; do
    if chezmoi "${SRC[@]}" execute-template --file "$ROOT/$source" >/dev/null; then
      pass "secret template renders: $source"
    else
      err "secret template failed to render: $source"
    fi
  done
}

check_encryption_allowlist() {
  local age rel entry glob reason matched unjustified=0
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    matched=0
    for entry in "${ENCRYPTION_ALLOWED_SOURCES[@]}"; do
      glob="${entry%%|*}"
      # shellcheck disable=SC2053
      [[ "$rel" == $glob ]] && { matched=1; break; }
    done
    if [[ "$matched" -eq 0 ]]; then
      err "encrypted without justification, add it to ENCRYPTION_ALLOWED_SOURCES or decrypt it: $rel"
      unjustified=$((unjustified + 1))
    fi
  done < <(encryption_source_files | grep '\.age$' || true)
  [[ "$unjustified" -eq 0 ]] \
    && pass 'every encrypted source file has a declared credential justification'

  local stale=0
  for entry in "${ENCRYPTION_ALLOWED_SOURCES[@]}"; do
    glob="${entry%%|*}"
    reason="${entry#*|}"
    if [[ -z "$reason" || "$reason" == "$glob" ]]; then
      err "encryption allowance has no reason: $glob"
      stale=$((stale + 1))
      continue
    fi
    matched=0
    while IFS= read -r rel; do
      # shellcheck disable=SC2053
      [[ "$rel" == $glob ]] && { matched=1; break; }
    done < <(encryption_source_files | grep '\.age$' || true)
    if [[ "$matched" -eq 0 ]]; then
      err "stale encryption allowance, no source file matches: $glob"
      stale=$((stale + 1))
    fi
  done
  [[ "$stale" -eq 0 ]] && pass 'no stale or reasonless encryption allowances'
}

check_required_encryption() {
  local rel base target leaked=0 name suffix
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    [[ "$rel" == *.age ]] && continue
    [[ "$rel" == scripts/* || "$rel" == docs/* ]] && continue
    base="${rel##*/}"
    target="$(encryption_target_basename "$base")"
    for name in "${ENCRYPTION_REQUIRED_BASENAMES[@]}"; do
      if [[ "$target" == "$name" ]]; then
        err "credential file committed in plaintext, must be encrypted: $rel"
        leaked=$((leaked + 1))
      fi
    done
    for suffix in "${ENCRYPTION_REQUIRED_SUFFIXES[@]}"; do
      if [[ "$target" == *"$suffix" ]]; then
        err "key material committed in plaintext, must be encrypted: $rel"
        leaked=$((leaked + 1))
      fi
    done
  done < <(encryption_source_files)
  [[ "$leaked" -eq 0 ]] \
    && pass 'no credential file or key material is committed in plaintext'
}

check_unversioned_trees() {
  local entry prefix reason present=0 hits
  for entry in "${UNVERSIONED_SOURCE_TREES[@]}"; do
    prefix="${entry%%|*}"
    reason="${entry#*|}"
    hits="$(encryption_source_files | awk -v prefix="$prefix" '$0 == prefix || index($0, prefix "/") == 1 { print; exit }')"
    if [[ -n "$hits" ]]; then
      err "tree must not be versioned ($reason): $prefix"
      present=$((present + 1))
    fi
  done
  [[ "$present" -eq 0 ]] && pass 'trees excluded from versioning stay out of the source state'

}

check_encryption_gitignore() {
  local line missing=0
  for line in "${ENCRYPTION_GITIGNORE_LINES[@]}"; do
    grep -Fxq "$line" "$ROOT/.gitignore" \
      || { err "gitignore misses the plaintext spelling of a secret path: $line"; missing=$((missing + 1)); }
  done
  [[ "$missing" -eq 0 ]] \
    && pass 'gitignore covers plaintext and encrypted spellings of secret paths'
}

# A checker that never fails proves nothing: seed ignored plaintext
# credentials in a scratch repository and require rejection.
check_encryption_policy_detection() {
  local seeded="$TMP/encryption-policy-seeded"
  mkdir -p "$seeded/dot_pi/agent"
  git -C "$seeded" init -q
  printf '%s\n' '.secrets.json' 'dot_pi/agent/private_auth.json' >"$seeded/.gitignore"
  printf '%s\n' '{"probe_key":"probe"}' >"$seeded/.secrets.json"
  printf '%s\n' '{}' >"$seeded/dot_pi/agent/private_auth.json"
  if (ROOT="$seeded"; fail=0; check_required_encryption >/dev/null 2>&1; [[ "$fail" -ne 0 ]]); then
    pass 'encryption policy rejects ignored plaintext credential files'
  else
    err 'encryption policy missed ignored plaintext credential files'
  fi
}

check_encryption_allowlist
check_required_encryption
check_unversioned_trees
check_encryption_gitignore
check_encryption_policy_detection

check_secret_templates

# Hermes neutral policy: source-only handoff

Shared policy is owned by agent-config-sync. `agents-shared.md` composes neutral prefix, managed Lanes policy, and neutral suffix in their original order. Recorded SHA-256 fixtures enforce the deliberately approved render of the five existing harnesses. Update those fixtures only when the shared policy intentionally changes.

`dot_agents/hermes-system-prompt.md.tmpl` composes only the neutral sections and a native Hermes adapter. Its target is `~/.agents/hermes-system-prompt.md`, not an automatically loaded context file. No Hermes configuration root, SOUL, profile, plugin, or credential file is managed by this change.

The supported input is profile-local `config.yaml` -> `agent.system_prompt`. `hermes_cli/personality.py:resolve_ephemeral_system_prompt` resolves it; CLI and gateway consume that resolver. This is an ephemeral request overlay, not part of cached prompt assembly (`agent/system_prompt.py`). A selected personality, HERMES_EPHEMERAL_SYSTEM_PROMPT, or gateway channel override can replace it. Do not claim mandatory always-on policy enforcement.

Native children currently construct their own ephemeral prompt in `tools/delegate_tool_progress.py:_build_child_system_prompt` and `tools/delegate_tool.py`, rather than inheriting this manual overlay automatically. The delegation owner must pass the neutral policy explicitly in child context and test once-only inclusion, or separately implement inheritance. This source-only change does not modify delegation or claim child runtime coverage.

After approval, from the chezmoi source:

```sh
agent-config-sync check
python3 scripts/check-hermes-policy.py "$HOME/.hermes/hermes-agent"
bash scripts/check-agent-config-sync.sh --check-live-migration --strict-preflight
chezmoi diff --exclude scripts -- ~/.agents/hermes-system-prompt.md
chezmoi apply --exclude scripts -- ~/.agents/hermes-system-prompt.md
chezmoi verify --exclude scripts -- ~/.agents/hermes-system-prompt.md
```

Do not run full `agent-config-sync apply`. Before applying, refuse any divergent existing policy target rather than overwriting it. Review unrelated preflight drift without expanding scope.

Profile activation is a separate approved operation, using the actual Hermes configuration command, not a new runtime feature. First privately back up each exact config, check that `agent.system_prompt` is empty or already equals the rendered adapter, and refuse divergent manual instructions. Confirm personality is neutral and no environment/channel prompt overrides are active. Do not dump configuration or credentials. Then use:

```sh
hermes --profile default config set agent.system_prompt "$(chezmoi cat ~/.agents/hermes-system-prompt.md)"
# Only after its owner creates/confirms the coding profile:
hermes --profile coding config set agent.system_prompt "$(chezmoi cat ~/.agents/hermes-system-prompt.md)"
```

The coding name is a proposed activation scope, not a profile created here. Never run these commands for socialdesk. Compare only the updated field to the rendered text in memory using `.strip()` on both strings (shell command substitution drops trailing newlines), verify all other parsed config values unchanged, and use a fresh CLI/gateway session when authorized; do not restart a running session during activation. Confirm default/coding A -> B -> A isolation and native-child policy once-only behavior before claiming activation complete. Roll back only the changed field from the private backup. SOUL remains independent and untouched.

Source tests do not establish live model execution, gateway override behavior, child inheritance, or runtime V6 acceptance. No live apply, configuration write, profile creation, or commit was performed.

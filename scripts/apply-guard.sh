#!/usr/bin/env bash
# Runs before every full `chezmoi apply`, through run_before_00-apply-guard.sh.
# It stops the apply when a target holds content that chezmoi did not write
# last: a live edit made since the last apply, a file that existed before
# chezmoi managed it, or a live directory that a file or link would replace.
# chezmoi replaces the last two kinds without asking, and all kinds under
# --force. A scoped `chezmoi apply <path>` runs no scripts, so it skips this
# guard on purpose. An --include or --exclude that leaves out scripts also
# skips it, and --keep-going ignores its failure, so a full apply must not use
# them.
set -euo pipefail

chezmoi_bin="${CHEZMOI_EXECUTABLE:-chezmoi}"
args=()
[[ -n "${CHEZMOI_SOURCE_DIR:-}" ]] && args+=(--source "$CHEZMOI_SOURCE_DIR")
[[ -n "${CHEZMOI_DEST_DIR:-}" ]] && args+=(--destination "$CHEZMOI_DEST_DIR")
[[ -n "${CHEZMOI_CONFIG_FILE:-}" && -f "$CHEZMOI_CONFIG_FILE" ]] \
  && args+=(--config "$CHEZMOI_CONFIG_FILE")

# chezmoi exports its command line but no variable for the state file. Take
# the path from that command line, then from the config, then use the default
# location next to the config file.
config_file="${CHEZMOI_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/chezmoi.toml}"
state_file=""
from_args=false
set -f
read -r -a words <<<"${CHEZMOI_ARGS:-}"
set +f
for ((i = 0; i < ${#words[@]}; i++)); do
  case "${words[$i]}" in
    --persistent-state=*) state_file="${words[$i]#*=}"; from_args=true ;;
    --persistent-state) state_file="${words[$((i + 1))]:-}"; from_args=true ;;
  esac
done

# The running apply holds the state lock, so read a private copy.
work="$(mktemp -d "${TMPDIR:-/tmp}/apply-guard.XXXXXX")"
trap 'rm -rf "$work"' EXIT
[[ -n "$state_file" ]] || state_file="$("$chezmoi_bin" ${args[@]+"${args[@]}"} \
  execute-template '{{ .chezmoi.config.persistentState }}')"
[[ -n "$state_file" ]] || state_file="$(dirname "$config_file")/chezmoistate.boltdb"
# CHEZMOI_ARGS is joined with spaces, and a relative path depends on the
# caller's directory. A wrong state file would make every target look unowned.
if [[ "$state_file" != /* ]] || { $from_args && [[ ! -f "$state_file" ]]; }; then
  echo "apply-guard: cannot read the state file '$state_file'." >&2
  echo "Name an existing state file with an absolute path without spaces." >&2
  exit 1
fi
[[ -f "$state_file" ]] && cp "$state_file" "$work/state.boltdb"
args+=(--persistent-state "$work/state.boltdb")

cz() { "$chezmoi_bin" ${args[@]+"${args[@]}"} "$@"; }

# status prints one path per line, so a newline in a source name would hide
# a target from the checks below.
source_dir="${CHEZMOI_SOURCE_DIR:-$(cz source-path)}"
if [[ -n "$(find "$source_dir" -name .git -prune -o -name "*"$'\n'"*" -print)" ]]; then
  echo "apply-guard: a source path contains a newline; rename it first." >&2
  exit 1
fi

# Live paths that this machine leaves to another tool through ignore.local.
# A chezmoi template reads each line the way chezmoi reads .chezmoiignore:
# the same comment regex, then Go's TrimSpace. chezmoi's own glob then expands
# the pattern. Lines that start with ! only undo other patterns, so skipping
# them can only block more removals.
dest="${CHEZMOI_DEST_DIR:-$HOME}"
local_ignore="$HOME/.config/chezmoi/ignore.local"
kept=""
kept_loaded=false
load_kept() {
  $kept_loaded && return
  kept_loaded=true
  [[ -f "$local_ignore" ]] || return 0
  kept="$(GUARD_IGNORE="$local_ignore" cz execute-template \
    '{{ range splitList "\n" (include (env "GUARD_IGNORE")) }}
{{- $pattern := regexReplaceAll `(?:\A|\s+)#.*$` . "" | trim }}
{{- if and $pattern (not (hasPrefix "!" $pattern)) }}
{{- range glob $pattern }}{{ . }}{{ "\n" }}{{ end }}
{{- end }}
{{- end }}')"
}

status="$(cz status --exclude=scripts --path-style=absolute)"
managed_dirs=""
edited=()
unowned=()
replaced=()
removed=()
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  before="${line:0:1}"
  planned="${line:1:1}"
  path="${line:3}"
  [[ "$planned" == ' ' ]] && continue
  # Removals come from .chezmoiremove and are meant to delete, but a removed
  # directory takes everything below it, including locally ignored paths.
  if [[ "$planned" == D ]]; then
    load_kept
    while IFS= read -r rel; do
      if [[ -n "$rel" && ( "$dest/$rel" == "$path" || "$dest/$rel" == "$path"/* ) ]]; then
        removed+=("$path")
        break
      fi
    done <<<"$kept"
    continue
  fi
  # A managed directory only changes mode, and its contents are separate
  # targets. Any other target replaces the live directory and its contents.
  if [[ -d "$path" && ! -L "$path" ]]; then
    [[ -n "$managed_dirs" ]] \
      || managed_dirs="$(cz managed --include=dirs --path-style=absolute)"
    grep -Fxq -- "$path" <<<"$managed_dirs" && continue
    replaced+=("$path")
    continue
  fi
  # Creating a missing target overwrites nothing.
  [[ -e "$path" || -L "$path" ]] || continue
  if [[ "$before" != ' ' ]]; then
    edited+=("$path")
    continue
  fi
  [[ -z "$(cz state get --bucket=entryState --key="$path")" ]] || continue
  unowned+=("$path")
done <<<"$status"

[[ "${#edited[@]}" -eq 0 && "${#unowned[@]}" -eq 0 && "${#replaced[@]}" -eq 0 \
  && "${#removed[@]}" -eq 0 ]] && exit 0

{
  echo "apply-guard: this full apply would overwrite content chezmoi did not write."
  for path in ${edited[@]+"${edited[@]}"}; do
    echo "  edited since the last apply: $path"
  done
  for path in ${unowned[@]+"${unowned[@]}"}; do
    echo "  existed before chezmoi managed it: $path"
  done
  for path in ${replaced[@]+"${replaced[@]}"}; do
    echo "  live directory would be replaced: $path"
  done
  for path in ${removed[@]+"${removed[@]}"}; do
    echo "  removal would delete a path in $local_ignore: $path"
  done
  echo "Review each path. Merge it with \`chezmoi merge <path>\`, or take the"
  echo "source version with \`chezmoi apply --force <path>\`. Then apply again."
  [[ "${#removed[@]}" -eq 0 ]] \
    || echo "For a removal, move the ignored path out of it or drop its pattern."
} >&2
exit 1

#!/bin/sh
# Clone the companion repositories that a full apply expects.

# Clone $1 (owner/name) into $2, unless $2 already holds that repository.
ensure_clone() {
  repo_path=$1
  target=$2

  if [ -e "$target" ] || [ -L "$target" ]; then
    if ! git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      printf 'error: %s exists but is not a git repository; refusing to overwrite it\n' "$target" >&2
      return 1
    fi

    origin=$(git -C "$target" remote get-url origin 2>/dev/null) || origin=
    origin=${origin%/}
    origin=${origin%.git}
    # Accept github.com and SSH config aliases like github.com-oElberte-dotfiles,
    # which machines with a per-repository identity key use for personal repos.
    case "$origin" in
      git@github.com:"$repo_path"|git@github.com[-.]*:"$repo_path"|\
      ssh://git@github.com/"$repo_path"|ssh://git@github.com[-.]*/"$repo_path"|\
      https://github.com/"$repo_path")
        return 0
        ;;
    esac
    printf 'error: %s is a git repository with unexpected origin %s; refusing to overwrite it\n' "$target" "${origin:-<missing>}" >&2
    return 1
  fi

  mkdir -p "$(dirname "$target")"
  if git clone "git@github.com:$repo_path.git" "$target" 2>/dev/null; then
    return 0
  fi

  # github.com may be bound to a different identity on this machine; try SSH
  # config host aliases that resolve back to github.com.
  for alias in $(awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i ~ /^github\.com[-.]/) print $i }' "$HOME/.ssh/config" 2>/dev/null); do
    if git clone "git@$alias:$repo_path.git" "$target"; then
      return 0
    fi
  done

  printf 'error: failed to clone %s into %s\n' "$repo_path" "$target" >&2
  return 1
}

status=0
ensure_clone ElbertePlinio/AgentMemory "$HOME/AgentMemory" || status=1

pi_kit="$HOME/Projects/Personal/pi-kit"
if ! ensure_clone ElbertePlinio/pi-kit "$pi_kit"; then
  status=1
elif [ ! -d "$pi_kit/node_modules" ]; then
  bun_bin=$(command -v bun || printf '%s' "$HOME/.bun/bin/bun")
  if [ ! -x "$bun_bin" ]; then
    printf 'warning: bun unavailable; run bun install in %s manually\n' "$pi_kit" >&2
  elif ! (cd "$pi_kit" && "$bun_bin" install --frozen-lockfile); then
    printf 'warning: bun install failed in %s; run it manually\n' "$pi_kit" >&2
  fi
fi

exit "$status"

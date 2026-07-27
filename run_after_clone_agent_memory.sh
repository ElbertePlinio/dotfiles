#!/bin/sh

repo_path='ElbertePlinio/AgentMemory'
target="$HOME/AgentMemory"

if [ -e "$target" ] || [ -L "$target" ]; then
  if ! git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'error: %s exists but is not a git repository; refusing to overwrite it\n' "$target" >&2
    exit 1
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
      exit 0
      ;;
    *)
      printf 'error: %s is a git repository with unexpected origin %s; refusing to overwrite it\n' "$target" "${origin:-<missing>}" >&2
      exit 1
      ;;
  esac
fi

mkdir -p "$(dirname "$target")"
if git clone "git@github.com:$repo_path.git" "$target" 2>/dev/null; then
  exit 0
fi

# github.com may be bound to a different identity on this machine; try SSH
# config host aliases that resolve back to github.com.
for alias in $(awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i ~ /^github\.com[-.]/) print $i }' "$HOME/.ssh/config" 2>/dev/null); do
  if git clone "git@$alias:$repo_path.git" "$target"; then
    exit 0
  fi
done

printf 'error: failed to clone %s into %s\n' "$repo_path" "$target" >&2
exit 1

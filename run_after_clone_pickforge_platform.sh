#!/bin/sh

repo='git@github.com:pickforge/pickforge-platform.git'
target="$HOME/Projects/Pickforge/pickforge-platform"

if [ -e "$target" ] || [ -L "$target" ]; then
  if ! git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'error: %s exists but is not a git repository; refusing to overwrite it\n' "$target" >&2
    exit 1
  fi

  origin=$(git -C "$target" remote get-url origin 2>/dev/null) || origin=
  origin=${origin%/}
  case "$origin" in
    git@github.com:pickforge/pickforge-platform|git@github.com:pickforge/pickforge-platform.git|\
    ssh://git@github.com/pickforge/pickforge-platform|ssh://git@github.com/pickforge/pickforge-platform.git|\
    https://github.com/pickforge/pickforge-platform|https://github.com/pickforge/pickforge-platform.git)
      exit 0
      ;;
    *)
      printf 'error: %s is a git repository with unexpected origin %s; refusing to overwrite it\n' "$target" "${origin:-<missing>}" >&2
      exit 1
      ;;
  esac
fi

mkdir -p "$(dirname "$target")"
git clone "$repo" "$target" || {
  printf 'error: failed to clone %s into %s\n' "$repo" "$target" >&2
  exit 1
}

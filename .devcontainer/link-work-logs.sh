#!/bin/sh
set -eu

# Container-only; explicit paths allow isolated lifecycle tests without live mounts.
mount_path=${1:-/work-logs}
workspace_path=${2:-$(dirname "$0")/..}
link_path="$workspace_path/work logs"

if [ -L "$link_path" ] && [ "$(readlink "$link_path")" = "$mount_path" ]; then
  if [ ! -d "$mount_path" ]; then
    rm "$link_path"
  fi
elif [ -e "$link_path" ] || [ -L "$link_path" ]; then
  printf 'Warning: work logs link skipped; preserving existing %s.\n' "$link_path" >&2
elif [ -d "$mount_path" ]; then
  ln -s "$mount_path" "$link_path"
fi

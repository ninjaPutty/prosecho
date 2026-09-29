#!/bin/sh
set -eu

runtime=${DEVCONTAINER_RUNTIME:-}
if [ -z "$runtime" ]; then
  if command -v podman >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1; then
    runtime=podman
  elif command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
    runtime=docker
  else
    printf '%s\n' 'Set DEVCONTAINER_RUNTIME=podman or docker.' >&2
    exit 1
  fi
fi

case "$runtime" in
  podman)
    printf 'services:\n  app:\n    userns_mode: "keep-id:gid=100"\n    security_opt:\n      - label=disable\n' > .devcontainer/compose.runtime.yaml
    ;;
  docker|orbstack)
    printf 'services:\n  app: {}\n' > .devcontainer/compose.runtime.yaml
    ;;
  *)
    printf 'Unsupported DEVCONTAINER_RUNTIME: %s\n' "$runtime" >&2
    exit 1
    ;;
esac

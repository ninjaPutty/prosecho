#!/bin/sh
set -eu

# Host-side Linux/Podman smoke test, using only a disposable isolated identity.
if [ "$(uname -s)" != Linux ]; then
  printf '%s\n' 'This smoke test is Linux/rootless Podman only.' >&2
  exit 2
fi
temp=$(mktemp -d "${TMPDIR:-/tmp}/prosecho-dev-ssh.XXXXXXXX")
agent_pid=
cleanup() {
  if [ -n "$agent_pid" ]; then
    kill "$agent_pid"
    wait "$agent_pid" || true
  fi
  rm -rf "$temp"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
ssh-agent -D -a "$temp/agent.sock" >/dev/null 2>&1 &
agent_pid=$!
attempt=0
while [ ! -S "$temp/agent.sock" ]; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 5 ]; then
    printf '%s\n' 'Disposable agent failed to start.' >&2
    exit 1
  fi
  sleep 1
done
ssh-keygen -q -t ed25519 -N '' -C prosecho-disposable-test -f "$temp/key"
SSH_AUTH_SOCK="$temp/agent.sock" ssh-add -t 60 "$temp/key"
export PROSECHO_DEV_SSH_AGENT_SOCK="$temp/agent.sock"
# One-off service: no build, published ports, database start, or app recreation.
podman-compose --in-pod false -p prosecho \
  -f .devcontainer/compose.yaml \
  -f .devcontainer/compose.runtime.yaml \
  -f .devcontainer/compose.developer-ssh.yaml \
  run --rm --no-deps -v "$temp/key.pub:/run/prosecho-test.pub:ro" app \
  sh -c 'sh .devcontainer/developer-ssh-doctor.sh && ssh-add -T /run/prosecho-test.pub'

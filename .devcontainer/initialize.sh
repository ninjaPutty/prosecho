#!/bin/sh
set -eu

runtime=${DEVCONTAINER_RUNTIME:-}
if [ -z "$runtime" ]; then
  if command -v podman >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1; then
    runtime=podman
  elif command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
    runtime=docker
  elif command -v podman >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
    # NixOS can expose Docker's command name as a Podman compatibility wrapper.
    case "$(docker version 2>/dev/null || true)" in
      *Podman*|*podman*) runtime=podman ;;
      *)
        printf '%s\n' 'Set DEVCONTAINER_RUNTIME=podman or docker.' >&2
        exit 1
        ;;
    esac
  else
    printf '%s\n' 'Set DEVCONTAINER_RUNTIME=podman or docker.' >&2
    exit 1
  fi
fi

socket=${PROSECHO_DEV_SSH_AGENT_SOCK:-}
ssh_available=false
if [ -n "$socket" ]; then
  if [ -S "$socket" ]; then
    ssh_available=true
  else
    printf '%s\n' 'Explicit SSH agent socket unavailable; no agent socket mounted.' >&2
  fi
fi

secrets=${HOME}/.config/opencode/secrets.env
secrets_available=false
if [ -f "$secrets" ]; then
  secrets_available=true
else
  printf '%s\n' 'Optional OpenCode secrets unavailable; no secrets file mounted.' >&2
fi

logs_available=false
if [ -d '../work logs' ]; then
  logs_available=true
fi

case "$runtime" in
  podman)
    printf 'services:\n  app:\n    userns_mode: "keep-id:gid=100"\n    security_opt:\n      - label=disable\n' > .devcontainer/compose.runtime.yaml
    ;;
  docker|orbstack)
    printf 'services:\n  app:\n' > .devcontainer/compose.runtime.yaml
    ;;
  *)
    printf 'Unsupported DEVCONTAINER_RUNTIME: %s\n' "$runtime" >&2
    exit 1
    ;;
esac

# Use the same host snapshot for the Explorer folders and the optional bind.
{
  printf '%s\n' '{' '  "folders": ['
  printf '%s' '    {"name": "Prosecho", "path": "/prosecho"}'
  if [ "$logs_available" = true ]; then
    printf ',\n%s' '    {"name": "Work Logs", "path": "/work-logs"}'
  fi
  printf '\n%s\n' '  ]' '}'
} > .devcontainer/prosecho.code-workspace

if [ "$ssh_available" = true ]; then
  printf '%s\n' \
    '    environment:' \
    '      GIT_SSH_COMMAND: sh /prosecho/.devcontainer/git-ssh.sh' \
    '      SSH_AUTH_SOCK: /run/prosecho-dev-agent.sock' >> .devcontainer/compose.runtime.yaml
fi

printf '%s\n' '    volumes:' >> .devcontainer/compose.runtime.yaml
# Only declared persistent state is created; optional logs/secrets stay optional.
for path in .cache/opencode .local/share/opencode; do
  mkdir -p "$HOME/$path"
  source=$(printf '%s' "$HOME/$path" | sed -e "s/'/''/g" -e 's/\$/$$/g')
  printf '%s\n' \
    '      - type: bind' \
    "        source: '$source'" \
    "        target: /home/vscode/$path" \
    '        read_only: false' \
    '        bind:' \
    '          create_host_path: false' >> .devcontainer/compose.runtime.yaml
done

if [ "$logs_available" = true ]; then
  # Compose resolves sources relative to the base file in .devcontainer/.
  printf '%s\n' \
    '      - type: bind' \
    '        source: "../../work logs"' \
    '        target: /work-logs' \
    '        bind:' \
    '          create_host_path: false' >> .devcontainer/compose.runtime.yaml
fi

if [ "$ssh_available" = true ]; then
  # Escape YAML quotes and Compose interpolation without changing the host path.
  source=$(printf '%s' "$socket" | sed -e "s/'/''/g" -e 's/\$/$$/g')
  printf '%s\n' \
    '      - type: bind' \
    "        source: '$source'" \
    '        target: /run/prosecho-dev-agent.sock' \
    '        read_only: true' \
    '        bind:' \
    '          create_host_path: false' >> .devcontainer/compose.runtime.yaml
fi

if [ "$secrets_available" = true ]; then
  source=$(printf '%s' "$secrets" | sed -e "s/'/''/g" -e 's/\$/$$/g')
  printf '%s\n' \
    '      - type: bind' \
    "        source: '$source'" \
    '        target: /home/vscode/.config/opencode/secrets.env' \
    '        read_only: true' \
    '        bind:' \
    '          create_host_path: false' >> .devcontainer/compose.runtime.yaml
fi

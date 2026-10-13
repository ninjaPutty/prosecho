#!/bin/sh
set -eu

# Bound engine calls without requiring GNU timeout on macOS.
bounded() (
  "$@" &
  command_pid=$!
  (sleep 5; kill -TERM "$command_pid" 2>/dev/null || exit 0
    sleep 1; kill -KILL "$command_pid" 2>/dev/null || true) >/dev/null 2>&1 &
  timer_pid=$!
  status=0
  wait "$command_pid" || status=$?
  kill "$timer_pid" 2>/dev/null || true
  wait "$timer_pid" 2>/dev/null || true
  return "$status"
)

runtime=${DEVCONTAINER_RUNTIME:-}
if [ -z "$runtime" ]; then
  if command -v podman >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1; then
    runtime=podman
  elif command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
    runtime=docker
  elif command -v podman >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
    # NixOS can expose Docker's command name as a Podman compatibility wrapper.
    version=$(bounded docker version 2>/dev/null) || version=
    case "$version" in
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

remote_agent=false
if [ "$runtime" = podman ]; then
  if [ -n "${CONTAINER_HOST:-}" ] || [ -n "${CONTAINER_CONNECTION:-}" ]; then
    remote_agent=true
  fi
elif [ "$runtime" = docker ] || [ "$runtime" = orbstack ]; then
  # DOCKER_CONTEXT overrides DOCKER_HOST; never mistake a remote daemon for OrbStack.
  context=${DOCKER_CONTEXT:-}
  endpoint=${DOCKER_HOST:-}
  if [ -z "$context" ] && [ -z "${DOCKER_HOST:-}" ]; then
    context=$(bounded docker context show 2>/dev/null) || context=
  fi
  if [ -n "$context" ]; then
    endpoint=$(bounded docker context inspect --format '{{.Endpoints.docker.Host}}' \
      "$context" 2>/dev/null) || endpoint=
  fi
  case "$endpoint" in
    unix:/*) ;;
    *) remote_agent=true ;;
  esac
  if [ "$runtime" = docker ] && [ "$context" = orbstack ]; then runtime=orbstack; fi
fi

socket=${PROSECHO_DEV_SSH_AGENT_SOCK:-}
ssh_available=false
if [ "$runtime" = podman ] && [ "$remote_agent" = false ] && [ "$(uname -s)" = Linux ]; then
  socket=${PROSECHO_DEV_SSH_AGENT_SOCK:-${SSH_AUTH_SOCK:-}}
fi
if [ "$runtime" = orbstack ] && [ -z "$socket" ]; then
  socket=/run/host-services/ssh-auth.sock
fi
if [ "$remote_agent" = true ]; then
  printf '%s\n' 'Optional SSH agent gate: remote or unverified engine endpoint; agent mounts unsupported.' >&2
elif [ -n "$socket" ] && [ "${socket#/}" = "$socket" ]; then
  printf '%s\n' 'Optional SSH agent gate: selected socket path must be absolute; no agent mounted.' >&2
elif [ "$runtime" = orbstack ] && [ "$socket" = /run/host-services/ssh-auth.sock ]; then
  # The bridge exists in the engine VM, not the Mac filesystem. Only use trusted
  # cached project/base images, pinned by ID; never pull or create a bind source.
  image=
  for candidate in prosecho-app prosecho_app ghcr.io/rails/devcontainer/images/ruby:3.4.7; do
    id=$(bounded docker image inspect --format '{{.Id}}' "$candidate" 2>/dev/null) || continue
    case "$id" in
      sha256:*)
        digest=${id#sha256:}
        case "$digest" in *[!0-9a-f]*) continue ;; esac
        if [ "${#digest}" -eq 64 ]; then image=$id; break; fi
        ;;
    esac
  done
  if [ -z "$image" ]; then
    printf '%s\n' 'Optional SSH agent gate: no trusted cached probe image; build app then rerun initialization.' >&2
  elif bounded docker run --rm --pull=never --network=none --read-only \
      --mount "type=bind,source=$socket,target=/run/developer-ssh-agent.sock,readonly" \
      --entrypoint /bin/sh "$image" -c 'test -S /run/developer-ssh-agent.sock' \
      >/dev/null 2>&1; then
    ssh_available=true
  else
    printf '%s\n' 'Optional SSH agent gate: OrbStack bridge probe failed or timed out; no agent mounted.' >&2
  fi
elif [ -n "$socket" ]; then
  if [ -S "$socket" ]; then
    ssh_available=true
  else
    printf '%s\n' 'Optional SSH agent gate: selected socket unavailable; no agent socket mounted.' >&2
  fi
else
  printf '%s\n' 'Optional SSH agent gate: no selected socket; rerun initialization with the host agent environment.' >&2
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

printf '%s\n' '    environment:' >> .devcontainer/compose.runtime.yaml
if [ "$ssh_available" = true ]; then
  printf '%s\n' '      SSH_AUTH_SOCK: /run/developer-ssh-agent.sock' >> .devcontainer/compose.runtime.yaml
else
  printf '%s\n' "      SSH_AUTH_SOCK: ''" >> .devcontainer/compose.runtime.yaml
fi

if [ "$logs_available" = true ] || [ "$ssh_available" = true ] || [ "$secrets_available" = true ]; then
  printf '%s\n' '    volumes:' >> .devcontainer/compose.runtime.yaml
else
  printf '%s\n' '    volumes: []' >> .devcontainer/compose.runtime.yaml
fi

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
    '        target: /run/developer-ssh-agent.sock' \
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

#!/bin/sh
set -eu

if [ -z "${SSH_AUTH_SOCK:-}" ] || [ ! -S "$SSH_AUTH_SOCK" ]; then
  printf '%s\n' 'Developer SSH agent unavailable; see docs/developer-ssh.md.' >&2
  exit 2
fi

# A public identity selects an agent key without exposing its private half.
if [ -n "${PROSECHO_DEV_SSH_PUBLIC_KEY:-}" ]; then
  if [ ! -f "$PROSECHO_DEV_SSH_PUBLIC_KEY" ]; then
    printf '%s\n' 'PROSECHO_DEV_SSH_PUBLIC_KEY must name a mounted public key file.' >&2
    exit 2
  fi
  set -- -o IdentitiesOnly=yes -i "$PROSECHO_DEV_SSH_PUBLIC_KEY" "$@"
fi
exec ssh -F /prosecho/.devcontainer/ssh.git "$@"

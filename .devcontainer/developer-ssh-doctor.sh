#!/bin/sh
set -eu

case "${1:-}" in
  ''|--github) ;;
  *) printf '%s\n' 'Usage: sh .devcontainer/developer-ssh-doctor.sh [--github]' >&2; exit 2 ;;
esac

if [ -z "${SSH_AUTH_SOCK:-}" ] || [ ! -S "$SSH_AUTH_SOCK" ]; then
  printf '%s\n' 'No developer agent socket. Check forwarding using docs/developer-ssh.md.' >&2
  exit 2
fi
if ! ssh-add -l; then
  printf '%s\n' 'Agent is empty or inaccessible. Check host agent and UID; do not chmod 666.' >&2
  exit 2
fi
printf '%s\n' 'Agent reachable. Every loaded key is usable by trusted container processes.'
printf '%s\n' 'Only forward production identities into a container you explicitly trust.'

if [ "${1:-}" = --github ]; then
  status=0
  output=$(sh /prosecho/.devcontainer/git-ssh.sh -T git@github.com 2>&1) || status=$?
  printf '%s\n' "$output"
  # GitHub deliberately returns 1 after successful authentication without a shell.
  case "$status:$output" in
    1:*"successfully authenticated, but GitHub does not provide shell access."*) exit 0 ;;
    *) printf '%s\n' 'GitHub authentication not confirmed.' >&2; exit 1 ;;
  esac
fi

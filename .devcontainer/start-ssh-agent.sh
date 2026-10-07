#!/bin/sh
# Explicit host login operation: ssh-add may prompt for the key's passphrase.
set -eu

fail() { printf '%s\n' "$*" >&2; exit 1; }

[ "$#" -le 1 ] || fail 'Usage: sh .devcontainer/start-ssh-agent.sh [GitHub-private-key-path]'
key=${1:-$HOME/.ssh/id_ed25519}
socket=${PROSECHO_DEV_SSH_AGENT_SOCK:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/prosecho-dev-agent.sock}
case "$socket" in /*) ;; *) fail 'The dedicated socket path must be absolute.' ;; esac
parent=${socket%/*}
[ -d "$parent" ] && [ ! -L "$parent" ] && [ -O "$parent" ] ||
  fail 'Socket parent must already exist, be owned by you, and not be a symlink.'
# This helper targets Linux; other hosts must supply and verify their own bridge.
[ "$(stat -c %a "$parent")" = 700 ] || fail 'Socket parent must have mode 700.'
[ "$socket" != "${SSH_AUTH_SOCK:-}" ] || fail 'Refusing the current shared SSH_AUTH_SOCK.'
[ "$socket" != "/run/user/$(id -u)/gcr/ssh" ] || fail 'Refusing the desktop shared agent.'
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ "$socket" -ef "$SSH_AUTH_SOCK" ]; then
  fail 'Refusing an alias of the shared agent.'
fi
[ -f "$key" ] && [ -f "$key.pub" ] || fail 'Key and matching .pub file must exist on the host.'
read -r key_type key_blob comment < "$key.pub"
[ "$key_type" = ssh-ed25519 ] || fail 'Use an Ed25519 GitHub development key.'
ssh-keygen -lf "$key.pub"

if [ -e "$socket" ] || [ -L "$socket" ]; then
  [ -S "$socket" ] && [ ! -L "$socket" ] && [ -O "$socket" ] ||
    fail 'Existing socket path is unsafe; nothing was removed.'
  [ "$(stat -c %a "$socket")" = 600 ] || fail 'Existing socket must have mode 600.'
else
  (umask 077; ssh-agent -a "$socket" -s) >/dev/null
fi
# Scope every agent operation to this socket; never eval or change the shared environment.
export SSH_AUTH_SOCK="$socket"
status=0
identities=$(ssh-add -L) || status=$?
case "$status" in
  0)
    case "$identities" in *'
'*) fail 'Dedicated agent contains multiple identities; refusing to change it.' ;; esac
    read -r loaded_type loaded_blob comment <<EOF
$identities
EOF
    [ "$loaded_type:$loaded_blob" = "$key_type:$key_blob" ] ||
      fail 'Dedicated agent contains an unexpected identity; refusing to change it.'
    ;;
  1) ;; # Reachable empty agent.
  *) fail 'Dedicated agent is inaccessible; no socket was removed.' ;;
esac
if ! ssh-add -t 1h "$key"; then
  fail 'Key not loaded. Rerun this helper in a host terminal for a passphrase prompt.'
fi
identities=$(ssh-add -L) || fail 'Cannot verify the loaded identity.'
case "$identities" in *'
'*) fail 'Dedicated agent now has multiple identities; do not mount it.' ;; esac
read -r loaded_type loaded_blob comment <<EOF
$identities
EOF
[ "$loaded_type:$loaded_blob" = "$key_type:$key_blob" ] ||
  fail 'Loaded identity does not match the selected public key; do not mount it.'
ssh-add -l
printf 'Dedicated GitHub agent ready at %s (key lifetime: 1 hour).\n' "$socket"

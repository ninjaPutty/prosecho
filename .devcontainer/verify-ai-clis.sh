#!/bin/sh
set -eu

# Isolate CLI state from the real home, including during image builds.
HOME=$(mktemp -d "$HOME/.ai-cli-check.XXXXXX")
export HOME
export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.local/state"
trap 'rm -rf "$HOME"' EXIT HUP INT TERM

test "$(id -un)" = vscode
test "$(node --version)" = v22.23.3
test "$(opencode --version)" = 1.18.33
test "$(codex --version)" = 'codex-cli 0.159.1'
test "$(claude --version)" = '2.1.285 (Claude Code)'
node --version
for cli in opencode codex claude; do
  command -v "$cli"
  "$cli" --version
  "$cli" --help >/dev/null 2>&1
done

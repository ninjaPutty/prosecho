# Developer SSH

Host initialization selects one optional read-only agent at
`/run/developer-ssh-agent.sock`. Private keys stay on the host; no complete home,
`.ssh` directory, or runtime control socket is mounted. Public GitHub gems do not
require authentication for ordinary setup.

This approved credential-convenience profile trusts repository code, dependencies,
and container processes with signing access to **every loaded identity**, including
approved production keys. Read-only does not prevent signing or agent protocol
operations. Use an isolated or narrowly authorized agent for untrusted work.
Initialization never loads, removes, lists, or changes identities or host SSH
configuration. Deployment and other external mutations still require approval.

## Runtime selection

Run from the host repository root:

```sh
DEVCONTAINER_RUNTIME=podman sh .devcontainer/initialize.sh
# With OrbStack running and its intended Docker context selected:
DEVCONTAINER_RUNTIME=orbstack sh .devcontainer/initialize.sh
```

Choices are `podman`, `docker`, and `orbstack`. One available engine can be
selected automatically; two real engines require an explicit choice. A Docker
command reporting Podman counts as a compatibility shim, not a second engine.
Selecting a runtime does not switch Docker contexts.

- Local Linux Podman selects the first nonempty `PROSECHO_DEV_SSH_AGENT_SOCK` or
  `SSH_AUTH_SOCK`. Both must be absolute paths to actual sockets. A missing
  explicit source never falls back. Nonempty `CONTAINER_HOST` or
  `CONTAINER_CONNECTION` suppresses all agent binds, including explicit ones.
  Use the native local CLI; silently configured remote wrappers/connections are
  outside this workflow. `CONTAINER_SSHKEY` alone does not select remote mode.
- Generic Docker requires an explicit `PROSECHO_DEV_SSH_AGENT_SOCK`. The effective
  context/host must resolve successfully to a local Unix endpoint. Remote or
  unverified endpoints omit even explicit mounts. `DOCKER_CONTEXT` takes precedence
  over `DOCKER_HOST`; otherwise the current context is discovered.
- OrbStack is selected explicitly or by Docker's selected `orbstack` context.
  Its default is the engine-side `/run/host-services/ssh-auth.sock`, not a Mac
  filesystem socket. The bridge must pass a bounded engine-side probe; naming
  a context does not establish availability. Other explicit sources require
  the local endpoint guard and an actual absolute socket.

The OrbStack probe uses only cached `prosecho-app`, `prosecho_app`, or the project's
Ruby 3.4.7 base image, pinned by validated image ID. It uses `--pull=never`,
`--network=none`, a read-only filesystem, and one read-only socket mount. It checks
socket type, not identities. Each engine call has a five-second deadline and a
one-second termination grace. Missing images or failed probes warn without
blocking the shell. Build the app image, rerun initialization, then recreate when
ready if no trusted probe image was cached initially.

Linux rootless Podman uses `keep-id:gid=100`; verify socket-owner UID mapping.
Never run the app as root or make sockets world-writable to fix access.

## Editor and readiness

Compose sets `SSH_AUTH_SOCK` to the canonical path, or explicitly empty when no
agent is mounted. VS Code forwarding is disabled and `remoteEnv.SSH_AUTH_SOCK`
inherits `${containerEnv:SSH_AUTH_SOCK}`. There is no editor fallback. Rerun host
initialization with the intended environment and recreate when ready to change
mounts; restarting or opening another terminal is insufficient. Preserve existing
OpenCode sessions first, following [OpenCode persistence](../README.md#opencode-persistence).

With RemoteSSH, initialization runs on the remote host and uses its intended
forwarded socket, not an assumed Mac/Linux desktop agent. Client forwarding
settings are not changed here. Verify the canonical path in editor and Compose
terminals after recreation; local editor settings must not re-enable forwarding.

Inside the container, check without contacting production:

```sh
printf '%s\n' "$SSH_AUTH_SOCK"
ssh-add -l
sh .devcontainer/developer-ssh-doctor.sh
# Optional explicit GitHub authentication check, not a push:
sh .devcontainer/developer-ssh-doctor.sh --github
```

An empty agent can mount successfully but cannot authenticate. Key loading is an
explicit host operation using the actual existing key, never lifecycle automation.
A stale/replaced socket requires recreation; scripts do not repair host agents.

## Isolation and trust

The existing Linux-only one-hour GitHub agent helper remains opt-in:

```sh
export PROSECHO_DEV_SSH_AGENT_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/prosecho-dev-agent.sock"
sh .devcontainer/start-ssh-agent.sh
DEVCONTAINER_RUNTIME=podman sh .devcontainer/initialize.sh
```

It defaults to `$HOME/.ssh/id_ed25519`; an argument can select another GitHub
Ed25519 key with a matching public file. It refuses unexpected/multiple identities
and requires an existing user-owned mode-700 parent and mode-600 socket. Never
point it at a shared/deployment agent. To remove its mount, unset the override
and ensure `SSH_AUTH_SOCK` does not select it, then reinitialize and recreate.
Do not clear or stop a shared agent.

Agent sharing does not globally set `GIT_SSH_COMMAND`. Production helpers retain
their public identity selector, strict host pin, and disabled onward forwarding;
see [Deployment](deployment.md). For intentionally GitHub-only Git operations:

```sh
GIT_SSH_COMMAND='sh /prosecho/.devcontainer/git-ssh.sh' git fetch
```

The wrapper ignores user/system SSH config, enforces the committed Ed25519 pin,
and rejects other destinations. GitHub's published fingerprint is
`SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`.
Never accept blind `ssh-keyscan` output or disable host checking. HTTPS remotes
do not use the agent. The manual `compose.developer-ssh.yaml` remains an opt-in
GitHub-only override; do not combine it with a generated agent mount. An optional
public selector at `/run/prosecho-github.pub` with `PROSECHO_DEV_SSH_PUBLIC_KEY`
limits that client, not other processes' access. Never mount private keys.

## Verification

Run `python3 .devcontainer/test_initialize.py` and
`python3 .devcontainer/test_start_ssh_agent.py` on the host, and
`ruby .devcontainer/test-developer-ssh.rb` inside `app`. They use stub engines and
disposable sockets/keys, with no external authentication or pushes. Configuration
tests do not establish live macOS, RemoteSSH, editor precedence, Windows/Pageant,
or successful migration. Verify those separately after scheduled recreation.

References: [OrbStack bridge](https://docs.orbstack.dev/docker/#ssh-agent-forwarding),
[VS Code environment](https://code.visualstudio.com/remote/advancedcontainers/environment-variables),
[GitHub fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).

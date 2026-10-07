# Developer SSH

VS Code-managed host SSH agent forwarding is the default for the ordinary `app`
container (`dev.containers.forwardSSHAgent: true`). The user explicitly approves
making the production deployment identity available alongside other loaded keys
to this trusted container. No per-key configuration or isolated-agent mount is
required. No private keys, host home, complete `.ssh` directory, or container-runtime
socket are mounted. Private keys remain on the host; the agent answers signing requests.
The public GitHub gems do not require authentication for ordinary setup.

## VS Code default: Linux, macOS, and RemoteSSH

Load any required identity once into the agent used by the VS Code client, in a
host terminal, using the actual existing key path:

```sh
ssh-add /absolute/path/to/existing/key
ssh-add -l
```

On macOS, Apple's `ssh-add` supports explicitly storing the passphrase in Keychain:

```sh
ssh-add --apple-use-keychain /absolute/path/to/existing/key
```

This is an optional host command, not lifecycle automation. Loading a key does not
remove other identities or isolate the agent. Do not copy private keys into the
checkout or container. No Mac Keychain or host SSH configuration is changed by
these scripts.

For a local Linux window, forwarding uses the agent available to that Linux VS Code
client. For a local Mac/OrbStack window, it uses the Mac client's agent. With
VS Code RemoteSSH from a Mac to Linux, the source is the Mac client's agent forwarded
over the RemoteSSH connection when agent forwarding is enabled there, not
automatically Linux's desktop GCR agent. Confirm which identities reach the remote
host and container rather than assuming the same source in all three workflows.
RemoteSSH forwarding must be enabled for the intended trusted host in the client;
this repository does not modify client SSH or unrelated host configurations.

VS Code must inherit a usable agent environment. On the current Linux host the
production identity was already loaded in `/run/user/1000/gcr/ssh`, but the tool
environment had no `SSH_AUTH_SOCK`. If the VS Code client has the same gap, launch
it from a host terminal with the intended agent environment, for example:

```sh
SSH_AUTH_SOCK=/run/user/1000/gcr/ssh code .
```

Ensure the VS Code process handling the window actually inherits that environment;
an already-running client may require exiting and relaunching. This does not load
or change keys. Forwarded sockets are session-scoped: reconnect the Dev Container
when ready; the current container may also need recreation to refresh metadata
that still records forwarding disabled. Restarting alone does not update mounts
or guarantee new forwarding metadata. No active container is recreated automatically.

Inside the reconnected container, check without contacting production:

```sh
printf '%s\n' "$SSH_AUTH_SOCK"
ssh-add -l
sh .devcontainer/developer-ssh-doctor.sh
```

The VS Code lifecycle, Mac Keychain, and RemoteSSH forwarding have **not yet been
verified** here. A setting of `true` expresses the intended default, not proof that
the current session is forwarded. Plain Compose terminals do not receive VS Code's
session forwarding; use an explicit socket or bridge below for those workflows.

## Manual macOS ARM64 / OrbStack bridge

Run from the repository root on the Mac, with OrbStack running. Confirm
`docker context show` reports `orbstack`. Check the host agent with `ssh-add -l`.
If necessary, explicitly load your GitHub development key on the host:

```sh
ssh-add -t 1h "$HOME/.ssh/id_ed25519_github"
```

That filename is an example; use your existing GitHub key. Loading it into an
existing agent does **not** remove other identities or isolate the agent. The bridge
can also expose loaded production identities; use it only with explicit trust.
Register the development key's public half with your GitHub account if needed;
never copy the private half into the checkout or container.

[OrbStack's official instructions](https://docs.orbstack.dev/docker/#ssh-agent-forwarding)
specify `/run/host-services/ssh-auth.sock`. This is an engine-side bridge, not a
socket that must exist in the Mac filesystem. Do not substitute Docker's daemon
socket. OrbStack also documents `$SSH_AUTH_SOCK` mounts in most cases, excluding
1Password's agent; the canonical bridge below is the recommended starting point.

```sh
unset PROSECHO_DEV_SSH_AGENT_SOCK
DEVCONTAINER_RUNTIME=orbstack sh .devcontainer/initialize.sh
export PROSECHO_DEV_SSH_AGENT_SOCK=/run/host-services/ssh-auth.sock
devcompose() {
  docker compose -p prosecho \
    -f .devcontainer/compose.yaml \
    -f .devcontainer/compose.runtime.yaml \
    -f .devcontainer/compose.developer-ssh.yaml "$@"
}
devcompose up -d
devcompose exec app sh .devcontainer/developer-ssh-doctor.sh
# Explicit network/authentication probe, not a push:
devcompose exec app sh .devcontainer/developer-ssh-doctor.sh --github
devcompose exec app git remote -v
```

This starts both `app` and local PostgreSQL by default, without a database profile.
The overlay sets `SSH_AUTH_SOCK` and `GIT_SSH_COMMAND` only
on `app`. It does not change Git configuration, remotes, commit history, or
deployment services. Use the same overlay for subsequent Compose invocations.

For Git operations use the existing SSH remote, such as
`git@github.com:OWNER/REPOSITORY.git`. HTTPS remotes do not use the SSH agent.
Inspect the remote first; change it only deliberately. A successful doctor probe
confirms account authentication, **not** write authorization to this repository.
Run `git push` only when the intended branch and changes have been approved.

To remove this manual mount, recreate `app` without the optional overlay (no image
rebuild or database-volume deletion). This does not disable separate VS Code forwarding:

```sh
docker compose -p prosecho \
  -f .devcontainer/compose.yaml \
  -f .devcontainer/compose.runtime.yaml up -d --force-recreate app
unset PROSECHO_DEV_SSH_AGENT_SOCK
unset -f devcompose
```

## Optional isolated Linux / rootless Podman agent

Opt in by starting the dedicated GitHub-only host agent before reopening the
Dev Container. The helper is an explicit host login operation, not lifecycle
automation; it may prompt for a passphrase in your host terminal:

```sh
export PROSECHO_DEV_SSH_AGENT_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/prosecho-dev-agent.sock"
sh .devcontainer/start-ssh-agent.sh
# Or explicitly select another GitHub Ed25519 key with its matching .pub file:
# sh .devcontainer/start-ssh-agent.sh "$HOME/.ssh/id_ed25519_github"
DEVCONTAINER_RUNTIME=podman sh .devcontainer/initialize.sh
# Reopen/recreate the Dev Container when ready; this ends the current session.
# Then inside app:
sh .devcontainer/developer-ssh-doctor.sh
sh .devcontainer/developer-ssh-doctor.sh --github
```

The default key is `$HOME/.ssh/id_ed25519`. Its identity is checked against the
host `.pub` file before and after loading; no private or public key is mounted or
copied into the image. The key expires after **one hour**. Rerun the helper to
reload it without replacing the socket or recreating the container. A failed
noninteractive load leaves an empty agent and reports the host-terminal command;
there is no fallback to the desktop agent.

The stable socket is `${XDG_RUNTIME_DIR}/prosecho-dev-agent.sock`, falling back
to `/run/user/$(id -u)/prosecho-dev-agent.sock` on Linux. On this host that is
`/run/user/1000/prosecho-dev-agent.sock`. The helper uses this default; initialization
requires an explicitly nonempty `PROSECHO_DEV_SSH_AGENT_SOCK`, as above. Set the
same absolute path for the helper and host initialization. Its parent must already
exist, belong to you, and have mode 700; an existing socket must belong to you and
have mode 600. The helper
never creates directories, replaces stale sockets, removes
keys, or touches the shared `SSH_AUTH_SOCK` (including the desktop GCR agent).
An existing agent with multiple or unexpected identities is refused unchanged.
When running this isolated helper, do not point its override at any shared or
deployment agent; the helper remains a finite, one-key GitHub-only alternative.

Initialization ignores dedicated and shared sockets when the variable is unset
or empty, without an agent warning or an instruction to run the isolated helper.
Only an explicit path is checked as a socket (`-S`). If present, it generates the
read-only bind and GitHub wrapper environment for
`app` in `compose.runtime.yaml`, alongside any optional logs in one volumes
list. A missing explicit socket or regular file produces an optional warning, no SSH
environment or mount, and no directory creation; the development shell still
opens. It never selects the arbitrary host `$SSH_AUTH_SOCK`. Initialization does
not authenticate or validate loaded identities: verify `ssh-add -l` against the
selected `.pub` fingerprint before mounting an independently supplied socket.
An explicit mount sets `SSH_AUTH_SOCK` in Compose; VS Code startup can set its own
forwarded environment, so do not assume which socket wins in an attached terminal.
Inspect `SSH_AUTH_SOCK` and `ssh-add -l`; avoid combining the two mechanisms.
The manual `compose.developer-ssh.yaml` remains available for explicit bridges
such as OrbStack; it is not automatically included and requires its variable.
Do not combine that overlay with a generated dedicated-agent mount.

Rootless `keep-id:gid=100` must preserve the socket owner's UID. If the socket
cannot be used, inspect host/container `id`, socket ownership, and selected
runtime. Do not run the app as root or make the socket world-writable. This is
the standard GID-100 Linux mapping, not a macOS Podman support claim.

To immediately remove signing access, explicitly clear **only** this dedicated
agent with `SSH_AUTH_SOCK=/run/user/1000/prosecho-dev-agent.sock ssh-add -D`
(substitute your actual dedicated path). Never run this against the shared agent.
The empty socket can remain mounted, but authentication is unavailable. To remove
the mount too, unset `PROSECHO_DEV_SSH_AGENT_SOCK`, rerun initialization, and recreate
`app` when ready. Stop the dedicated agent using its independently verified PID
if it is no longer needed. Separate VS Code forwarding can still provide access.
A restarted agent/socket requires recreating the bind mount; stale sockets are
not repaired automatically. Restarting the container does not update its mounts.
The helper targets Linux with GNU `stat`; macOS/OrbStack isolation is not verified
by this helper, and requires the explicit bridge workflow above.

## Host trust and identity

Production helpers (`bin/prod/ssh`, `shell`, `runner`, and `console`) use the
forwarded production identity through `ssh-prosecho.menloparking.com` and
`cloudflared`. `ssh` connects to the host; `shell` connects to the app container.
See [production session setup](deployment.md#production-shell-runner-and-console)
for the verified binary installer and committed production host-key pin.
This hostname requires no Cloudflare browser login or Access service token;
SSH key authentication still uses the forwarded agent. The production client
disables onward agent forwarding and clears inherited Access token variables.

The explicit mount's Git wrapper uses `.devcontainer/ssh.git`, ignoring user/system
SSH configuration. It requires strict verification against the committed public
`git_github_known_hosts`, pins GitHub's Ed25519 host key, disables remote
`ForwardAgent`, and rejects other destinations via `ProxyCommand false`.
The manual bind is host socket sharing. The VS Code RemoteSSH workflow may also
involve an SSH forwarding hop before the agent reaches the container.

The host key was retrieved from the public [GitHub metadata API](https://api.github.com/meta)
on 2026-09-29 and cross-checked against
[GitHub's published fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints):

```text
SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU
```

On host-key change, stop and independently verify official GitHub publications
before updating this public file. Never accept blind `ssh-keyscan` output, turn
off host checking, or silently fall back to another host/port. Port 443 and
GitHub Enterprise need separately reviewed trust/configuration.

Without explicit identity selection, SSH offers the agent's loaded identities.
Prefer a GitHub-only agent to avoid wrong-account authentication or too many
identities. If needed, bind-mount **only** a user-supplied `.pub` file read-only
at `/run/prosecho-github.pub` using a local additional Compose overlay, then set
`PROSECHO_DEV_SSH_PUBLIC_KEY=/run/prosecho-github.pub` on `app`. The Git wrapper
uses `IdentitiesOnly=yes` for that public file; the private key remains in the
host agent. This selects the key for this client, but does not limit what other
container processes can request from the shared agent.

For example, keep this additional overlay outside the checkout, replace the
source with the absolute path to your **public** key, and add it after the
developer SSH overlay in your Compose command:

```yaml
services:
  app:
    environment:
      PROSECHO_DEV_SSH_PUBLIC_KEY: /run/prosecho-github.pub
    volumes:
      - type: bind
        source: /absolute/host/path/id_ed25519_github.pub
        target: /run/prosecho-github.pub
        read_only: true
        bind:
          create_host_path: false
```

## Editor behavior and security

[VS Code Dev Containers](https://code.visualstudio.com/remote/advancedcontainers/sharing-git-credentials)
forwards a running client SSH agent automatically; the repository enables it.
Avoid adding a second mount merely for editor convenience. For pinned GitHub trust
with the forwarded socket, explicitly use
`GIT_SSH_COMMAND='sh /prosecho/.devcontainer/git-ssh.sh'`. The wrapper is GitHub-only;
do not use it for production SSH. Forwarding itself needs no per-key selection.

For an isolated or credential-free editor session, disable forwarding in **local
VS Code user settings before opening the container**, remove manual agent mounts,
and verify the resulting environment. Other editor Git credential helpers can
separately grant access. Editor lifecycle enforcement has not been tested here;
no host editor settings are changed by these scripts.

Every trusted process in `app`, including repository scripts, dependencies, and
coding agents, can ask the forwarded or mounted agent to sign as **any loaded identity**,
including the user-approved production deployment key.
Read-only mounting does not prevent signing or agent protocol operations. The
SSH client configuration is not a sandbox against malicious code using its own
client. Account-authorized Git pushes and other SSH actions are possible while
the socket is shared. Use a narrowly authorized development key, a short agent
lifetime, and preferably an isolated agent. The OrbStack bridge may expose the
Mac's existing agent identities; do not assume a fresh shell agent changes the
bridge's backing agent. Custom isolated-agent bridging needs runtime verification.
Forwarding production identities is an explicit trust decision for this container,
not isolation. Do not forward them into untrusted repositories or containers.

PuTTY/Pageant on Windows is not this tested socket protocol/runtime path. Do not
copy `.ppk` files into the container or claim Windows support from these commands.
Host key loading and passphrase prompts remain host-side.

## Verification scope

Run `python3 .devcontainer/test_initialize.py` and
`python3 .devcontainer/test_start_ssh_agent.py` on the Linux host. These hermetic
tests cover explicit sockets present/absent/non-socket, default ignoring dedicated
and shared sockets (including an empty override), no shared-agent fallback,
optional logs without directory creation, combined mounts, explicit path escaping,
finite key loading, and refusal to modify unexpected/multiple/shared identities.
The helper tests use disposable local keys and agents, never GitHub or real keys.

Run `ruby .devcontainer/test-developer-ssh.rb` inside `app`.
It checks missing/empty/inaccessible agents, command construction, key selection,
GitHub's special success exit status, strict trust, and the default/optional
configuration without external authentication. No test pushes or alters a remote.

On 2026-10-07, the VS Code-default change passed 21 host initialization tests,
3 isolated-agent helper tests, and 5 tests / 58 assertions inside the existing
`app`. JSON parsing confirmed forwarding enabled; shell syntax and diff whitespace
checks passed. No active container was recreated, production connection attempted,
host agent keys changed, or Mac/RemoteSSH configuration modified. Live VS Code
forwarding remains unverified until reconnect and inspection of the session socket.

On 2026-10-05, the host suites passed 12 initialization tests and 3 helper tests;
the existing `app` passed 5 Minitest tests / 58 assertions. Shell syntax and
Podman Compose config passed with both logs and dedicated-agent mounts. A
disposable container using the active development image, unprivileged `vscode`,
`keep-id:gid=100`, and only a read-only dedicated socket listed exactly the
approved GitHub development fingerprint. No image was pulled or active container
recreated. A separate read-only GitHub probe with only the `.devcontainer`
directory additionally mounted verified GitHub's pinned host key and offered the
development identity, but GitHub rejected it with `Permission denied (publickey)`.
This establishes socket passthrough, **not** successful GitHub account access;
register/confirm that public key in the intended GitHub account before retrying.
No host trust, remote, shared agent, production connection, or Git history changed.

On 2026-09-29, the Minitest suite passed inside the existing Linux development
container: 5 tests, 58 assertions, no failures. The host-side
`sh .devcontainer/test-developer-ssh-runtime.sh` also passed on Linux x86_64
rootless Podman 5.8.6 with podman-compose 1.6.0: a one-off `app` service using the actual
overlay listed a disposable host-agent identity and `ssh-add -T` successfully
requested and verified a signature. Only the public fixture identity was mounted;
the disposable private key stayed in the host temporary directory, removed along
with its dedicated agent afterward. No existing app/database was recreated and no
GitHub authentication or push was attempted. Compose parsing without the explicit
socket variable failed as intended. The live test assumes initialization has
already generated the Linux Podman runtime overlay and the app image is built.

macOS ARM64 / OrbStack and the editor lifecycle are not independently verified
by the earlier MacBook report. Official path documentation establishes the
intended mount, not local success. Missing-source rejection via
`create_host_path: false` is declared but was not exercised on OrbStack.

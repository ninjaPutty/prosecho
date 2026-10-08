# Prosecho

Local Rails 8.1 / Ruby 3.4 / PostgreSQL / Phlex 2 / Tailwind CSS 4 starter, formatted with Standard
Ruby and tested with Minitest (not RSpec). The root page is public. Staff sign-in uses Devise with
Argon2id. Visit `/admin` for first-account setup, then administrator-only account/campus management.
The private `/dashboard` is the pastoral workspace with campus-scoped local people, filters,
portraits, and details. ActiveJob uses Solid Queue for explicit directory refreshes and a
network-free recurring readiness check. See [Phase 0 foundations](docs/phase-0-foundations.md) for
operation and pending gates.

Use **Fetch campuses from Rock** on `/admin` to populate campus records without manual names/IDs. It
uses the read-only adapter and preserves local staff grants. The local server's expressly enabled
integration holds a process-only runtime Rock key; normal container credential mounts and
configuration are unchanged.

Use **Data decisions** on `/admin` (or `/admin/data_policy`) to save retention periods,
source/interpretation rules, the initial field allowlist, and custom attribute keys. Drafts can be
saved before recording complete agreed decisions. These are persisted settings; no YAML editing is
needed for routine data-policy administration, and saving them does not start a live sync or
cleanup.

The Phase 1 [person-read pipeline](docs/phase-1-person-pipeline.md) provides policy-gated,
campus-scoped paginated Rock reads and immutable normalized person values. The
[persisted pastoral workspace](docs/phase-1-pastoral-workspace.md) adds local projection refreshes,
a filtered directory, and approved person details.

## Development

Open the repository folder (the root containing this README and `.devcontainer/`)
as a Dev Container workspace. The local checkout is `~/Church/prosecho/src`,
mounted at `/prosecho` inside the container. The host layout is:

```text
~/Church/prosecho/
  src/          # Repository, including .git and .devcontainer
  work logs/    # Optional sibling directory, outside the repository
```

Initialization mounts the existing sibling `work logs` directory read-write at
`/work-logs`, outside the container workspace. Trusted container processes can
read and modify those logs. If the directory is absent, no logs mount is generated
and neither a host logs directory nor a container `/work-logs` directory is created.
The long bind syntax uses `create_host_path: false`; the Compose provider must
support it so a source removed after initialization fails rather than being created.
Rerun initialization from the host repository root after adding or removing the
directory to refresh the overlay and generated `.devcontainer/prosecho.code-workspace`.

On attachment, before dependency/database readiness checks, the container creates
`/prosecho/work logs` as a symlink to `/work-logs` only when that directory exists.
Work logs then appear alongside the app files in the standard VS Code Explorer;
no multi-root workspace is required. The repository bind also writes this symlink
into the host checkout, where it is gitignored and may be dangling because its
absolute target is container-only. Host initialization never creates the link.
No placeholder directory is created. Repeated attachments preserve the exact
managed link; if the mount is absent, attachment removes only a symlink whose
target is exactly `/work-logs`. Files, real directories, and unrelated symlinks
at `work logs` are preserved with a warning, without blocking the shell.

The optional multi-root workspace remains available: first reopen the host `src`
folder in the Dev Container, then use **File > Open Workspace from File...** to open
`/prosecho/.devcontainer/prosecho.code-workspace`. Its folders are **Prosecho**
(`/prosecho`) and, only when the sibling directory existed at initialization,
**Work Logs** (`/work-logs`). Missing host logs produce no generated logs entry,
mount, directory, or new repository symlink. Each initialization overwrites the
generated workspace, removing a stale logs entry when the host directory is absent.

The [Dev Containers schema](https://raw.githubusercontent.com/devcontainers/spec/main/schemas/devContainer.base.schema.json)
and CLI configuration types do not define a `workspaceFile` property;
`workspaceFolder` stays `/prosecho` for startup and lifecycle working directories.
The generated file is not automatically opened on first attachment. Open it only
inside the attached window, not as a host workspace (its paths are container paths).
This changes the editor workspace on the same remote connection, not the host
checkout root or Compose sources. After adding/removing logs, recreate the
Dev Container when ready to apply mount changes, then reopen the generated workspace
if Explorer has not refreshed. Restarting alone does not update mounts; opening
the workspace alone does not apply them either. No active session is recreated
by the initializer.

After relocating an existing checkout, reopen `~/Church/prosecho/src` and recreate
the Dev Container to apply the new bind sources. The old container still binds
the parent directory at `/prosecho`; restarting it does not update its mounts.

On Linux rootless Podman set
`DEVCONTAINER_RUNTIME=podman` before opening it; the Podman Compose provider
must support `--in-pod false`. Compose uses project `prosecho`; if invoking it
manually, always pass `-p prosecho -f .devcontainer/compose.yaml -f
.devcontainer/compose.runtime.yaml`. The app is bound to host
`127.0.0.1:3100` (container port 3000). Development mounts this repository,
optional sibling logs, persistent OpenCode data/cache, and the host OpenCode
secrets file when present (see [Agent Tools](#agent-tools)). No complete host home
or container-runtime socket is mounted. VS Code-managed SSH agent forwarding is
enabled by default: trusted container processes can sign with every loaded host
identity, including the user-approved production deployment key. Private keys
remain on the host. The container can access public networks; source code,
dependencies, and coding agents must be trusted within that credential boundary.
Kamal deployment runs from the ordinary devcontainer with the optional
[credential overlay](docs/deployment.md); forwarding does not invoke deployment.
Linux x86_64 rootless Podman is locally tested. macOS ARM64 with OrbStack's
Docker runtime has a user-supplied development workflow report, not independent
verification here; see [Local Verification](#local-verification) for scope.

For Linux, macOS/OrbStack, and VS Code RemoteSSH agent forwarding, see
[Developer SSH](docs/developer-ssh.md). No per-key configuration or manual socket
mount is required for the VS Code default. The forwarding source depends on the
VS Code connection and client agent environment; it has not yet been verified
in the current session. Reconnect when ready, possibly recreating the container
to refresh its old forwarding setting. The Linux GitHub-only one-hour agent helper
and manual Compose/OrbStack bridge remain opt-in alternatives. Initialization
mounts an agent only when `PROSECHO_DEV_SSH_AGENT_SOCK` is explicitly nonempty and
names an existing socket; it never autodetects a dedicated or shared agent.

The Dev Container starts both `app` and local PostgreSQL by default; no database
profile is required. The shell does not wait for database health or installed gems.
Post-create runs
`sh .devcontainer/setup.sh --automatic`: it requires `Gemfile.lock`, checks the
frozen bundle, installs missing locked dependencies, and prepares the local
development/test databases when PostgreSQL responds. It never updates the lockfile.
If only PostgreSQL is unavailable, automatic setup reports database setup pending
and succeeds, preserving a usable shell. If the local database is stopped or an
existing app session did not start it, recover it from the host:

```sh
podman-compose -p prosecho -f .devcontainer/compose.yaml -f .devcontainer/compose.runtime.yaml up -d postgres
```

For Docker/OrbStack replace `podman-compose` with `docker compose`. Then in the
container run `sh .devcontainer/setup.sh` to resume. Manual setup is strict:
an unavailable database returns failure. Missing lockfiles, failed dependency
installs, authentication errors, probe errors, and failed `db:prepare` return
failure in both modes; they are not reported as optional database gates. Setup
requires development mode and rejects `DATABASE_URL` overrides. Use only the
local development cluster, never production connection settings.

Post-attach checks the frozen bundle and current development database connection
and pending migrations without installing dependencies or migrating. It reports
readiness or the needed resumption step; optional checks do not block attachment.
Run `ruby .devcontainer/test-setup.rb` inside `app` for hermetic lifecycle regressions.
Then run `bin/check` (frozen bundle check, Standard Ruby, Minitest),
and `bin/rails server -b 0.0.0.0`. A stale `tmp/devcontainer-setup.lock`
needs manual inspection before removal. The lockfile pins Lookbook 2.3.15 and
lookbook_theme v0.1.1. All three pinned GitHub gems (Carnet, Turnstile, and
lookbook_theme) were confirmed public; no credential forwarding is needed.
Do not add access tokens to the repository or container image.

Development Puma starts Solid Queue workers alongside the web server. Supply the approved Rock key
to the server's runtime process for directory reads; a container restart loses process-only key
configuration. Production uses a separate job role. See the
[workspace runtime notes](docs/phase-1-pastoral-workspace.md#runtime-and-verification).
Refreshes save complete pages and resume interrupted work automatically. The Resume/check refresh
button reconnects the existing run; progress updates while the workspace is visible.

### macOS ARM64 / OrbStack

With OrbStack running and its Docker context selected, run these commands from
the repository root on the host. This is the development-only Compose workflow
covered by the user report, not a verified editor Dev Container lifecycle:

```sh
DEVCONTAINER_RUNTIME=orbstack sh .devcontainer/initialize.sh
docker compose -p prosecho -f .devcontainer/compose.yaml -f .devcontainer/compose.runtime.yaml build app
docker compose -p prosecho -f .devcontainer/compose.yaml -f .devcontainer/compose.runtime.yaml up -d
docker compose -p prosecho -f .devcontainer/compose.yaml -f .devcontainer/compose.runtime.yaml exec app sh .devcontainer/setup.sh
docker compose -p prosecho -f .devcontainer/compose.yaml -f .devcontainer/compose.runtime.yaml exec app bin/check
docker compose -p prosecho -f .devcontainer/compose.yaml -f .devcontainer/compose.runtime.yaml exec app bin/rails server -b 0.0.0.0
```

The `app` service runs `sleep infinity`; `up -d` does not start Rails. The last
command starts Rails separately in the foreground. Visit
`http://127.0.0.1:3100` after it starts. Initialization generates the runtime
overlay for OrbStack's Docker runtime; no deployment overlay is used.

Lookbook is mounted at `/lookbook` in development only. The deterministic
landing scenario is at `/lookbook/inspect/landing/default`, with its iframe at
`/lookbook/preview/landing/default.html`. It renders the same Phlex landing
component as `/` inside an app-owned Phlex preview layout; the tiny ERB layout
adapter is needed by Lookbook's Rails renderer. The preview loads the same
compiled Tailwind stylesheet as the public page. Lookbook theme styles only
its inspector chrome, not the iframe. Tailwind CSS 4 is provided by
`tailwindcss-rails` without a Node toolchain. The source is
`app/assets/tailwind/application.css`; `bin/rails tailwindcss:build` generates
`app/assets/builds/tailwind.css`. The development Puma plugin watches for CSS and Phlex class
changes after a server restart; asset precompilation builds the production stylesheet. Lucide
provides workspace icons. MenloUI is not installed, and no private gem access is assumed.

The runtime overlay is generated by `.devcontainer/initialize.sh`.
Rebuilds retain the PostgreSQL named volume and source tree. The cached Ruby
base image is versioned `3.4.7`. No production schema or deployment claim is
made.

## Agent Tools

The development image includes pinned Docker CLI 28.5.2 / Buildx 0.29.1 for
Kamal's remote-VM builder; no workstation Docker socket is mounted. The user
SSH config selects the committed production identity and strictly verified host
pin. The optional deployment credential overlay grants `app` access to runtime
secrets and production Docker through SSH as documented in
[Deployment](docs/deployment.md). Rebuild to acquire these image additions.

The development image includes pinned `opencode` 1.18.33, `codex` 0.159.1,
and `claude` 2.1.285, available to the unprivileged `vscode` user. Run
`verify-ai-clis` to check their versions. Rebuild the image to install them;
the already-running container does not acquire tools from a changed Dockerfile.
Their version/help checks passed on Linux x86_64 without network or credentials.
The MacBook report predates these additions; repeat these checks on ARM64.
Installation does not establish login, model access, or a successful agent run.

`AGENTS.md` and `CLAUDE.md` are small launchers for the canonical MP Drive
AGENTS document. Read its relevant linked guidance before working. Keep the
shared rules in Drive rather than copying them into this repository.

Host initialization mounts `${HOME}/.config/opencode/secrets.env` read-only at
`/home/vscode/.config/opencode/secrets.env` on `app` only when it is a regular
file. A missing file or directory at that path produces an optional warning,
no mount, and no host file/directory or placeholder credentials. Only the file
is mounted, never the host OpenCode config directory; secrets are not built into the image.
The bind uses `create_host_path: false` so a removed source fails at creation.
Rerun initialization after adding/removing the file and recreate `app` when
ready; restarting does not update mounts. The image pre-creates its target parent.

This is an accepted convenience-over-isolation choice: repository code,
dependencies, and agent commands must be trusted. Every container process with
file access can read the tokens and act as the host user within their scopes,
including infrastructure, financial, or production API actions if authorized.
Read-only prevents file writes, not credential use. Use lower-privilege host
credentials or omit the source for untrusted work; external mutations still
require approval. Protect the host file with mode 600 and a private parent.

For a narrower Drive-only alternative, set `PROSECHO_AGENT_SECRETS_FILE` to an
existing dedicated file outside the checkout and add
`.devcontainer/compose.agents.yaml` after the runtime overlay; it replaces the
mount at the same target. Codex and Claude login/state remain separate and are
not mounted; OpenCode's shared data includes authentication as described below.
Without approved Drive access, the launcher reports a blocker instead of
dumping secrets or bypassing the guidance.

### OpenCode persistence

Host initialization creates and mounts these two directories read-write on `app`,
using the same host sources as Mixdown and Rhythm:

| Host source                     | Container target                     | Purpose                     |
| ------------------------------- | ------------------------------------ | --------------------------- |
| `${HOME}/.local/share/opencode` | `/home/vscode/.local/share/opencode` | Sessions and authentication |
| `${HOME}/.cache/opencode`       | `/home/vscode/.cache/opencode`       | Model and package cache     |

The generated runtime overlay contains one volumes list for state and optional
logs, SSH, and secrets. State binds use `create_host_path: false`; initialization
creates only the declared state sources, not missing optional logs or secrets.
Existing state is not cleared, copied, or re-owned. The image pre-creates
`vscode`-owned target parents. The whole host `.config/opencode` directory is not
shared, even read-only: session persistence does not require host provider/MCP
configuration. Unlike Mixdown/Rhythm, `.opencode` is not mounted because the image
installs the binary at `/usr/local/bin/opencode` and this workflow does not use
that runtime directory.

This user-approved session-sharing convenience also exposes authentication such
as `auth.json` within the writable data directory. Trusted container processes
can read, change, or delete host sessions and authentication, including state used
by other projects, and use provider credentials as the host user within their
scopes. Cache contents can also be modified. The separate `secrets.env` mount
remains read-only with no overlapping config-directory bind. Read-only secrets
do not prevent credential use; external mutations still require approval. For
untrusted work, use a separate lower-privilege host home/state or deliberately
omit these state binds from the generated overlay before creating the container.

Sessions written to the shared data directory at the stable `/prosecho` workspace
survive subsequent rebuilds/recreations. Host-checkout sessions may not appear in
the container's default list because its absolute workspace path differs from
`~/Church/prosecho/src`; use session tooling to select the relevant path/session.
No host-path symlink or automatic session migration is performed.

Rerun `DEVCONTAINER_RUNTIME=podman sh .devcontainer/initialize.sh` from the host
repository root (use `docker` or `orbstack` for those runtimes), then rebuild and
recreate the Dev Container when ready. Restarting does not apply new mounts.
Sessions already stored only in an existing container's private data directory
are not automatically transferred; preserve/export any needed sessions before
recreation. Initialization never recreates or restarts the live container.

## Local Verification

On 2026-10-07, the optional Explorer symlink passed hermetic container lifecycle
tests (18 tests / 363 assertions), including absent/non-directory mounts, repeated
attachment, stale managed-link removal, preservation of conflicting paths, script
location independent of cwd, and usable attachment after a link failure. The host
initialization suite passed 22 tests; Standard Ruby, shell syntax, and diff
whitespace checks passed. Only the link helper was run against the live mount,
verifying `/prosecho/work logs` points to the existing `/work-logs` directory.
The host checkout reflects that symlink; Git confirmed it is ignored only at the
repository root and is not tracked. No database preparation, image rebuild,
container recreation/restart, or commit was performed. The live VS Code Explorer
UI and other runtimes were not tested.

On 2026-10-07, OpenCode persistence passed 19 hermetic host initialization tests
and the 3-test SSH-agent suite. Coverage includes declared source creation,
existing-state preservation and repeated initialization, escaped home paths,
one volumes list, and absent optional logs/secrets remaining absent. The existing
container passed lifecycle tests (10 tests / 179 assertions) and SSH tests
(5 tests / 58 assertions). Shell syntax, JSON parsing, diff whitespace checks,
and Podman Compose config passed. `bin/check` passed frozen-bundle and Standard
Ruby checks but Rails tests were blocked because `postgres` did not resolve;
no database was started or repaired. Read-only inspection found zero sessions
in the container-private database and no active host data/cache binds. No secrets
content was printed, image rebuilt, container restarted/recreated, or live
persistence claimed. Apply the new mounts by rebuilding/recreating when ready.

On 2026-10-07, the workspace generation regressions passed in the 18-test host
initialization suite: Prosecho always present, logs present/absent/non-directory,
stale logs removal with other optional mounts retained, and no phantom directories
or repository links. The 3-test SSH-agent suite, shell syntax, JSON parsing, diff
whitespace checks, and Podman Compose config passed. The generated local workspace
contains both folders because the host logs directory exists. No container was
recreated or restarted; automatic workspace opening and the live VS Code UI were
not tested. Startup remains a folder attachment with a manual remote workspace open.

On 2026-10-07, host initialization tests passed (16 tests), including optional
OpenCode secrets present/absent/directory, removed-source refresh, combined mounts,
and paths with spaces, quotes, and dollar signs. The SSH-agent host suite passed
(3 tests); shell syntax, diff whitespace checks, and Podman Compose config passed.
The active container already has a `vscode`-owned mode-700 target parent. No image
was rebuilt or container recreated; the new secrets bind was not exercised live.

On Linux x86_64 rootless Podman, initialization, Compose build/start, frozen
`bundle install`, and `db:prepare` succeeded with no credentials. `bin/check`
passed at initial setup; the earlier automatic post-create only reported shell
readiness. The current setup installs missing locked gems and prepares available
local databases. Live HTTP requests returned 200 for `/`,
`/lookbook`, `/lookbook/inspect/landing/default`, the preview iframe, its
fingerprinted CSS, and Lookbook theme CSS. The iframe HTML contained one
document, the landing heading, and the compiled Tailwind stylesheet. Restart
any development server started before the Tailwind install to refresh its asset
load path. No browser visual test or other OS/runtime test was run locally.
Cloudflare SSH access is active; public HTTP routing is deferred. The application
is not yet deployed to the Beelink VM. No production-host verification was
performed as part of these agent-tool and documentation changes.

On 2026-10-05, inside the existing Linux Podman `app` container with PostgreSQL
already running, `setup.sh --automatic` completed database preparation and
`post-attach.sh` reported current readiness. The hermetic lifecycle suite passed
10 tests / 179 assertions; `bin/check` passed 26 tests / 165 assertions. Missing
dependencies, failed installs, unavailable databases, authentication/migration
errors, locking, and post-attach readiness were exercised with isolated mocks.
No containers were restarted or recreated and no volumes or profiles changed.
This was not a clean-creation, editor-lifecycle, or cross-runtime verification.

After relocating the checkout to `~/Church/prosecho/src`, host initialization
tests passed (9 tests), covering optional logs present, absent, and removed after
initialization for Docker, OrbStack, and Podman, including paths with spaces.
Shell syntax and `podman compose config` passed with Podman 5.8.6 and
podman-compose 1.6.0; the installed provider implements missing-source rejection
for `create_host_path: false`. The existing container still mounted the parent,
so lifecycle checks and `bin/check` were rerun at `/prosecho/src` with the same
passing counts above. No container was recreated; the new live workspace/logs
mounts and Docker/OrbStack runtime behavior were not exercised.

### Portability Status

| Environment / scope                                                        | Evidence                                               | Limits                                                               |
| -------------------------------------------------------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------- |
| Linux x86_64, rootless Podman development                                  | Locally tested as described above                      | Not a browser appearance check or cross-platform claim               |
| macOS ARM64, OrbStack Docker development                                   | User-supplied MacBook agent report received 2026-09-29 | Reviewed revision and execution date not provided; not observed here |
| New CLI/deployment additions                                               | Not covered by the MacBook report                      | Follow-up verification required before claiming macOS success        |
| Editor Dev Container lifecycle, browser appearance, macOS production image | Not verified by the MacBook report                     | Compose/HTTP success does not establish these                        |
| Other Docker runtimes, OSes, or architectures                              | No verification recorded here                          | Do not infer support from the OrbStack report                        |

The MacBook report says initialization with `DEVCONTAINER_RUNTIME=orbstack`,
Compose build/start with the then-required database profile, frozen dependency setup, and both
development/test database preparation succeeded. It reports `bin/check` passing
Standard Ruby and 2 tests / 7 assertions, plus HTTP 200 responses for `/`, `/up`,
the Lookbook landing inspector, preview iframe, and preview CSS. Rails was
started separately from the `sleep infinity` app service.

This is a dated user-supplied report, not verification performed for this README
change. The earlier source reference `e78601a` likely predates deployment commit
`c9989af` and its expanded 23-test suite; the reviewed revision was not supplied.
The reported 2-test result must not be treated as validation of that newer suite,
new CLI additions, production image, editor lifecycle, or browser appearance.

## Production Image

The root `Dockerfile` builds a Ruby 3.4.7 / Rails 8.1.3.1 production image with a frozen bundle and
precompiled Propshaft assets. The build stage fetches the pinned public Git gems; the runtime stage
excludes development/test gems, Git tooling, source-control metadata, and credentials. It runs as a
non-root user on port 3000. `/up` is the Rails boot health endpoint, not a database readiness check.
Do not pass real secrets as build arguments or copy them into the build context; provide runtime
secrets through deployment configuration.

On x86_64 Linux with rootless Podman, test without a database or host mounts:

```sh
podman build -t localhost/prosecho:image-test .
sh test/production_image.sh localhost/prosecho:image-test
```

Run `bin/check` inside the Dev Container.

The image smoke test uses an isolated network and a throwaway runtime key. The local production
image build, precompile, and smoke test passed, including the public page and its fingerprinted
Tailwind CSS; `/lookbook` returned 404. Kamal 2.12.0 configuration and guarded deployment tooling
are documented in [Deployment](docs/deployment.md). Local verification is not a successful
production deployment claim; VM, registry, Cloudflare, and other architectures require separate
verification.

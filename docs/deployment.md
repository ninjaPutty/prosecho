# Deployment

This is app-owned tooling only, not VM or Cloudflare provisioning. No password
login has been added. `/up` checks boot; `/ready` queries PostgreSQL with
`SELECT 1` and rejects pending migrations, returning only a generic 503 on
database errors. Deployment health checks use `/ready`.

## Runtime Boundary

Deploy with Kamal from the ordinary VS Code `app` devcontainer at `/prosecho`.
No separate deployment container or workstation Docker socket is required.
The image includes the pinned Docker CLI, Buildx, and cloudflared; Kamal is in
the development bundle. Rebuild the image to acquire newly added tools.

VS Code forwards the existing SSH agent. It must contain the Prosecho deployment
identity, fingerprint `SHA256:cPD+CrrfISC9ll5vIVtocfcP5dQcyYaMvj5wAebYj5M`;
other loaded identities are allowed. The committed public selector
`.devcontainer/production_deploy.pub` selects only that identity for Prosecho SSH.
The private key stays on the host. SSH uses `.devcontainer/ssh.prod`, installed
as the image's user SSH config, with the existing strictly verified VM pin.
Both the hostname and `prosecho-deploy-cloudflare` alias use this connection.
No Cloudflare Access token or browser login is required.

Use the existing host credential file
`~/.local/share/menloparking/prosecho/creds/app.env`, mode 600, in a mode-700
credential directory. It must contain exactly four unique, unquoted `KEY=value`
lines, without comments:

- `KAMAL_REGISTRY_PASSWORD`: a nonempty loopback-registry placeholder containing
  only letters, digits, `.`, `_`, or `-`.
- `PGADMINPASSWORD`: the existing PostgreSQL bootstrap administrator password.
- `PGPASSWORD`: the existing, separate application role password.
- `SECRET_KEY_BASE`: the existing application secret.

The three real secrets must be lowercase hex strings, 32 to 128 characters.
Preserve existing values; generating replacement passwords does not rotate
an initialized database. Never put secrets in source or build arguments.

The optional `.devcontainer/compose.kamal.yaml` mounts only this credential file
read-only into `app`, at `/run/prosecho/app.env`, and selects the remote Docker
host. On the host, apply it when ready to recreate `app`:

```sh
podman-compose -p prosecho -f .devcontainer/compose.yaml -f .devcontainer/compose.runtime.yaml -f .devcontainer/compose.kamal.yaml up -d --build app postgres
```

For Docker/OrbStack use `docker compose`. Retain the overlay on subsequent
Compose invocations. VS Code supplies agent forwarding on attachment; plain
Compose terminals need the existing documented developer agent setup.
Alternatively, keep the credential file outside the checkout inside `app` at
`~/.local/share/prosecho/app.env`, or set `PROSECHO_DEPLOY_SECRETS_FILE` to its
path. The default uses `/run/prosecho/app.env` when mounted, then the local file.
The container-local copy does not survive recreation; the host credential overlay
is the durable option. The deployment helper and Kamal read the same validated
file. Do not run `bin/prod/secret` interactively:
its stdout is intended only for Kamal's secret loader.

Trusted processes in `app` can use these runtime secrets and the forwarded agent,
including its other identities. The read-only bind prevents writes to the host
file, not use of its credentials. No private key, host home, or host runtime
socket is mounted. The older dedicated deployment overlay remains optional;
it is not required by this workflow.

Docker CLI 28.5.2 and Buildx 0.29.1 come from the digest-pinned official Docker
CLI image. cloudflared 2026.5.2 is checksum-verified against the official
[release asset digest](https://api.github.com/repos/cloudflare/cloudflared/releases/tags/2026.5.2).
Kamal is locked to 2.12.0 in development only; production excludes all these tools.
`DOCKER_HOST=ssh://deploy@prosecho-deploy-cloudflare` means the Docker daemon and
build are on the VM, not the workstation. The builder uses Docker's `docker`
driver and a committed Git clone, never `builder.context: .`.
The narrow `bin/prod/docker` wrapper sends only this registry's CLI-side login
and logout to the VM over SSH; the login password goes through stdin. The
Buildx client has no registry credentials, so this contract requires an
unauthenticated, VM-loopback-only registry, not a private authenticated registry.

## Production Shell, Runner, and Console

Run these helpers in the ordinary VS Code devcontainer. They connect as `deploy`
to `ssh-prosecho.menloparking.com` through `bin/prod/cloudflare-ssh`, using
the forwarded SSH agent without a Cloudflare Access login or service token. The
development image includes checksum-verified `cloudflared` 2026.5.2 for Linux
amd64/arm64; rebuild the image to install it. To install the same verified binary
in an existing container without recreating it, run:

```sh
sh .devcontainer/install-cloudflared.sh "$HOME/.local/bin/cloudflared"
```

The destination directory must already exist and be on `PATH`.
Developer sessions require no `CF_SSH_HOST` or app-secret credential mounts.
SSH uses `.devcontainer/ssh.prod`, strictly checks the committed public pin in
`.devcontainer/production_known_hosts`, and does not forward the agent to production.
The pin was copied from the host's vetted deployment known-host file and matched
the [VM inventory](https://drive.menloparking.com/documents/b796ca28-87da-4ec3-a210-e37ea63480f3)
fingerprint `SHA256:pL/Z+zpE+W25Q56uyJk7Z0+wtjvG2zOdkZm7UX7VyCw` on 2026-10-07.
On a key change, stop and independently verify with the host administrator before
updating the pin; these scripts do not automatically enroll host keys.

```sh
bin/prod/ssh
bin/prod/shell
bin/prod/console
bin/prod/console --sandbox
bin/prod/runner 'puts Rails.env'
bin/prod/runner ./scripts/report.rb argument
bin/prod/runner - < ./scripts/report.rb
```

`ssh` opens an interactive login shell on the production host; `shell` opens an
interactive `sh` inside the running production app container.
`console` attaches an interactive Rails console there; console options are
forwarded. Both allocate an SSH and Docker terminal. `runner` accepts one quoted
Ruby string, an existing local file, or `-` for stdin, followed by script arguments.
Local file content is streamed to Rails runner without uploading a remote file.
Rails commands explicitly use the production environment and return the remote
exit status.

In the dedicated deployment container, its configured
`DOCKER_HOST=ssh://deploy@prosecho-deploy-cloudflare` selects the existing pinned
`.devcontainer/ssh.deploy` connection, dedicated identity, and mounted host pin.
Both modes use the shared Cloudflare helper, which clears inherited Access token
variables and defaults to the production hostname (`CF_SSH_HOST` can override it).
Only `ssh-prosecho.menloparking.com` had its Access gate removed on 2026-10-07;
SSH public-key authentication, trusted TLS, tunnel routing, and DNS remain unchanged.
The former service-token file is no longer mounted or read; leave host credentials
and unrelated remote tokens untouched. This helper is not for Access-protected hosts.
Both session modes use a 10-second SSH connection timeout. Setting `DOCKER_HOST`
in ordinary `app` does not select the dedicated agent configuration; that mode
also requires its dedicated `/run/prosecho/agent.sock` selection.

The proxy resolves the source helper through `PATH`, including the isolated
deployment candidate's helper. No image-copied helper is used by these session
commands. Rebuilding the deployment image refreshes its copied `~/.ssh/config`;
the source helper ignores legacy auth selections in older copied configs.
Existing token mounts remain until an explicitly scheduled recreation; this
change does not recreate containers or delete the host file.

Application helpers require exactly one running canonical
`prosecho-web-FULL_SHA` container with the app's service/role labels. Missing or
ambiguous containers stop execution. Host `ssh` needs no app container. Sessions
remain attached to the selected container if a deployment switches versions.
These are direct application sessions; coordinate data/schema changes with
deployment operations. They do not acquire the deployment/cleanup lock.

Verify without production access inside the devcontainer:

```sh
ruby tests/prodhelpers/helpers_test.rb
```

The hermetic Minitest suite checks host versus container sessions, both SSH
connection modes, absence of Access token use, strict host trust, terminal
allocation, Ruby quoting, local-file/stdin streaming, script arguments, exit
statuses, and discovery failures using fake SSH. It is also included in `bin/check`.

## VM Prerequisites

The host agent must independently admit/provision the VM, Docker/BuildKit,
`deploy` user Docker access, Python 3 (stdlib only), `curl`, `flock`, standard Unix
tools, and pinned SSH host identity. Docker's reported data directory must be
readable for `df`.
The loopback HTTP registry is `127.0.0.1:5555`, reachable by the VM Docker daemon
and VM shell only. Its lifetime, persistence, and access policy are host-owned.
No workstation registry forwarding or Docker daemon bootstrap is performed.
Install the app-owned `bin/prod/cleanup` as `prosecho-cleanup` on the guest PATH,
using the host's reviewed Nix package with a pinned Python interpreter. This is
an infrastructure integration requirement, not provisioned by the app helper.
The Nix runner must execute this single script as `deploy`, with pinned Python 3
and Docker/Buildx on PATH; do not duplicate the cleanup policy in a shell wrapper.
The script uses Linux process groups and `prctl` via Python's stdlib `ctypes` to
supervise Docker CLI/plugin descendants. No additional Python packages are required.
Guest Docker 29.6.2, BuildKit 0.31 and Buildx 0.31 are distinct from the client
Docker 28.5.2 / Buildx 0.29.1 pins. Cleanup uses the guest Buildx and default
builder directly against `/var/run/docker.sock`, ignoring remote client contexts.

Proxy binds only `127.0.0.1:8080` and `127.0.0.1:8443`, without TLS. Cloudflare
must route the public hostname to VM loopback port 8080 with the correct Host
header. PostgreSQL 17 has no published port, uses the internal `kamal` network,
and persists at the explicit VM path `/home/deploy/.local/share/prosecho/postgres`.
Do not erase or repurpose that directory or initialization/digest markers.

App/accessory and proxy containers explicitly use Docker's `json-file` logging
driver with a 10 MiB log limit. Kamal's default `max-size` log option is not
compatible with the VM daemon's `journald` default; do not change the daemon-wide
logging configuration to work around an app deployment failure.

## Lifecycle Contract

The coordinating agent must obtain commit authorization and commit the reviewed
changes before deployment. No GitHub status, push, or CI service is required.
Use the exact full committed SHA, not a branch, dirty version, or `latest`:

```sh
bin/prod/deploy check FULL_SHA
bin/prod/deploy first FULL_SHA
# For subsequent reviewed, backward-compatible migrations with a verified backup:
APPROVED_MIGRATION_SHA=FULL_SHA bin/prod/deploy migrate FULL_SHA
# The retained revision is materialized separately; do not switch the shared checkout:
bin/prod/deploy check RETAINED_SHA
ROLLBACK_COMPATIBLE_SHA=RETAINED_SHA bin/prod/deploy rollback RETAINED_SHA
```

Every invocation materializes the exact commit in a fresh detached clone under
a private mode-700 operation directory, without hardlinks to the shared repo.
The shared checkout can change branches or contain other agents' uncommitted
work without changing candidate source. The candidate HEAD is verified afresh,
tracked files become read-only, and `bin/check` runs there. No proof file from
another invocation is trusted: `first`, `migrate`, and `rollback` repeat checks
on their own isolated candidate before any target mutation. The clone, checks,
Kamal working directory, helper PATH, and Kamal scratch/clone directory all
belong to this unique operation. The SSH proxy resolves `cloudflare-ssh` through
that candidate PATH, not through the mutable shared checkout. Kamal still
builds its own Git clone, not the working directory. Only the operation's own
temporary directory is removed afterward; no shared source is changed.

Under a VM-side `flock` held by `prosecho-cleanup` for the whole target operation,
a lightweight guard requires 4 GiB available Docker disk space and 2 GiB
available memory before remote building. If disk is low, it attempts only the
bounded cache policy below while holding that same lock, then rechecks capacity
and aborts if still low. Capacity is checked again before migrations and activation.
One runner checks the lock before starting and after completing every capture
or mutation, and while commands run. Registry queries, digest recording,
database operations, and the final initialization marker use this same runner.
Loss forbids any new phase and stops the active local command group. Deadlines
are 30 seconds for target metadata/tool probes, 300 seconds for normal phases,
600 seconds for checks, and 1800 seconds for builds. TERM-resistant local
processes receive KILL after two seconds. Lock acquisition is nonblocking; the
lock/preflight handshake allows 210 seconds for low-disk cache recovery, and lock
transport shutdown allows two seconds. Inspect remote state:
stopping an SSH client does **not** guarantee cancellation of an already-issued
remote command, and cannot undo its effects. Other deployers must
use this same helper/lock, not direct concurrent Kamal commands.

New SHA tags must not already exist in the registry. After publishing, the helper
records their manifest digest on the VM and refuses unknown or changed tags.
Retries reuse the recorded artifact instead of rebuilding/overwriting it. A
crash between push and recording requires operator verification, not automatic
adoption. The registry must retain these tags/digests; never edit the digest
records to bypass a mismatch.

First install builds the checked image, creates the internal network, and boots
PG with bootstrap user/database `postgres`, using `PGADMINPASSWORD` as
`POSTGRES_PASSWORD`. It waits for PG startup, then uses that administrator
inside the PG accessory to create a separate `prosecho` LOGIN role with
`NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT` and no
role memberships. It creates `prosecho_production` owned by that role. Database
ownership and PostgreSQL 17's default `pg_database_owner` public-schema ownership
permit app migrations only within that database, not cluster administration.
Unexpected existing memberships are rejected for operator review.

The app password is validated as hex and sent only in SQL stdin, not SSH/psql
arguments or printed commands; bootstrap captures suppress stdout/stderr, and
session statement/duration/error-statement logging is disabled before the
password SQL. The administrator password remains in the PG accessory's
environment, never in Rails. Rails one-off containers receive only
`SECRET_KEY_BASE` and `PGPASSWORD`; normal web containers receive the same app
secrets via Kamal. Both admin and app authentication use TCP, not local trust.
After bootstrap it waits up to 120 seconds for an authenticated **app-role**
`SELECT 1`, sending its password via stdin, pulls the image, and runs image-based
`db:prepare` once. A `db-prepared` marker makes a failed
proxy/switch retry skip initialization. Only then does it boot the loopback proxy
and run `redeploy --skip-push`. A successful origin `/ready` check records the
`initialized` marker, through the monitored runner. Existing installations
reject `first`. Bootstrap retries are idempotent and never delete a database,
directory, or volume. Changing the administrator secret does not change an
already initialized PG cluster password; retain the correct original admin
credential and use a separately reviewed rotation procedure when needed.

Later deployment explicitly runs `db:migrate` in the new image before traffic
switching. Review expand/contract compatibility with the running and retained
versions and verify a backup first; the approval environment variable records
operator intent, not a migration-safety proof. Pending migrations cause 503, so
noncompatible schema changes need a separately reviewed maintenance procedure.

Rollback requires a retained container and explicit schema-compatibility review,
then uses `kamal rollback` without builds or reverse migrations. First install
has no previous app to roll back to: leave PG/data/artifacts intact, diagnose,
and retry the same recorded SHA. Never automate database restore or down
migrations. These helpers never remove accessories or run `kamal setup`; failed
releases leave unresolved artifacts and their containers protected. Local tests
are not evidence of a production deployment.

## Bounded Cleanup

`bin/prod/cleanup --dry-run` and `--apply` run **on the guest**, as `deploy`.
`--cache-only` restricts either mode to build cache. Every mode obtains the same
nonblocking `/home/deploy/.local/share/prosecho/deploy.lock`. Busy lock exits 75
without Docker queries or mutations. The helper validates a regular, deploy-owned,
non-symlink, single-link, non-group/world-writable lock and its inode before work.
Every Docker call revalidates the named lock's device/inode and the pinned state
directory. Directory traversal uses directory-relative `lstat`/`open` with
`O_NOFOLLOW`, rejects symlinks and group/other-writable directories all the way
from `/`, and permits only root or the effective user to own ancestors. The
deploy home and final state directory must be deploy-owned; the final state
directory must be exactly mode 700. Root-owned mode-755 `/` and `/home` are allowed.
Unsafe existing directories are rejected, never automatically chmodded or replaced.
It never truncates, replaces or unlinks that file. All deployers and future timers
must use this protocol; there is no unchecked lock-held flag. Do not invoke
direct concurrent Kamal or cleanup commands outside the common lock.
The state path is fixed, not derived from `HOME`; root execution is rejected.
Run any future timer with `User=deploy`, even when the program is root-installed.

Deployment starts the installed helper with `--apply --hold-lock` over SSH. It
prints `LOCKED` after preflight and holds the lock until stdin EOF. After all
deployment phases succeed, the client sends one JSON line containing `sha` and
`digest`. The helper independently verifies the exact running canonical web
container, service/role labels, image repository and recorded manifest digest,
then requires routed `/ready` to return exactly 200 without redirects. Only then
does it atomically append `{sha, digest, at}` to `success.json` and print
`RECORDED`. It performs post-success cleanup under the same full-operation lock
and prints `CLEANED`. Cleanup errors are warnings, not release failures after
`RECORDED`; ledger verification/recording failures are deployment failures.
No success is inferred from the artifact files under `images/`, tag order,
`latest`, an initialized marker, or previous failed deployment output.

Before enabling release cleanup, infrastructure must install deploy-owned,
non-symlink `protect.json` in the same state directory, containing this JSON array:

```json
[
  "4a69a6aeca31d6f75f8496bb38f0a90abbb5a74b",
  "66870ed7351e11ecf1f720743c54fd3bd25bed96",
  "c9989afa5b16ee745feb920efde7137e598e27cb"
]
```

These protect the current, prior and unresolved initial artifacts permanently.
Add full candidate/operator-protected SHAs here as needed. Unknown SHAs are
already protected. Protection edits must also hold the deployment lock. Do not
seed `success.json` from artifact records: only a
verified successful deployment may write it. Missing or malformed success or
protection state skips all release cleanup, while cache cleanup can still run.
Each success record must be an object with exactly `sha`, `digest`, and `at`:
string full SHA and digest, and a finite positive numeric timestamp no later than
now. Booleans, NaN, infinities, future times, non-objects and conflicting SHA
digests are rejected before selecting any release for removal.
State files are bounded at 4 MiB, success history at 10,000 records and explicit
protection at 1,000 SHAs; hitting a bound requires operator review, not pruning
the ledger or dropping protection automatically.

Cache cleanup issues only this guest command (with an explicit local daemon):

```sh
docker --host unix:///var/run/docker.sock buildx prune --builder default --filter until=168h --max-used-space 5368709120 --force
```

There is no `--all`. Seven-day cache age plus a 5 GiB max-used-space target is a
soft reclaim policy, not a hard disk quota or guarantee of 5 GiB usage. Reports
include free filesystem bytes and unfiltered Buildx disk usage before and after.
Dry-run derives eligibility from reclaimable status and last-used timestamps;
it does not trust Buildx `du --filter until=...`, which can report all records.
Any reclaimable record with missing, null, unparseable or timezone-less last-used
metadata blocks the **whole cache prune**, including when usage exceeds 5 GiB.
Unknown reclaimability also blocks prune. This is necessary because server-side
`until` filtering can admit NULL ages; the age filter alone does not protect them.
Dry-run reports age-eligible candidates separately from actual eligibility; when
blocked, all records are protected and actual eligibility is empty. Low-disk
preflight still rechecks capacity and aborts when this conservative skip leaves
insufficient space. There is no broad-prune or bespoke-record-deletion fallback.

Release cleanup preserves the last three distinct successful SHAs, explicit
protection, and all running containers' images. It removes at most 20 objects per
pass. Container removal requires an unprotected, known successful SHA older than
seven days, exact name `prosecho-web-FULL_SHA` (or explicitly supported
`_replaced_SUFFIX` / `-replaced-SUFFIX`), exact
`service=prosecho` / `role=web` labels and exact repository/SHA image reference.
It must be exited for more than seven days and is reinspected by full ID just
before non-forced `docker container rm`, without `-v`. Its **actual image ID** is
inspected and must have the success ledger's exact repository manifest digest;
the tag in `Config.Image` is not sufficient. A fresh inventory must show no
running container referencing that image ID or repository/SHA tag. Protected
SHAs retain all their containers, not just the canonical rollback container.

Image removal uses only an explicit `127.0.0.1:5555/prosecho:FULL_SHA` tag for an
older known successful release, after matching its ledger manifest digest and
re-enumerating **all** containers, including stopped/unrelated containers, for
image-ID and tag references. Removal is exactly `docker image rm --no-prune REF`,
without force, so untagged parents cannot be implicitly removed outside the
20-object limit. It never removes an image by ID. Artifact
records, registry tags/blobs, PostgreSQL data, backups, volumes, networks, proxy
and accessory containers are untouched. There is no Docker system/image/volume
prune, registry garbage collection, or automatic database cleanup. Registry and
protected artifacts can grow without bound; alert/provision capacity rather than
relaxing these protections. A scheduled timer is infrastructure-owned and is not
installed by this change.

### Uncertain Mutations

Before each Docker mutation the helper durably creates a mode-600
`cleanup-inflight` marker containing the command and timestamp, while retaining
the deployment lock in the Python supervisor. CLI/plugins run in a new process
group; inherited lock FDs are not trusted because Go/plugin launchers can drop
them. The normal CLI deadline is 180 seconds. On timeout, interruption, command
failure or surviving descendants, the helper preserves `cleanup-uncertain`,
sends TERM to the whole group, waits two seconds, then sends KILL and reaps
adopted descendants. It retains the lock until the group is gone. A process stuck
in uninterruptible kernel sleep can delay this shutdown; safety takes precedence
over releasing the lock. Abrupt supervisor death leaves the inflight marker.
Successful completion clears only its own transient inflight marker, never an
existing uncertainty marker.

Killing clients cannot prove that an already-issued daemon/BuildKit request has
stopped. Either marker therefore blocks **every** subsequent cleanup or deployment
lock acquisition, including dry-run, before Docker queries or new phases.
There is no automatic expiry, retry, bypass or uncertainty-marker clearing.
Post-success cleanup remains nonfatal to the recorded release, but its uncertainty
must be resolved before the next operation.

Recovery is operator-only: hold the unchanged deployment lock with `flock`, read
the marker's command/timestamp, verify that the CLI/plugin process group is gone
and that the daemon/BuildKit mutation has completed or ceased, and inspect the
resulting Docker/application state. Only after that verification and explicit
review may the operator remove `cleanup-uncertain` or stale `cleanup-inflight`
while still holding the lock. Never unlink `deploy.lock`, clear a marker merely
because its PID disappeared, or use a timer to clear it. If daemon activity cannot
be established confidently, retain the marker and stop deployments/cleanup.

## Local Verification

`bin/check` exercises `/ready` against real local PostgreSQL: healthy 200,
unreachable database 503, and a real unapplied migration 503. It also bootstraps
a uniquely named temporary role/database on the local development/test PG
cluster, verifies authenticated app access and table migrations, verifies that
role/database creation and `pg_authid` access are forbidden, then removes only
those test-owned objects. No production credentials or target connection is
used. Source-switch, lock-loss, bounded-timeout, credential-filtering and digest
tests use temporary repositories or fake dependencies, not external HTTP.
Cleanup regressions use Minitest and a fake Docker executable:
`ruby tests/prodcleanup/cleanup_test.rb` inside the devcontainer, with Python 3
available. The deployment tests also invoke this suite, so `bin/check` requires
Python 3 in the test container as well as on the guest. No actual Docker deletion,
guest activation or live prune is part of these tests.

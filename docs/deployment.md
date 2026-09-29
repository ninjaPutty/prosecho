# Deployment

This is app-owned tooling only, not VM or Cloudflare provisioning. No password
login has been added. `/up` checks boot; `/ready` queries PostgreSQL with
`SELECT 1` and rejects pending migrations, returning only a generic 503 on
database errors. Deployment health checks use `/ready`.

## Runtime Boundary

The normal devcontainer remains credential-free. On the host, the coordinating
agent must prepare `~/.local/share/menloparking/prosecho/` with:

- `runtime.env`: mode 600, containing only `CF_SSH_HOST=the-approved-access-hostname`.
- `agent.sock`: dedicated SSH agent holding exactly the Prosecho deployment key.
- `creds/deploy.pub`: public half of that key, not the private key.
- `creds/known_hosts`: independently verified VM host key under the alias `prosecho-deploy-cloudflare`. Do not use blind `ssh-keyscan` trust or disable verification.
- `creds/service-token.json`: mode 600 JSON with `client_id` and `client_secret` for the narrowly scoped Cloudflare SSH Access service token.
- `creds/app.env`: mode 600, exactly four unquoted lines named `SECRET_KEY_BASE`, `PGPASSWORD`, `PGADMINPASSWORD`, and `KAMAL_REGISTRY_PASSWORD`. `PGPASSWORD` is the app role's password; `PGADMINPASSWORD` is the separate bootstrap administrator password. All three real secrets must be independently generated lowercase hex strings, 32 to 128 characters; database passwords must differ. The unauthenticated loopback registry login uses a nonempty placeholder containing only letters, digits, `.`, `_`, or `-`. No comments or duplicate keys.

Credential directories should be mode 700. Credential files and the private key
stay outside the checkout. The overlay mounts only the dedicated socket, public
key, pinned known-host file, service-token JSON, app secrets, and this source
tree. `runtime.env` is read by Compose, not bind-mounted. No host home, private
key, Docker/Podman socket, or general SSH agent is exposed. The deployment
container can use the agent and secrets while running trusted repository code;
read-only mounts do not make malicious code safe.

Start explicitly on Linux x86_64 rootless Podman:

```sh
podman-compose -p prosecho -f .devcontainer/compose.yaml -f .devcontainer/compose.runtime.yaml -f .devcontainer/compose.deploy.yaml --profile deploy --profile db up -d deploy postgres
podman-compose -p prosecho -f .devcontainer/compose.yaml -f .devcontainer/compose.runtime.yaml -f .devcontainer/compose.deploy.yaml exec deploy sh .devcontainer/setup.sh
```

Rebuild the deployment image after these changes; both container images now
include `psql` for the real local database-role tests. Setup prepares the
**local** test/development database only. Run the commands below inside `deploy`
at `/prosecho`. Stop that service when deployment access is
no longer needed. This overlay is intentionally not part of `devcontainer.json`.

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

## VM Prerequisites

The host agent must independently admit/provision the VM, Docker/BuildKit,
`deploy` user Docker access, `curl`, `flock`, standard Unix tools, and pinned SSH
host identity. Docker's reported data directory must be readable for `df`.
The loopback HTTP registry is `127.0.0.1:5555`, reachable by the VM Docker daemon
and VM shell only. Its lifetime, persistence, and access policy are host-owned.
No workstation registry forwarding or Docker daemon bootstrap is performed.

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

Under a VM-side `flock` held for the whole target operation, a lightweight guard requires 4 GiB
available Docker disk space and 2 GiB available memory before remote building.
One runner checks the lock before starting and after completing every capture
or mutation, and while commands run. Registry queries, digest recording,
database operations, and the final initialization marker use this same runner.
Loss forbids any new phase and stops the active local command group. Deadlines
are 30 seconds for target metadata/tool probes, 300 seconds for normal phases,
600 seconds for checks, and 1800 seconds for builds. TERM-resistant local
processes receive KILL after two seconds. Lock acquisition is bounded at 30
seconds and lock transport shutdown at two seconds. Inspect remote state:
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
migrations. These helpers do not prune images or containers, remove accessories,
or run `kamal setup`; failed releases leave retained containers available.
`retain_containers: 3` is a future targeted cleanup policy, not broad-prune
permission. Production deployment has not been exercised by local tests.

## Local Verification

`bin/check` exercises `/ready` against real local PostgreSQL: healthy 200,
unreachable database 503, and a real unapplied migration 503. It also bootstraps
a uniquely named temporary role/database on the local development/test PG
cluster, verifies authenticated app access and table migrations, verifies that
role/database creation and `pg_authid` access are forbidden, then removes only
those test-owned objects. No production credentials or target connection is
used. Source-switch, lock-loss, bounded-timeout, credential-filtering and digest
tests use temporary repositories or fake dependencies, not external HTTP.

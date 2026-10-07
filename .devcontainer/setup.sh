#!/bin/sh
set -eu

automatic=false
case "${1:-}" in
  --automatic) automatic=true ;;
  "") ;;
  *) printf '%s\n' 'Usage: sh .devcontainer/setup.sh [--automatic]' >&2; exit 2 ;;
esac

lock_dir=tmp/devcontainer-setup.lock
mkdir -p tmp
if ! mkdir "$lock_dir" 2>/dev/null; then
  printf 'Setup already running or stale lock at %s\n' "$lock_dir" >&2
  exit 1
fi
trap 'rmdir "$lock_dir"' EXIT HUP INT TERM

if [ ! -f Gemfile.lock ]; then
  printf '%s\n' 'Gemfile.lock is missing; resolve and review dependencies first.' >&2
  exit 1
fi

if [ "${RAILS_ENV:-development}" != development ] ||
   [ "${RACK_ENV:-development}" != development ] || [ -n "${DATABASE_URL:-}" ]; then
  printf '%s\n' 'Setup requires development with no DATABASE_URL override.' >&2
  exit 1
fi
export RAILS_ENV=development PGCONNECT_TIMEOUT=3

if ! BUNDLE_FROZEN=true bundle check >/dev/null 2>&1 &&
   ! BUNDLE_FROZEN=true bundle install; then
  printf '%s\n' 'Dependency installation failed; fix the error above, then resume: sh .devcontainer/setup.sh' >&2
  exit 1
fi

probe_status=0
pg_isready -q -t 3 -d postgres || probe_status=$?
case "$probe_status" in
  0) ;;
  1|2)
    printf '%s\n' 'Shell ready; dependencies installed; PostgreSQL unavailable (database setup pending).'
    printf '%s\n' 'On the host, start the local database:' \
      'podman-compose -p prosecho -f .devcontainer/compose.yaml -f .devcontainer/compose.runtime.yaml up -d postgres' \
      'For Docker/OrbStack, replace podman-compose with docker compose.' \
      'Then in the container resume: sh .devcontainer/setup.sh'
    [ "$automatic" = true ] && exit 0
    exit 1
    ;;
  *) printf '%s\n' 'PostgreSQL availability probe failed; check pg_isready and its configuration.' >&2
    exit 1 ;;
esac

# pg_isready does not authenticate; a responding server with bad credentials is an error.
if ! psql -X -w -d postgres -v ON_ERROR_STOP=1 -c 'SELECT 1' >/dev/null; then
  printf '%s\n' 'PostgreSQL authenticated connection failed; fix the error above.' >&2
  exit 1
fi

if ! bin/rails db:prepare; then
  printf '%s\n' 'Database preparation failed; fix the error above, then resume: sh .devcontainer/setup.sh' >&2
  exit 1
fi

printf '%s\n' 'Ready: run bin/check, then bin/rails server -b 0.0.0.0.'

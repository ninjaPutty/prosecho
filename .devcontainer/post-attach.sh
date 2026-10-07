#!/bin/sh
set -eu

if ! sh "$(dirname "$0")/link-work-logs.sh"; then
  printf '%s\n' 'Warning: optional work logs link could not be updated; shell remains usable.' >&2
fi

if [ ! -f Gemfile.lock ] || ! BUNDLE_FROZEN=true bundle check >/dev/null 2>&1; then
  printf '%s\n' 'Shell ready; dependencies NOT ready. Resume: sh .devcontainer/setup.sh'
elif [ "${RAILS_ENV:-development}" != development ] ||
     [ "${RACK_ENV:-development}" != development ] || [ -n "${DATABASE_URL:-}" ]; then
  printf '%s\n' 'Shell ready; development readiness NOT ready: remove environment/database overrides.'
else
  probe_status=0
  pg_isready -q -t 3 -d postgres || probe_status=$?
  case "$probe_status" in
    0) ;;
    1|2)
      printf '%s\n' 'Shell ready; dependencies ready; PostgreSQL unavailable (database setup pending).'
      printf '%s\n' 'On the host, start the local database:' \
        'podman-compose -p prosecho -f .devcontainer/compose.yaml -f .devcontainer/compose.runtime.yaml up -d postgres' \
        'For Docker/OrbStack, replace podman-compose with docker compose.' \
        'Then in the container resume: sh .devcontainer/setup.sh'
      exit 0 ;;
    *)
      printf 'Shell ready; database readiness NOT checked: PostgreSQL availability probe failed (status %s); check pg_isready and its configuration.\n' "$probe_status" >&2
      exit 0 ;;
  esac

  if PGCONNECT_TIMEOUT=3 RAILS_ENV=development bin/rails runner \
  'pool = ActiveRecord::Base.connection_pool
   pool.with_connection { |c| c.select_value("SELECT 1") }
   abort "Pending migrations" if pool.migration_context.needs_migration?'; then
    printf '%s\n' 'Ready: dependencies and development database checked. Run bin/check.'
  else
    printf '%s\n' 'Shell ready; database NOT ready. Review the error above, then resume: sh .devcontainer/setup.sh'
  fi
fi

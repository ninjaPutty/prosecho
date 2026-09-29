#!/bin/sh
set -eu

automatic=false
case "${1:-}" in
  --automatic) automatic=true ;;
  "") ;;
  *) printf '%s\n' 'Usage: sh .devcontainer/setup.sh [--automatic]' >&2; exit 2 ;;
esac

lock_dir=tmp/devcontainer-setup.lock
if ! mkdir "$lock_dir" 2>/dev/null; then
  printf 'Setup already running or stale lock at %s\n' "$lock_dir" >&2
  exit 1
fi
trap 'rmdir "$lock_dir"' EXIT HUP INT TERM

if [ "$automatic" = true ]; then
  if [ -f Gemfile.lock ] && BUNDLE_FROZEN=true bundle check; then
    printf '%s\n' 'Shell ready; dependencies installed. Database setup is opt-in: sh .devcontainer/setup.sh'
  else
    printf '%s\n' 'Shell ready; dependencies NOT ready. Run sh .devcontainer/setup.sh to install and prepare the database.'
  fi
  exit 0
fi

if [ ! -f Gemfile.lock ]; then
  printf '%s\n' 'Gemfile.lock is missing; resolve and review dependencies first.' >&2
  exit 1
fi

if ! BUNDLE_FROZEN=true bundle check && ! BUNDLE_FROZEN=true bundle install; then
  printf '%s\n' 'Dependencies unavailable; check network access, then resume: sh .devcontainer/setup.sh' >&2
  exit 1
fi

if ! bin/rails db:prepare; then
  printf '%s\n' 'PostgreSQL unavailable; start the db profile, then resume: sh .devcontainer/setup.sh' >&2
  exit 1
fi

printf '%s\n' 'Ready: run bin/check, then bin/rails server -b 0.0.0.0.'

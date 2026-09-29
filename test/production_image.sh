#!/bin/sh
# Run after building: sh test/production_image.sh IMAGE
set -eu

image=${1:?Pass a locally built image name or digest}
podman run --rm --network none --entrypoint /bin/sh "$image" -ec '
  test "$(id -u)" -ne 0
  test -w /rails
  test "$(ruby -v | cut -d " " -f 2)" = 3.4.7
  bundle check
  SECRET_KEY_BASE=prosecho-image-smoke-test-only-not-a-real-secret bin/rails runner '\''abort unless Gem.loaded_specs.fetch("rails").version.to_s == "8.1.3.1"; abort unless defined?(PG) && defined?(Phlex::Rails) && defined?(Carnet) && defined?(Turnstile)'\''
  test -f public/assets/.manifest.json
  test -n "$(ls public/assets/tailwind-*.css)"
  grep -q "#f5f3ed" public/assets/tailwind-*.css
  test ! -e .git
  test ! -e .env
  test ! -e config/master.key
  test ! -e config/credentials.yml.enc
  test ! -e test
  test ! -e /usr/bin/git
  test ! -d /usr/local/bundle/ruby/3.4.0/gems/lookbook-2.3.15
  test ! -d /usr/local/bundle/ruby/3.4.0/gems/standard-1.56.0
'

podman run --rm --network none --entrypoint /bin/sh \
  -e SECRET_KEY_BASE=prosecho-image-smoke-test-only-not-a-real-secret \
  "$image" -ec '
  bin/rails server -b 127.0.0.1 > /tmp/server.log 2>&1 &
  server=$!
  trap "kill $server 2>/dev/null || true" EXIT
  ruby -rnet/http -e '\''
    60.times do
      begin
        health = Net::HTTP.get_response(URI("http://127.0.0.1:3000/up"))
        if health.code == "200"
          inspector = Net::HTTP.get_response(URI("http://127.0.0.1:3000/lookbook"))
          abort "Lookbook returned #{inspector.code}" unless inspector.code == "404"
          home = Net::HTTP.get_response(URI("http://127.0.0.1:3000/"))
          abort "Home returned #{home.code}" unless home.code == "200"
          css_path = home.body[/href="([^"]*tailwind[^"]*\.css)"/, 1]
          abort "Home has no Tailwind stylesheet" unless css_path
          css = Net::HTTP.get_response(URI("http://127.0.0.1:3000#{css_path}"))
          abort "Tailwind returned #{css.code}" unless css.code == "200" && css.body.include?("#f5f3ed")
          exit 0
        end
      rescue Errno::ECONNREFUSED
      end
      sleep 1
    end
    abort "health endpoint did not return 200"
  '\'' || { /bin/cat /tmp/server.log; exit 1; }
'

#!/bin/sh
set -eu

destination=${1:-/usr/local/bin/cloudflared}
case "$(dpkg --print-architecture)" in
  amd64) checksum=5286698547f03df745adb2355f04c12dde52ef425491e81f433642d695521886 ;;
  arm64) checksum=5a4e8ce2701105271412059f44b6a0bf1ae4542b4d98ff3180c0c019443a5815 ;;
  *) printf '%s\n' 'Unsupported cloudflared architecture' >&2; exit 1 ;;
esac
temporary=$(mktemp)
trap 'rm -f "$temporary"' EXIT HUP INT TERM
curl --connect-timeout 10 --max-time 120 -fsSL \
  "https://github.com/cloudflare/cloudflared/releases/download/2026.5.2/cloudflared-linux-$(dpkg --print-architecture)" \
  -o "$temporary"
printf '%s  %s\n' "$checksum" "$temporary" | sha256sum -c -
install -m 755 "$temporary" "$destination"
"$destination" --version

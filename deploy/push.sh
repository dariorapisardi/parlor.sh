#!/usr/bin/env bash
# Copy the service to the server, install its systemd units when they changed, and restart it.
# Rooms survive restarts.
# usage: deploy/push.sh user@host
set -euo pipefail
target="${1:?usage: deploy/push.sh user@host}"
here="$(cd "$(dirname "$0")/.." && pwd)"

# The Gleam build is never made here: it is the one CI compiled on the Erlang the server runs
# (artifact parlor-gleam-otp27), for exactly the commit being deployed, after the suite passed.
cd "$here"
commit="$(git rev-parse HEAD)"
git diff --quiet HEAD -- gleam || { echo "gleam/ has uncommitted changes: commit, push, let CI build it" >&2; exit 1; }
run="$(gh run list --commit "$commit" --workflow conformance --json databaseId,conclusion \
  -q '.[] | select(.conclusion == "success") | .databaseId' | head -1)"
[ -n "$run" ] || { echo "no successful CI run for $commit: push it and wait for CI" >&2; exit 1; }
build="$(mktemp -d)"; trap 'rm -rf "$build"' EXIT
gh run download "$run" -n parlor-gleam-otp27 -D "$build/gleam/erlang-shipment"

rsync -az --delete \
  --include='/server.mjs' --include='/docs/***' --include='/skill/***' --include='/LICENSE' --include='/brand/***' --include='/README.md' \
  --include='/deploy/' --include='/deploy/parlor.service' --include='/deploy/parlor.socket' --include='/deploy/parlor-gleam.service' \
  --include='/deploy/Caddyfile' --exclude='*' "$here/" "$target:/tmp/parlor-release/"
rsync -az --delete "$build/gleam/" "$target:/tmp/parlor-release/gleam/"
ssh "$target" '
  set -e
  sudo rsync -a --delete /tmp/parlor-release/ /opt/parlor/
  # The units carry the production limits and the socket; a changed unit needs a reload before use.
  for u in parlor.socket parlor.service parlor-gleam.service; do
    if ! sudo cmp -s "/opt/parlor/deploy/$u" "/etc/systemd/system/$u"; then
      sudo install -m 644 "/opt/parlor/deploy/$u" "/etc/systemd/system/$u"
      changed=1; echo "$u installed"
    fi
  done
  [ -n "${changed:-}" ] && sudo systemctl daemon-reload
  if systemctl is-enabled --quiet parlor-gleam; then
    # The Gleam service binds the port itself; Caddy retries the connections refused meanwhile.
    sudo systemctl restart parlor-gleam
    unit=parlor-gleam
  elif systemctl is-active --quiet parlor.socket; then
    # systemd holds the port: connections arriving during the restart wait for the new process.
    sudo systemctl restart parlor
  else
    # First time only: the running parlor bound the port itself and must let go before the socket
    # unit can take it. This one restart can still refuse connections for a moment.
    sudo systemctl stop parlor && sudo systemctl enable --now --quiet parlor.socket && sudo systemctl start parlor
    echo "socket unit now holds the port"
  fi
  for i in $(seq 1 50); do curl -s -o /dev/null http://127.0.0.1:8787/ && break; sleep 0.2; done
  systemctl is-active "${unit:-parlor}"
  # Caddy imports deploy/Caddyfile from the release; a reload is graceful (no connection dropped).
  if systemctl is-active --quiet caddy; then sudo systemctl reload caddy && echo "caddy reloaded"; fi
  curl -s -o /dev/null -w "local check: %{http_code}\n" http://127.0.0.1:8787/'

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

# --delete-excluded: a file dropped from the release (server.mjs, once) leaves the server too.
rsync -az --delete --delete-excluded --filter='P /gleam/***' \
  --include='/docs/***' --include='/skill/***' --include='/LICENSE' --include='/brand/***' --include='/README.md' \
  --include='/deploy/' --include='/deploy/parlor-gleam.service' \
  --include='/deploy/Caddyfile' --exclude='*' "$here/" "$target:/tmp/parlor-release/"
rsync -az --delete "$build/gleam/" "$target:/tmp/parlor-release/gleam/"
ssh "$target" '
  set -e
  sudo rsync -a --delete /tmp/parlor-release/ /opt/parlor/
  # The unit carries the production limits; a changed unit needs a reload before use.
  u=parlor-gleam.service
  if ! sudo cmp -s "/opt/parlor/deploy/$u" "/etc/systemd/system/$u"; then
    sudo install -m 644 "/opt/parlor/deploy/$u" "/etc/systemd/system/$u"
    sudo systemctl daemon-reload; echo "$u installed"
  fi
  # parlor binds the port itself; Caddy retries the connections refused during the restart.
  sudo systemctl enable --quiet parlor-gleam
  sudo systemctl restart parlor-gleam
  for i in $(seq 1 50); do curl -s -o /dev/null http://127.0.0.1:8787/ && break; sleep 0.2; done
  systemctl is-active parlor-gleam
  # Caddy imports deploy/Caddyfile from the release; a reload is graceful (no connection dropped).
  if systemctl is-active --quiet caddy; then sudo systemctl reload caddy && echo "caddy reloaded"; fi
  curl -s -o /dev/null -w "local check: %{http_code}\n" http://127.0.0.1:8787/'

#!/usr/bin/env bash
# Copy the service to the server, install its systemd unit when it changed, and restart it.
# Rooms survive restarts.
# usage: deploy/push.sh user@host
set -euo pipefail
target="${1:?usage: deploy/push.sh user@host}"
here="$(cd "$(dirname "$0")/.." && pwd)"
rsync -az --delete \
  --include='/server.mjs' --include='/docs/***' --include='/skill/***' --include='/LICENSE' --include='/brand/***' --include='/README.md' \
  --include='/deploy/' --include='/deploy/parlor.service' --include='/deploy/Caddyfile' \
  --exclude='*' "$here/" "$target:/tmp/parlor-release/"
ssh "$target" '
  set -e
  sudo rsync -a --delete /tmp/parlor-release/ /opt/parlor/
  # The unit carries the production limits; a changed unit needs a reload before the restart reads it.
  unit=/etc/systemd/system/parlor.service
  if ! sudo cmp -s /opt/parlor/deploy/parlor.service "$unit"; then
    sudo install -m 644 /opt/parlor/deploy/parlor.service "$unit"
    sudo systemctl daemon-reload
    echo "unit installed"
  fi
  sudo systemctl restart parlor && sleep 1 && systemctl is-active parlor
  # Caddy imports deploy/Caddyfile from the release; a reload is graceful (no connection dropped).
  if systemctl is-active --quiet caddy; then sudo systemctl reload caddy && echo "caddy reloaded"; fi
  curl -s -o /dev/null -w "local check: %{http_code}\n" http://127.0.0.1:8787/'

#!/usr/bin/env bash
# Copy the service to the server, install its systemd units when they changed, and restart it.
# Rooms survive restarts.
# usage: deploy/push.sh user@host
set -euo pipefail
target="${1:?usage: deploy/push.sh user@host}"
here="$(cd "$(dirname "$0")/.." && pwd)"
rsync -az --delete \
  --include='/server.mjs' --include='/docs/***' --include='/skill/***' --include='/LICENSE' --include='/brand/***' --include='/README.md' \
  --include='/deploy/' --include='/deploy/parlor.service' --include='/deploy/parlor.socket' --include='/deploy/Caddyfile' \
  --exclude='*' "$here/" "$target:/tmp/parlor-release/"
ssh "$target" '
  set -e
  sudo rsync -a --delete /tmp/parlor-release/ /opt/parlor/
  # The units carry the production limits and the socket; a changed unit needs a reload before use.
  for u in parlor.socket parlor.service; do
    if ! sudo cmp -s "/opt/parlor/deploy/$u" "/etc/systemd/system/$u"; then
      sudo install -m 644 "/opt/parlor/deploy/$u" "/etc/systemd/system/$u"
      changed=1; echo "$u installed"
    fi
  done
  [ -n "${changed:-}" ] && sudo systemctl daemon-reload
  if systemctl is-active --quiet parlor.socket; then
    # systemd holds the port: connections arriving during the restart wait for the new process.
    sudo systemctl restart parlor
  else
    # First time only: the running parlor bound the port itself and must let go before the socket
    # unit can take it. This one restart can still refuse connections for a moment.
    sudo systemctl stop parlor && sudo systemctl enable --now --quiet parlor.socket && sudo systemctl start parlor
    echo "socket unit now holds the port"
  fi
  sleep 1 && systemctl is-active parlor
  # Caddy imports deploy/Caddyfile from the release; a reload is graceful (no connection dropped).
  if systemctl is-active --quiet caddy; then sudo systemctl reload caddy && echo "caddy reloaded"; fi
  curl -s -o /dev/null -w "local check: %{http_code}\n" http://127.0.0.1:8787/'

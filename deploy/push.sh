#!/usr/bin/env bash
# Copy the service to the server and restart it. Rooms survive restarts.
# usage: deploy/push.sh user@host
set -euo pipefail
target="${1:?usage: deploy/push.sh user@host}"
here="$(cd "$(dirname "$0")/.." && pwd)"
rsync -az --delete \
  --include='/server.mjs' --include='/docs/***' --include='/skill/***' --include='/LICENSE' --include='/brand/***' --include='/README.md' \
  --exclude='*' "$here/" "$target:/tmp/parlor-release/"
ssh "$target" 'sudo rsync -a --delete /tmp/parlor-release/ /opt/parlor/ && sudo systemctl restart parlor && sleep 1 && systemctl is-active parlor && curl -s -o /dev/null -w "local check: %{http_code}\n" http://127.0.0.1:8787/'

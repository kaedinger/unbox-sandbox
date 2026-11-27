#!/bin/bash
# Local test deployment on Unraid, equivalent to the CA template.
# Run as root:  [NAME=sandbox] [SHARE=claude-sandbox] [ALLOW="host:port ..."] bash host/deploy.sh
# NAME is the container name, hostname and Remote Control name.
# Layout like Unbox: /mnt/user/<share>/<name>/{home,workspace,backup}.
# The container's state lives in the mounted folders, so recreating it is safe.
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
NAME=${NAME:-sandbox}
ROOT=/mnt/user/${SHARE:-claude-sandbox}/$NAME
ALLOW=${ALLOW:-}

mkdir -p "$ROOT/workspace" "$ROOT/home" "$ROOT/backup"
chown 99:100 "$ROOT/workspace" "$ROOT/home" "$ROOT/backup"

docker build -t claude-sandbox "$REPO/build"

# Icon: without one, Unraid 7.3.2 falls back to a question.png it doesn't ship,
# and the browser requests it in a loop (nginx error per request). dockerMan uses
# a cached <name>-icon.png as is, so the label only has to be non-empty.
ICON=/var/lib/docker/unraid/images/$NAME-icon.png
mkdir -p "${ICON%/*}"
cp "$REPO/unraid/icon.png" "$ICON"
rm -f "/usr/local/emhttp/state/plugins/dynamix.docker.manager/images/$NAME-icon.png"

docker rm -f "$NAME" 2>/dev/null || true
docker run -d --name "$NAME" --hostname "$NAME" \
  --label net.unraid.docker.icon="$ICON" \
  --cap-add NET_ADMIN \
  --memory 6g --cpus 4 --pids-limit 4096 \
  --restart unless-stopped \
  -e SANDBOX_ALLOW="$ALLOW" \
  -v "$ROOT/workspace:/workspace" \
  -v "$ROOT/home:/home/claude" \
  -v "$ROOT/backup:/backup" \
  claude-sandbox

sleep 2
docker logs "$NAME"

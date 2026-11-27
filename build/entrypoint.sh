#!/bin/bash
# Runs as root. Firewalls the container's own network namespace, then drops
# CAP_NET_ADMIN from the bounding set (irrevocable for every descendant) and
# continues as the unprivileged user.
# Fails closed: if the firewall can't be set, nothing else starts.
set -euo pipefail
# Never resolve commands from user-writable directories while root.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if ! /usr/local/bin/firewall.sh; then
  echo "entrypoint: firewall setup failed, refusing to start" >&2
  exit 1
fi

# Map the claude user to PUID/PGID (Unraid default 99:100).
getent group "$PGID" >/dev/null || groupadd -g "$PGID" sandbox
usermod -o -u "$PUID" -g "$PGID" claude
chown "$PUID:$PGID" /home/claude /workspace
# Unraid creates share folders 0777 (and Tools > New Permissions resets them to
# that); a home writable by others is no place for ssh keys and dotfiles.
chmod 755 /home/claude
# Backup archives (sandbox-backup): readable for share-level backups.
if mountpoint -q /backup; then chown "$PUID:$PGID" /backup; chmod 755 /backup; fi

exec setpriv --bounding-set=-net_admin \
  --reuid="$PUID" --regid="$PGID" --init-groups \
  env HOME=/home/claude USER=claude LOGNAME=claude \
  PATH="/home/claude/.local/bin:$PATH" \
  /usr/local/bin/start.sh

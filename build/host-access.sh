#!/bin/bash
# Optional host access for one sandbox: lets its Claude SSH into this host as root.
# Ships in the image (/usr/local/lib/claude-sandbox/host-access.sh) but only works
# on the host: it needs root and the docker socket, which the sandbox has neither
# of. Run as root on the host, taking the script from the sandbox's own image (a
# fresh container from the image never sees changes made inside the sandbox):
#   C=claude-sandbox   # the container name
#   docker run --rm --entrypoint cat "$(docker inspect -f '{{.Image}}' $C)" \
#     /usr/local/lib/claude-sandbox/host-access.sh | bash -s -- $C on
# Actions:
#   key              create Claude's key, print the line for the Unraid UI
#   on|off|status    switch host access for this sandbox only
# HOST and PORT (the host's IP and sshd port) are detected; override via env.
#
# The switch is the container's firewall: "on" inserts an ACCEPT for the host's sshd
# into the container's OUTPUT chain. A container restart re-applies the base rules,
# so host access falls back to off. Claude's key is entered once by hand in the
# Unraid UI (Users > root > SSH authorized keys); this script never edits
# authorized_keys.
#
# While host access is on, Claude runs with prompts: "on" writes managed settings
# that disable bypass and auto mode, restarts Claude (see restart_claude; the
# container keeps running and the conversation continues) and only then opens the
# firewall. "off" closes the firewall, removes the settings and restarts Claude the
# same way, back in bypass mode.
#
# Nothing here executes binaries from the sandbox container itself (Claude could
# have planted them). iptables runs in a fresh container from the same image that
# joins the sandbox's network namespace; files go in via docker cp or a fresh,
# capability-less container (so symlinks in the home can't point at host files).
set -euo pipefail
usage() { echo "usage: host-access.sh <container> key|on|off|status" >&2; exit 2; }
[ $# -ge 1 ] || usage
NAME=$1 ACTION=${2:-status}
[ "$(id -u)" = 0 ] || { echo "run as root on the host" >&2; exit 1; }
docker inspect "$NAME" >/dev/null 2>&1 || { echo "no container named $NAME" >&2; exit 1; }
# The sandbox's home, from the container's config (set by root, not by Claude).
SBHOME=$(docker inspect -f \
  '{{range .Mounts}}{{if eq .Destination "/home/claude"}}{{.Source}}{{end}}{{end}}' "$NAME")
[ -n "$SBHOME" ] && [ -d "$SBHOME" ] ||
  { echo "$NAME has no /home/claude mount; not a claude sandbox?" >&2; exit 1; }
# The host's address on the default route, and its sshd port (on Unraid, port 22
# is often taken by something else, e.g. a Git server's SSH). awk reads to the end:
# exiting early would SIGPIPE the writer, and pipefail would end the script.
HOST=${HOST:-$(ip -4 route get 1.1.1.1 | awk '!h { for (i = 1; i < NF; i++) if ($i == "src") { h = $(i + 1); print h; break } }')}
PORT=${PORT:-$(sshd -T 2>/dev/null | awk '$1 == "port" && !p { print $2; p = 1 }')}
[ -n "$HOST" ] && [ -n "$PORT" ] || { echo "could not detect HOST/PORT; set them in the env" >&2; exit 1; }
MARK="$NAME-host-access"
RULE=(-d "$HOST" -p tcp --dport "$PORT" -m comment --comment "$MARK" -j ACCEPT)
MANAGED=/etc/claude-code/managed-settings.json
PROMPTS_ON='{"permissions":{"disableBypassPermissionsMode":"disable","disableAutoMode":"disable","defaultMode":"default"}}'

img=$(docker inspect -f '{{.Image}}' "$NAME")
ipt() {
  docker run --rm --network "container:$NAME" --cap-drop ALL --cap-add NET_ADMIN \
    --entrypoint iptables "$img" "$@"
}
in_home() {
  docker run --rm -i --network none --cap-drop ALL -u 99:100 \
    -v "$SBHOME:/home/claude" -e HOME=/home/claude --entrypoint bash "$img" -c "$@"
}
set_managed() {
  local f; f=$(mktemp); printf '%s\n' "$1" > "$f"; chmod 644 "$f"
  docker cp "$f" "$NAME:$MANAGED"; rm -f "$f"
}
# Restart Claude in the new permission mode without restarting the container.
# While ~/.switching exists, the autostart loop (build/start.sh) holds Claude back;
# once the switch is complete (see finish_switch) it continues the conversation.
# Every process of the sandbox user is stopped, not just Claude:
# anything a session in the old mode started (background jobs, daemons, other
# tmux windows, an attached tmux client) must not outlive the switch. Spared are
# only the container's own processes, recognised by structure and by having
# started with the container, so a later process can't pass for one of them:
# "sleep infinity" and the tmux server (children of tini), the autostart loop
# (child of the tmux server) and the backup loop (child of "sleep infinity",
# which start.sh exec'd into). Killed from the host by PID; nothing runs inside
# the sandbox.
restart_claude() {
  in_home 'touch ~/.switching'
  trap finish_switch EXIT
  local up pids sig=TERM
  up=$(( $(date +%s) - $(date -d "$(docker inspect -f '{{.State.StartedAt}}' "$NAME")" +%s) ))
  for _ in $(seq 15); do
    pids=$(docker top "$NAME" -eo pid,ppid,uid,etimes,args | awk -v up="$up" '
      NR > 1 {
        n++; pid[n] = $1; ppid[n] = $2; uid[n] = $3; boot[n] = ($4 >= up - 10)
        a = $0; sub(/^ *([^ ]+ +){4}/, "", a); args[n] = a
        if (uid[n] == 0 && a ~ /^\/usr\/bin\/tini /) tini = $1
      }
      END {
        for (i = 1; i <= n; i++)
          if (boot[i] && uid[i] && ppid[i] == tini && args[i] ~ /^tmux new-session /) tmux = pid[i]
        for (i = 1; i <= n; i++) {
          if (boot[i] && tmux && ppid[i] == tmux && args[i] ~ /^bash -c cont=/) loop = pid[i]
          if (boot[i] && uid[i] && ppid[i] == tini && args[i] == "sleep infinity") sinf = pid[i]
        }
        for (i = 1; i <= n; i++)
          if (boot[i] && sinf && ppid[i] == sinf && args[i] == "/bin/bash /usr/local/bin/sandbox-backup") bak = pid[i]
        for (i = 1; i <= n; i++) {
          if (!uid[i]) continue
          if (boot[i] && ppid[i] == tini && (pid[i] == tmux || args[i] == "sleep infinity")) continue
          if (loop && pid[i] == loop) continue
          # the loop waiting for the switch: its own sleep and seq, nothing else
          if (loop && ppid[i] == loop && args[i] ~ /^(sleep [0-9]+|seq [0-9]+)$/) continue
          # the backup loop (start.sh) and its hourly sleep; a running tar is
          # killed and retried an hour later
          if (bak && (pid[i] == bak || (ppid[i] == bak && args[i] ~ /^sleep [0-9]+$/))) continue
          print pid[i]
        }
      }')
    [ -z "$pids" ] && return 0
    # shellcheck disable=SC2086
    kill -"$sig" $pids 2>/dev/null || true
    sig=KILL
    sleep 1
  done
  echo "processes of the sandbox user still running:" >&2
  # shellcheck disable=SC2086
  ps -o pid,stat,args -p "$(echo $pids | tr ' ' ,)" >&2 || true
  return 1
}
# Let the autostart loop bring Claude back (runs on exit, also after an error).
finish_switch() { in_home 'rm -f ~/.switching ~/.resume'; }
rule_on() { ipt -C OUTPUT "${RULE[@]}" 2>/dev/null; }
prompts_on() { docker cp "$NAME:$MANAGED" - 2>/dev/null | tar -xO 2>/dev/null | grep -q disableBypassPermissionsMode; }

case $ACTION in
key)
  in_home '[ -f ~/.ssh/id_ed25519 ] ||
    { mkdir -p -m 700 ~/.ssh && ssh-keygen -q -t ed25519 -N "" -C "$1" -f ~/.ssh/id_ed25519; }' _ "$NAME"
  echo "Add this line in the Unraid UI (Users > root > SSH authorized keys):"
  echo "from=\"172.16.0.0/12\",no-agent-forwarding,no-X11-forwarding $(in_home 'cut -d" " -f1,2 ~/.ssh/id_ed25519.pub') $NAME"
  ;;
on)
  # Pin the host key and add a "host" alias, so Claude just runs "ssh host".
  # ssh refuses a key or config others can access; Unspin promotions and Unraid's
  # New Permissions make them 666.
  in_home 'mkdir -p -m 700 ~/.ssh && chmod 700 ~/.ssh
    touch ~/.ssh/config ~/.ssh/known_hosts
    chmod 600 ~/.ssh/config ~/.ssh/known_hosts ~/.ssh/id_ed25519 2>/dev/null || true
    grep -qxF "$1" ~/.ssh/known_hosts 2>/dev/null || echo "$1" >> ~/.ssh/known_hosts
    grep -q "^Host host$" ~/.ssh/config 2>/dev/null ||
      printf "Host host\n  HostName %s\n  Port %s\n  User root\n" "$2" "$3" >> ~/.ssh/config' \
    _ "[$HOST]:$PORT $(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)" "$HOST" "$PORT"
  if rule_on && prompts_on; then echo "host access is already ON"; exit 0; fi
  ipt -C OUTPUT -d 10.0.0.0/8 -j REJECT 2>/dev/null ||
    { echo "base firewall not in place; host access stays off" >&2; exit 1; }
  # Prompts on before the port opens; nothing from the bypass session survives.
  set_managed "$PROMPTS_ON"
  restart_claude || { echo "host access stays off" >&2; exit 1; }
  rule_on || ipt -I OUTPUT 1 "${RULE[@]}"
  echo "host access ON (ssh host from the sandbox). Claude continues in manual mode in a few seconds."
  ;;
off)
  if ! rule_on && ! prompts_on; then echo "host access is already OFF"; exit 0; fi
  while rule_on; do ipt -D OUTPUT "${RULE[@]}"; done
  set_managed '{}'
  restart_claude || { echo "host access OFF, but Claude could not be restarted" >&2; exit 1; }
  echo "host access OFF. Claude continues in bypass mode in a few seconds."
  ;;
status)
  echo "host access: $(rule_on && echo ON || echo OFF)"
  echo "prompts:     $(prompts_on && echo enforced || echo not enforced)"
  ;;
*) usage ;;
esac

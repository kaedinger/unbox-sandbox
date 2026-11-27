#!/bin/bash
# The mounted home hides the image's skeleton files; restore them once.
[ -f "$HOME/.bashrc" ] || cp -rn /etc/skel/. "$HOME/"
# Default sandbox rules; once present, the user's edits win.
[ -f "$HOME/.claude/CLAUDE.md" ] ||
  install -D -m 644 /usr/local/share/claude-sandbox/CLAUDE.md "$HOME/.claude/CLAUDE.md"
# Daily archive of memory/transcripts into /backup (becomes a child of the
# "sleep infinity" below; host-access.sh recognises it by that).
/usr/local/bin/sandbox-backup &

if [ -f "$HOME/.autostart" ] && command -v claude >/dev/null; then
  # Command passed to new-session directly: no race with shell startup.
  # Remote Control name = hostname, which is set to the container name.
  # Restarts Claude while ~/.autostart exists; afterwards drops to a shell.
  # ~/.switching (held by host-access.sh while it switches the permission mode):
  # wait until it's gone (at most 60 s), then continue the last conversation.
  # SANDBOX_CONTINUE (default yes): also continue it after any other restart
  # (container restart, image update, reboot, crash), if there is one for
  # /workspace. A continued start that ends within 30 s starts fresh next time,
  # so a broken conversation can't keep Claude from coming up.
  tmux new-session -d -s main -c /workspace \
    'keep=; case "${SANDBOX_CONTINUE:-yes}" in [Nn]*|0|[Ff]alse|[Oo]ff) ;; *) keep=1 ;; esac
     cont=
     [ -n "$keep" ] && ls ~/.claude/projects/-workspace/*.jsonl >/dev/null 2>&1 && cont=--continue
     while [ -f ~/.autostart ]; do
       t=$SECONDS
       claude $cont --dangerously-skip-permissions --remote-control "$HOSTNAME"
       rc=$? short=$(( SECONDS - t < 30 )) cont=
       if [ -f ~/.switching ]; then
         echo "claude stopped for a permission mode switch, continuing when done"
         for _ in $(seq 60); do [ -f ~/.switching ] || break; sleep 1; done
         cont=--continue
       else
         [ -n "$keep" ] && [ "$short" = 0 ] && cont=--continue
         echo "claude exited ($rc), restarting in 30 s${cont:+, continuing the conversation} (rm ~/.autostart to stop)"
         sleep 30
       fi
     done
     exec bash'
else
  tmux new-session -d -s main -c /workspace
fi
exec sleep infinity

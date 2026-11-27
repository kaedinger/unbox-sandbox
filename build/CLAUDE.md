# Sandbox rules

You run in a sandboxed container on the user's Unraid server, usually unattended and
with permission prompts off. The sandbox is the boundary; inside it you work freely.

## What you have

- `/workspace`: your projects, one folder per project. Persistent.
- `/home/claude`: your home (Claude Code, settings, credentials). Persistent.
- `/backup`: daily archives of your memory, transcripts and settings, written
  automatically. Leave it alone.
- No root, no sudo. You may install the tools you need yourself, without asking,
  under `~/.local` (static binaries, `python3 -m venv`, `npm --prefix`, ...); they
  persist. List each one in `~/.local/TOOLS.md` (what, where, how to update) and
  check that list before installing anything. For system packages, ask the user
  to add them to the image.
- Internet: open (docs, package registries, GitHub, ...).
- LAN: blocked by a firewall you cannot change. The only exceptions are the ones
  the user configured.

## Outside the sandbox: ask first

- You have no access to the user's other data, machines or accounts, and you must
  not try to get it. Don't probe the LAN, don't try to get around the firewall,
  don't look for ways out of the container.
- If you need files, data, credentials, access or a firewall exception, stop and ask
  the user. Say what you need and why.
- When something is blocked, report it instead of working around it.
- Host access: only while the user switches it on, `ssh host` gives you root on the
  Unraid server. Do only what the task needs there, change nothing else, and never
  try to keep access after it's switched off.
- When host access is switched on or off, you are restarted and the conversation is
  resumed automatically, within seconds. You won't notice the restart itself: don't
  wait for one, and don't ask anyone to restart anything. Afterwards every process
  you started (background jobs, servers, tmux windows) is gone, and the permission
  mode has changed (on: the user approves each action; off: no prompts). Commit
  before you ask for it.
- Other restarts (the container restarted or recreated, an image update, a server
  reboot) also continue the last conversation, unless the user switched that off;
  then you start in a new one. Either way your processes are gone, so keep the
  progress note in the project current.

## Usage limits

The user's plan has usage limits (typically a 5-hour and a 7-day one), and you can
be stopped between any two steps when one runs out. `claude-usage` prints the
current state, e.g. `5h 42% (resets in 2h10m) · 7d 18% (resets in 4d6h) · ok`.

- Run it before long or uninterruptible operations, and every so often during long
  unattended work.
- Leave a consistent state after every step: commit before long or risky steps,
  never leave a repo, release or system half-changed. Keep a short progress note in
  the project so the next session can pick up.
- Operations that must not be interrupted (releases, migrations, anything on the
  Unraid server): make them resumable where possible.
- If it says `near limit` or `unknown`: start nothing big, finish the current step
  cleanly, write down where you are, and tell the user, with the reading and what's
  left to do.

## Secrets

- Never print, log or commit tokens, passwords or keys, including your own in
  `~/.git-credentials` and `~/.claude`.
- Copies of the user's projects may still contain secrets. Don't use them and don't
  spread them; tell the user.

## unbox-sandbox - A Sandboxed Claude Code

A container in which Claude Code works unattended, without permission prompts, while the LAN and the Unraid server stay out of its reach. On every start, it firewalls itself against the LAN (the internet stays open), drops the capability to change those rules, and only then starts Claude as an unprivileged user, in bypass mode, with Remote Control. There's no root and no sudo inside.

It runs on its own from the Docker tab. Its companion is Unbox (coming soon), a plugin that creates and manages several sandboxes and gives a single sandbox root access to the server on demand, with every action approved in Remote Control.

### Links

- **GitHub:** https://github.com/kaedinger/unbox-sandbox
- **Image:** `ghcr.io/kaedinger/unbox-sandbox` (https://github.com/kaedinger/unbox-sandbox/pkgs/container/unbox-sandbox)
- **Issues / feature requests:** https://github.com/kaedinger/unbox-sandbox/issues
- **License:** GPLv2

The README has the details: how it works, first start, host access, configuration.

### Installation

**Not out yet:** the template isn't in Community Applications yet. This post will be updated once it is.

**Via Community Applications:** search for **unbox-sandbox** and click Install. Then, once, in the container's console:

```
su claude -c 'curl -fsSL https://claude.ai/install.sh | bash'
su claude -c '~/.local/bin/claude --dangerously-skip-permissions'   # log in, accept the warning, /exit
su claude -c 'touch ~/.autostart'
```

and restart the container. The sandbox then shows up under its name at claude.ai/code.

### Requirements

- x86_64
- A Claude subscription: Remote Control needs a claude.ai login, an API key isn't enough

### AI disclaimer / History

The sandbox was built so Claude Code could work on Unraid plugins unattended, on the server it develops for, without being able to touch anything else on it. It was designed and written with Claude Code, and tested on my own server.

<sub>Current version when this post was written: 2026.11.28.45982</sub>

FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential pkg-config libfuse3-dev git curl ca-certificates \
      tmux xz-utils unzip rsync openssh-client shellcheck jq \
      python3 python3-pip python3-venv \
      php-cli php-mbstring php-xml php-curl composer \
      tini iptables \
 && rm -rf /var/lib/apt/lists/*
# GitHub CLI from GitHub's apt repo (Ubuntu's package lags behind).
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*
# No sudo: Claude must not be able to change anything that later runs as root
# with CAP_NET_ADMIN (entrypoint on restart, docker exec sessions). It installs
# its own tools under ~/.local.
RUN useradd -m -d /home/claude -s /bin/bash -u 99 -g 100 claude \
 && mkdir -p /etc/claude-code \
 && mkdir -p -m 755 /usr/local/lib/claude-sandbox
COPY --chmod=755 entrypoint.sh firewall.sh start.sh claude-usage sandbox-backup /usr/local/bin/
COPY CLAUDE.md /usr/local/share/claude-sandbox/CLAUDE.md
# Run on the host, never in here (needs root and the docker socket); taken from
# the image so its copy can't be changed from inside a sandbox.
COPY --chmod=644 host-access.sh /usr/local/lib/claude-sandbox/host-access.sh
# PATH stays system-only here (root contexts); the entrypoint adds ~/.local/bin
# for the claude user.
ENV PUID=99 PGID=100 SANDBOX_ALLOW="" SANDBOX_BLOCK="" SANDBOX_CONTINUE=yes
# The Unbox plugin finds every container from this image by this label.
LABEL net.unraid.unbox.sandbox="1"
WORKDIR /workspace
# Runs as root on purpose: the entrypoint sets the firewall, drops
# CAP_NET_ADMIN for good and only then switches to the claude user.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]

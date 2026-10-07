FROM docker.io/library/node:22.23.3-bookworm-slim@sha256:43ac6c60b8f89723f746e8a92ce91abd5017e627ce1ddfe4238355d3a30b772c AS node
FROM ghcr.io/rails/devcontainer/images/ruby:3.4.7

USER root
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
COPY verify-ai-clis.sh /usr/local/bin/verify-ai-clis
COPY install-cloudflared.sh /usr/local/bin/install-cloudflared
RUN usermod -g 100 vscode && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    curl file gh jq less openssh-client postgresql-client procps python3 ripgrep zsh && \
  rm -rf /var/lib/apt/lists/*
RUN sh /usr/local/bin/install-cloudflared
# Official npm distributions; optional dependencies select Linux x64/ARM64 binaries.
# Claude's npm package supplies its native binary without a mutable shell installer.
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
  ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
  npm install --global --prefix /usr/local --include=optional --engine-strict \
    opencode-ai@1.18.33 @openai/codex@0.159.1 @anthropic-ai/claude-code@2.1.285 && \
  npm cache clean --force && chmod 755 /usr/local/bin/verify-ai-clis && \
  install -d -m 700 -o vscode -g 100 /home/vscode/.config/opencode \
    /home/vscode/.cache /home/vscode/.local /home/vscode/.local/share
ENV DISABLE_AUTOUPDATER=1
USER vscode
ENV PATH="/home/vscode/.local/bin:/home/vscode/.local/share/mise/shims:${PATH}"
RUN verify-ai-clis
WORKDIR /prosecho

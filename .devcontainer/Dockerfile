FROM ghcr.io/rails/devcontainer/images/ruby:3.4.7

USER root
RUN usermod -g 100 vscode && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    file jq less postgresql-client procps ripgrep zsh && \
  rm -rf /var/lib/apt/lists/*
USER vscode
ENV PATH="/home/vscode/.local/bin:/home/vscode/.local/share/mise/shims:${PATH}"
WORKDIR /prosecho

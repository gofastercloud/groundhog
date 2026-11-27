# syntax=docker/dockerfile:1
# Lightweight, hardened offline container image for Groundhog agent-box.
# Built locally via `agent-box --build` (auto-built on first run).

FROM ghcr.io/astral-sh/uv:0.9 AS uv-bin

FROM python:3.13-slim

ENV DEBIAN_FRONTEND=noninteractive \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_PYTHON_DOWNLOADS=never \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      git \
      jq \
      make \
      ripgrep \
    && rm -rf /var/lib/apt/lists/*

COPY --from=uv-bin /uv /uvx /usr/local/bin/

# Bake in Groundhog's 7-day supply-chain cooldown for uv.
RUN mkdir -p /etc/uv && printf 'exclude-newer = "7 days"\n' > /etc/uv/uv.toml

# Pre-install fast Python lint/test tools so offline runs work immediately.
RUN uv tool install ruff && uv tool install pytest

# Non-root user with zero host credentials.
RUN groupadd --gid 1000 agent \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash agent \
    && mkdir -p /workspace \
    && chown agent:agent /workspace

USER agent
WORKDIR /workspace
CMD ["/bin/bash"]

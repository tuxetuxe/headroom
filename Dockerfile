# Clean Python base — NOT the upstream image. The upstream GHCR image
# (ghcr.io/chopratejas/headroom:latest) is republished infrequently, which left
# this wrapper lagging behind upstream. The actual product ships as the PyPI
# package `headroom-ai`, released frequently and — crucially — as a prebuilt
# wheel (cp310-abi3-manylinux_2_28_aarch64) that already contains the compiled
# `headroom._core` Rust extension. So we install straight from PyPI and always
# get the latest release, without reproducing upstream's Rust/cargo build.
#
# python:3.13-slim runs as root with HOME=/root, matching this wrapper's
# /root/.headroom and /root/.claude assumptions (the scripts and volumes below).
FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Which headroom-ai to install. Empty = latest on PyPI. The build scripts pass
# the concrete latest version (--build-arg HEADROOM_VERSION=x.y.z) so a manual
# rebuild busts Docker's layer cache exactly when a new release exists — fast
# (cached) when already current, a fresh install when upstream moves.
ARG HEADROOM_VERSION=""

# Install Headroom + extras from PyPI in a single layer:
#   proxy  -> the reverse proxy runtime (previously inherited from the base image)
#   code   -> code-aware context tool (tree-sitter parsers)
#   memory -> persistent semantic memory (hnswlib + sentence-transformers embeddings)
# The memory extra pulls in torch/sentence-transformers, so this layer is large,
# and hnswlib compiles from source — hence the C++ toolchain, installed then
# purged within the same layer to keep the image small. curl + ca-certificates
# are kept (needed by the rtk download below and by any healthcheck).
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential python3-dev curl ca-certificates \
    && pip install --no-cache-dir "headroom-ai[proxy,code,memory]${HEADROOM_VERSION:+==$HEADROOM_VERSION}" \
    && apt-get purge -y build-essential python3-dev \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# rtk (CLI output filter) — lets Headroom's cli_filtering layer detect and use
# it inside the container. Pinned release, checksum-verified. arm64-only, like
# the rest of the image.
ARG RTK_VERSION=0.43.0
RUN asset="rtk-aarch64-unknown-linux-gnu" \
    && cd /tmp \
    && curl -fsSLO "https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/${asset}.tar.gz" \
    && curl -fsSLO "https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/checksums.txt" \
    && grep "${asset}.tar.gz" checksums.txt | sha256sum -c - \
    && tar -xzf "${asset}.tar.gz" -C /usr/local/bin rtk \
    && chmod +x /usr/local/bin/rtk \
    && rm -f "${asset}.tar.gz" checksums.txt

# socat relays the published port to Headroom's loopback listener so the
# dashboard's loopback-only live-message feed works through Docker (kept in
# the final image, unlike the build toolchain above).
RUN apt-get update \
    && apt-get install -y --no-install-recommends socat \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 8787

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD []

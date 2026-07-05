FROM ghcr.io/chopratejas/headroom:latest

# Enable the "code" and "memory" extras.
#   code   -> code-aware context tool (tree-sitter parsers)
#   memory -> persistent semantic memory (hnswlib + sentence-transformers embeddings)
# Note: the memory extra pulls in torch/sentence-transformers, so this layer is large.
# hnswlib compiles from source, so a C++ toolchain is needed at build time.
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential python3-dev \
    && pip install --no-cache-dir "headroom-ai[code,memory]" \
    && apt-get purge -y build-essential python3-dev \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# rtk (CLI output filter) — lets Headroom's cli_filtering layer detect and use
# it inside the container. Pinned release, checksum-verified. arm64-only, like
# the rest of the image.
ARG RTK_VERSION=0.43.0
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && asset="rtk-aarch64-unknown-linux-gnu" \
    && cd /tmp \
    && curl -fsSLO "https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/${asset}.tar.gz" \
    && curl -fsSLO "https://github.com/rtk-ai/rtk/releases/download/v${RTK_VERSION}/checksums.txt" \
    && grep "${asset}.tar.gz" checksums.txt | sha256sum -c - \
    && tar -xzf "${asset}.tar.gz" -C /usr/local/bin rtk \
    && chmod +x /usr/local/bin/rtk \
    && rm -f "${asset}.tar.gz" checksums.txt \
    && rm -rf /var/lib/apt/lists/*

# socat relays the published port to Headroom's loopback listener so the
# dashboard's loopback-only live-message feed works through Docker (kept in
# the final image, unlike the build toolchain above).
RUN apt-get update \
    && apt-get install -y --no-install-recommends socat \
    && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD []

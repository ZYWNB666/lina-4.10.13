FROM jumpserver/lina-base:20260824_094611 AS stage-build

ARG VERSION
ENV VERSION=$VERSION

ADD . /data
WORKDIR /data

RUN --mount=type=cache,target=/root/.yarn/berry/cache,id=lina-yarn-cache \
    yarn --version \
    && yarn install --immutable \
    && sed -i "s@version-dev@${VERSION}@g" src/layout/components/NavHeader/About.vue \
    && yarn build:prod \
    && cp -r /data/lina /opt/lina

# Luna v5.1.0: rebuild its source so selected-text Ctrl+C never sends an interrupt.
FROM node:24-bookworm-slim AS stage-luna
ENV ELECTRON_SKIP_BINARY_DOWNLOAD=1 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    HUSKY=0
RUN apt-get update && apt-get install -y --no-install-recommends patch \
    && rm -rf /var/lib/apt/lists/* \
    && npm install --global pnpm@11.4.0
ADD --checksum=sha256:fadcd13c0006d3b0edae00d1415eeacfadb72d93f03848c60e1e01eb4f852092 \
    https://codeload.github.com/jumpserver/luna/tar.gz/6f0ffe532d542cea3aa3d698255b69786e32a42e /tmp/luna.tar.gz
WORKDIR /data
RUN tar -xzf /tmp/luna.tar.gz --strip-components=1 -C /data && rm /tmp/luna.tar.gz
COPY utils/luna-selection-copy.patch /tmp/luna-selection-copy.patch
RUN patch --batch --fuzz=0 -p1 < /tmp/luna-selection-copy.patch
RUN --mount=type=cache,target=/root/.local/share/pnpm/store,id=luna-pnpm-cache \
    pnpm --filter jumpserver-web... install --frozen-lockfile --config.node-linker=isolated --child-concurrency=2 \
    && pnpm --config.node-linker=isolated --filter jumpserver-web web:generate

# Keep the official v5 web proxy, replacing Lina and patched Luna assets.
FROM jumpserver/web:v5.1.0-ce
COPY --from=stage-build /opt/lina/ /opt/lina/
RUN rm -rf /opt/luna && mkdir /opt/luna
COPY --from=stage-luna /data/.output/public/ /opt/luna/
COPY nginx-luna-bfcache.conf /etc/nginx/conf.d/00-luna-bfcache.conf

# 网页终端 WebSocket(koko)与数据库终端(chen)的反代读/写超时 600s→1800s。
# 官方默认 600s 会在用户标签页被浏览器冻结/休眠/断网约 10 分钟时由 nginx 先于
# koko 的读超时掐断连接(前端报 1006), 与 koko 的 WS_READ_TIMEOUT(默认 30min)对齐。
RUN sed -i -E 's/(proxy_(read|send)_timeout )600;/\11800;/' \
    /etc/nginx/includes/koko.conf /etc/nginx/includes/chen.conf

# Avoid stale HTML after deployment. This header does not prevent background
# tab freezing; terminal connections are protected by the Web Lock script below.
RUN set -eux; \
    sed -i '/location \/luna\/ {/a\        add_header Cache-Control $luna_cache_control always;' \
        /etc/nginx/includes/common.conf; \
    grep -Fq 'add_header Cache-Control $luna_cache_control always;' \
        /etc/nginx/includes/common.conf

# Install the connection guard into Luna's HTML entry points.
# Content hashing prevents stale script caching.
COPY utils/luna-terminal-session-guard.js /tmp/luna-terminal-session-guard.js
COPY utils/install-luna-terminal-guard.sh /tmp/install-luna-terminal-guard.sh
RUN sh /tmp/install-luna-terminal-guard.sh \
    && rm /tmp/luna-terminal-session-guard.js /tmp/install-luna-terminal-guard.sh

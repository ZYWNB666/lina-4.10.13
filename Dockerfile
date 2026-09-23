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

# Keep the official v5 web proxy and Luna assets, replacing only Lina.
FROM jumpserver/web:v5.0.0-ce
COPY --from=stage-build /opt/lina/ /opt/lina/
COPY nginx-luna-bfcache.conf /etc/nginx/conf.d/00-luna-bfcache.conf

# 网页终端 WebSocket(koko)与数据库终端(chen)的反代读/写超时 600s→1800s。
# 官方默认 600s 会在用户标签页被浏览器冻结/休眠/断网约 10 分钟时由 nginx 先于
# koko 的读超时掐断连接(前端报 1006), 与 koko 的 WS_READ_TIMEOUT(默认 30min)对齐。
RUN sed -i -E 's/(proxy_(read|send)_timeout )600;/\11800;/' \
    /etc/nginx/includes/koko.conf /etc/nginx/includes/chen.conf

# Chrome/Edge 149+ 会在 Luna 页面进入 BFCache 时主动关闭 WebSocket,
# 前端因收不到 Koko 结束原因而报 1006。仅对 HTML 导航响应禁用
# BFCache; hashed JS/CSS/图片继续使用浏览器缓存。
RUN set -eux; \
    sed -i '/location \/luna\/ {/a\        add_header Cache-Control $luna_cache_control always;' \
        /etc/nginx/includes/common.conf; \
    grep -Fq 'add_header Cache-Control $luna_cache_control always;' \
        /etc/nginx/includes/common.conf

# New Chrome versions ignore unload handlers by default. Explicitly allow the
# handler for Luna and register one before the terminal app boots so Chrome
# cannot restore a page whose Koko WebSocket has already been closed.
RUN set -eux; \
    sed -i '/location \/luna\/ {/a\        add_header Permissions-Policy "unload=(self)" always;' \
        /etc/nginx/includes/common.conf; \
    grep -Fq 'add_header Permissions-Policy "unload=(self)" always;' \
        /etc/nginx/includes/common.conf; \
    grep -q '</head>' /opt/luna/index.html; \
    snippet='<script>window.addEventListener("unload",function(){});window.addEventListener("pageshow",function(e){if(e.persisted){location.reload();}});</script>'; \
    sed -i "s#</head>#${snippet}</head>#" /opt/luna/index.html; \
    grep -q 'addEventListener("unload"' /opt/luna/index.html; \
    grep -q 'pageshow' /opt/luna/index.html

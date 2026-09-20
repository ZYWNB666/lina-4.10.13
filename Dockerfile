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

# 网页终端 WebSocket(koko)与数据库终端(chen)的反代读/写超时 600s→1800s。
# 官方默认 600s 会在用户标签页被浏览器冻结/休眠/断网约 10 分钟时由 nginx 先于
# koko 的读超时掐断连接(前端报 1006), 与 koko 的 WS_READ_TIMEOUT(默认 30min)对齐。
RUN sed -i -E 's/(proxy_(read|send)_timeout )600;/\11800;/' \
    /etc/nginx/includes/koko.conf /etc/nginx/includes/chen.conf

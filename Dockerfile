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

# Chrome/Edge 允许持有 WebSocket 的页面进入前进/后退缓存(BFCache): 同标签页
# 导航离开时页面被冻结而非销毁, 浏览器会主动掐断页面上的全部 WebSocket(服务端
# 只收到一次干净的 1001 going away, koko 日志无任何异常)。用户后退/返回时页面
# 从 BFCache 恢复, 终端 WS 早已死亡, luna 弹"连接异常中断(关闭码 1006): 未收到
# Koko 结束通知"——浏览器控制台伴随报错"Page entered Back-Forward Cache"。
# 向 lina/luna 入口 HTML 注入自愈脚本: 检测到 BFCache 恢复(pageshow.persisted)
# 立即整页重载, 应用全新启动并重连会话, 替代吓人的断连弹窗。
# 注: 冻结时服务端 SSH 会话已随 WS 关闭, 重载后建立的是新会话(等效于用户手动
# 点重连); 更优雅的原会话重接(reattach)需要 luna 上游支持, 超出镜像 patch 范围。
RUN set -eux; \
    snippet='<script>window.addEventListener("pageshow",function(e){if(e.persisted){location.reload();}});</script>'; \
    for f in /opt/lina/index.html /opt/luna/index.html; do \
        grep -q '</head>' "$f"; \
        sed -i "s#</head>#${snippet}</head>#" "$f"; \
        grep -q 'pageshow' "$f"; \
    done


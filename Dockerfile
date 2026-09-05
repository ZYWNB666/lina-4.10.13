FROM jumpserver/lina-base:20251105_092554 AS stage-build

ARG VERSION
ENV VERSION=$VERSION

ADD . /data

RUN --mount=type=cache,target=/usr/local/share/.cache/yarn,sharing=locked \
    sed -i "s@version-dev@${VERSION}@g" src/layout/components/NavHeader/About.vue \
    && yarn build

# fork 定制: 基于官方 web 镜像叠加 lina 构建产物(保留 /api /koko /ws 等全部反代能力),
# 本镜像可直接替换 jms_web 容器(原 Dockerfile 产物是纯 nginx, 缺少反代, 不能替换)
FROM jumpserver/web:v4.10.13-ce
COPY --from=stage-build /data/lina/ /opt/lina/

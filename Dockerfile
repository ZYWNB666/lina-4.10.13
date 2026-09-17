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

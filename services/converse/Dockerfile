FROM buildpack-deps:trixie-curl@sha256:9e486725325568707dbd794ca9b53cffb7ddee2b8ac1b94941ca4d3d8c6e9df9 AS fetch

ARG CONVERSE_VERSION=14.0.0
ARG CONVERSE_SHA256=634f31fa0f7b0e47f1abc60d870ff6805c737577399920ebe92da4c7e5bcaff0
RUN curl -fsSL "https://github.com/conversejs/converse.js/releases/download/v${CONVERSE_VERSION}/converse.js-${CONVERSE_VERSION}.tgz" -o /tmp/converse.tgz \
    && echo "${CONVERSE_SHA256}  /tmp/converse.tgz" | sha256sum -c - \
    && tar -xzf /tmp/converse.tgz -C /tmp

FROM ghcr.io/nginx/nginx-unprivileged:1.29.8@sha256:18d5312e3b7e455cf9e4fb8becfc2dafaf98063dab542759c2a38708956574b7
COPY --from=fetch /tmp/package/dist /opt/converse/dist

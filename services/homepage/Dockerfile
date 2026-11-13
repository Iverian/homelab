FROM node:24-bookworm-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54 AS builder

ADD --checksum=sha256:60df1f229ac236f0cbc572654f7f766ff55082c24a9a2f083dd850ef64a00ccb \
  https://github.com/gethomepage/homepage/archive/refs/tags/v2.8.0.tar.gz /tmp/homepage.tar.gz
RUN mkdir /src \
  && tar -xzf /tmp/homepage.tar.gz --strip-components=1 -C /src

WORKDIR /src
RUN corepack enable \
  && pnpm install --frozen-lockfile \
  && NEXT_TELEMETRY_DISABLED=1 \
     NEXT_PUBLIC_VERSION=v2.8.0 \
     pnpm run build

FROM node:24-bookworm-slim@sha256:dc26ae92c9fb15cf6b1d63e20f0944b2efe0f115b20e00be48fb23fceb061c54

RUN apt-get update \
  && apt-get install --yes --no-install-recommends ca-certificates curl iputils-ping \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder --chown=node:node /src/public ./public
COPY --from=builder --chown=node:node /src/.next/standalone ./
COPY --from=builder --chown=node:node /src/.next/static ./.next/static

RUN mkdir -p /app/config/logs \
  && chown -R node:node /app/config

USER node
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    HOSTNAME=:: \
    PORT=3000
EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s \
  CMD curl --fail --silent --show-error http://localhost:3000/api/healthcheck >/dev/null || exit 1
CMD ["node", "server.js"]

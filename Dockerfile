FROM hugomods/hugo:nightly AS builder
WORKDIR /src
COPY . .
RUN hugo --gc --minify --noBuildLock

FROM caddy:2.9.1-alpine
WORKDIR /usr/share/caddy
COPY --from=builder /src/public /usr/share/caddy
COPY ./Caddyfile /etc/caddy/Caddyfile

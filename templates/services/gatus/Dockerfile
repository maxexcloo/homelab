FROM ghcr.io/twin/gatus:stable AS gatus
FROM docker.io/tailscale/tailscale:stable AS tailscale
FROM alpine:latest
RUN apk add --no-cache ca-certificates iptables ip6tables \
    && mkdir -p /var/cache/tailscale /var/lib/tailscale /var/run/tailscale
WORKDIR /app
COPY --from=gatus /gatus gatus
COPY --from=tailscale /usr/local/bin/tailscaled tailscaled
COPY --from=tailscale /usr/local/bin/tailscale tailscale
COPY app/ ./
COPY --chmod=755 start.sh start.sh
ENTRYPOINT ["/app/start.sh"]

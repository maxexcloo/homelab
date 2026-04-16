FROM ghcr.io/twin/gatus:stable AS gatus
FROM docker.io/tailscale/tailscale:stable AS tailscale
FROM alpine:latest
RUN apk add --no-cache ca-certificates iptables ip6tables && \
    mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale
COPY --from=gatus /app/gatus /app/gatus
COPY --from=tailscale /usr/local/bin/tailscaled /app/tailscaled
COPY --from=tailscale /usr/local/bin/tailscale /app/tailscale
COPY app/ /app/
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh
ENTRYPOINT ["/app/start.sh"]

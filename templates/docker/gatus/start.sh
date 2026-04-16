#!/bin/sh
/app/tailscaled --socket=/var/run/tailscale/tailscaled.sock --state=/var/lib/tailscale/tailscaled.state &
/app/tailscale up --authkey=$${TAILSCALE_AUTH_KEY} --hostname=${service.identity.name}
/app/gatus

#!/usr/bin/env bash
set -euo pipefail

printf '%s' "${CLOUDFLARE_API_TOKEN}" | podman secret create --replace caddy-cloudflare - >/dev/null

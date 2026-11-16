#!/usr/bin/env bash
set -euo pipefail
umask 077

# dsh's listener must use TLS to issue Secure session cookies.
if [[ ! -e "${STATE_DIRECTORY}/server.crt" && ! -e "${STATE_DIRECTORY}/server.key" ]]; then
  openssl req -x509 -newkey ed25519 -nodes -days 3650 -subj /CN=localhost \
    -addext subjectAltName=DNS:localhost,IP:127.0.0.1 \
    -keyout "${STATE_DIRECTORY}/server.key" -out "${STATE_DIRECTORY}/server.crt"
fi

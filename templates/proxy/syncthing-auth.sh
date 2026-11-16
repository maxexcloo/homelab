#!/usr/bin/env bash
set -euo pipefail

printf '%s' "${SYNCTHING_PASSWORD}" | syncthing generate --gui-password=- --gui-user="${1:?username}"

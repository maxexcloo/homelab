#!/bin/sh
set -eu

# Resolve credentials only in the child process.
# shellcheck disable=SC2016
fnox exec -- sh -c '
  export OP_CONNECT_HOST="$_OP_CONNECT_HOST" OP_CONNECT_TOKEN="$_OP_CONNECT_TOKEN"
  exec tofu "$@"
' sh "$@"

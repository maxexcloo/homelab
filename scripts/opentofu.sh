#!/bin/sh
set -eu

unset OP_CONNECT_HOST OP_CONNECT_TOKEN

# Expand credential references only in the child authenticated by 1Password.
# shellcheck disable=SC2016
exec op run -- sh -c '
  export OP_CONNECT_HOST="$_OP_CONNECT_HOST" OP_CONNECT_TOKEN="$_OP_CONNECT_TOKEN"
  exec tofu "$@"
' sh "$@"

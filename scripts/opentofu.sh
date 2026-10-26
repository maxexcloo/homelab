#!/bin/sh
set -eu

# Resolve credentials only in the child process.
# shellcheck disable=SC2016
run_tofu() {
  fnox exec -- sh -c '
    export OP_CONNECT_HOST="$_OP_CONNECT_HOST" OP_CONNECT_TOKEN="$_OP_CONNECT_TOKEN"
    exec tofu "$@"
  ' sh "$@"
}

# Docker hosts include desktops that may be off, so skip their resources until
# SSH reaches them. The platforms mirror local.docker_hosts.
case "${1:-}" in
  apply | plan)
    # $network and $domain are yq variables.
    # shellcheck disable=SC2016
    hosts="$(yq -r '
      load("data/domains.yaml").domains.infrastructure as $domain
      | .machines
      | to_entries[]
      | .key as $network
      | .value
      | to_entries[]
      | select(.value.platform == "bazzite" or .value.platform == "ucore")
      | .key + "=" + (.value.hostname // .key) + "." + $network + "." + $domain
    ' data/machines.yaml)"
    offline="$(
      for host in ${hosts}; do
        nc -4 -z -G 1 "${host#*=}" 22 2>/dev/null || echo "${host%%=*}" &
      done
      wait
    )"
    resources="$(sed -n 's/^resource "\(docker_[a-z_]*\)" "\([a-z_]*\)".*/\1.\2/p' docker.tf)"
    for host in ${offline}; do
      echo "Skipping offline Docker host ${host}" >&2
      for resource in ${resources}; do
        set -- "$@" "-exclude=${resource}[\"${host}\"]"
      done
    done
    ;;
esac

run_tofu "$@"

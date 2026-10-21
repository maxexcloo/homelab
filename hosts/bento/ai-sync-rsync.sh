#!/bin/sh
# Forced command for kimbap's AI sync key: read only Bento's active model library.
set -eu

refuse() {
  echo "ai-sync-rsync: refused" >&2
  exit 1
}

command=${SSH_ORIGINAL_COMMAND:-}
case $command in
  "rsync --server "*) ;;
  *) refuse ;;
esac
case $command in
  *[\;\&\|\`\$\(\)\<\>\\\'\"\*\?\[]* | *..*) refuse ;;
esac
[ "$command" = "$(printf '%s' "$command" | tr -d '\n\r\t')" ] || refuse

set -f
# shellcheck disable=SC2086 # Split the vetted command into words.
set -- $command
sender=false
for word in "$@"; do
  [ "$word" = --sender ] && sender=true
done
paths=0
for word in "$@"; do
  case $sender:$word in
    *:rsync | *:-* | *:.) continue ;;
    true:ai/models/*) ;;
    *) refuse ;;
  esac
  paths=$((paths + 1))
done
[ "$paths" -gt 0 ] || refuse

cd "$HOME"
exec "$@"

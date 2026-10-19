#!/bin/sh
# Forced command for kimbap's AI sync key: rsync may write only the model
# library and read only Studio's staged workflows and configuration.
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
    false:ai/models/comfyui/*) ;;
    true:ai/config/models.json | true:ai/config/prompting.json | true:ai/studio/data/workflows/*) ;;
    *) refuse ;;
  esac
  paths=$((paths + 1))
done
[ "$paths" -gt 0 ] || refuse

cd "$HOME"
exec "$@"

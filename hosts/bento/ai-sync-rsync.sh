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
[ "$#" -ge 5 ] && [ "$1" = rsync ] && [ "$2" = --server ] && [ "$3" = --sender ] || refuse
shift 3
paths=0
options=true
for word in "$@"; do
  if "$options"; then
    case $word in
      .) options=false; continue ;;
      --list-only | --msgs2stderr | --no-msgs2stderr | --no-specials | --numeric-ids | --safe-links | --stats) continue ;;
      -) refuse ;;
      -*)
        # -e's trailing capability string is protocol data, not more short options.
        printf '%s\n' "$word" | LC_ALL=C grep -Eq '^-[ACDHIORSUWXcdglnopqrtuvxyz]*(e[0-9]*\.[A-Za-z0-9_]*)?$' || refuse
        continue
        ;;
      *) refuse ;;
    esac
  fi
  case $word in
    ai/models/*) ;;
    *) refuse ;;
  esac
  paths=$((paths + 1))
done
[ "$paths" -gt 0 ] || refuse

cd "$HOME"
exec rsync --server --sender "$@"

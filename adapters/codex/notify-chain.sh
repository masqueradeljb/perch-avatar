#!/bin/sh
# Usage in ~/.codex/config.toml (written by `perch setup`):
#   notify = ["/path/notify-chain.sh", "<previous notify argv...>"]
# Codex appends its JSON payload as the last argument; it is passed through to the previous command.
d="$(cd "$(dirname "$0")" && pwd)"
if [ -n "$PERCH_CLI" ]; then
  $PERCH_CLI state done >/dev/null 2>&1 &
else
  node_bin="${PERCH_NODE:-$(command -v node || ls /opt/homebrew/bin/node /usr/local/bin/node 2>/dev/null | head -n1)}"
  if [ -f "$d/../dist/cli.js" ]; then        # npm package layout: <pkg>/assets/notify-chain.sh
    cli="$d/../dist/cli.js"
  else                                        # source checkout: adapters/codex/notify-chain.sh
    cli="$d/../../cli/dist/cli.js"
  fi
  [ -n "$node_bin" ] && [ -f "$cli" ] && "$node_bin" "$cli" state done >/dev/null 2>&1 &
fi
[ "$#" -gt 1 ] && exec "$@"
exit 0

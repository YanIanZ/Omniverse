#!/bin/sh
set -eu
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
for candidate in python3 python3.14 python3.13 python3.12 python3.11; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import tomllib' 2>/dev/null; then
    exec "$candidate" "$ROOT/scripts/install-global.py" "$@"
  fi
done
echo 'Global installation requires Python 3.11+ (tomllib).' >&2
exit 1

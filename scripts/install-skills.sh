#!/bin/sh
# Standard Agent Skills installer; all caller options are passed through unchanged.
set -eu
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
command -v npx >/dev/null 2>&1 || { echo 'Node.js/npm (npx) is required.' >&2; exit 1; }
if [ -d /Volumes/Ext/DevCache ]; then
  export npm_config_cache="${npm_config_cache:-/Volumes/Ext/DevCache/OmniMemo/npm}"
fi
export DISABLE_TELEMETRY="${DISABLE_TELEMETRY:-1}"
exec npx --yes skills@1.5.12 add "$ROOT" "$@"

#!/bin/sh
set -eu
BASE="${OMNIMEM_BUILD_CACHE:-/Volumes/Ext/DevCache/OmniMemo/swift}"
mkdir -p "$BASE/cache" "$BASE/build" "$BASE/config" "$BASE/security"
exec swift "$@" --cache-path "$BASE/cache" --scratch-path "$BASE/build" --config-path "$BASE/config" --security-path "$BASE/security"

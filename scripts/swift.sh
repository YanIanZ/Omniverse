#!/bin/sh
set -eu
# The development machine keeps caches on its Ext disk; elsewhere the macOS user cache.
if [ -d /Volumes/Ext/DevCache ]; then ROOT_DEFAULT=/Volumes/Ext/DevCache/OmniMemo; else ROOT_DEFAULT="$HOME/Library/Caches/OmniMemo"; fi
BASE="${OMNIMEM_BUILD_CACHE:-$ROOT_DEFAULT/swift}"
mkdir -p "$BASE/cache" "$BASE/build" "$BASE/config" "$BASE/security"
exec swift "$@" --cache-path "$BASE/cache" --scratch-path "$BASE/build" --config-path "$BASE/config" --security-path "$BASE/security"

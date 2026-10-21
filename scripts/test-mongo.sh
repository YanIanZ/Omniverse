#!/bin/sh
set -eu
if [ -d /Volumes/Ext/DevCache ]; then ROOT_DEFAULT=/Volumes/Ext/DevCache/OmniMemo; else ROOT_DEFAULT="$HOME/Library/Caches/OmniMemo"; fi
export OMNIMEM_MONGO_ROOT="${OMNIMEM_TEST_MONGO_ROOT:-$ROOT_DEFAULT/test-mongo}"
export OMNIMEM_MONGO_PORT="${OMNIMEM_TEST_MONGO_PORT:-27019}"
exec "$(dirname "$0")/mongodb.sh" "$@"

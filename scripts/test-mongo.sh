#!/bin/sh
set -eu
export OMNIMEM_MONGO_ROOT="${OMNIMEM_TEST_MONGO_ROOT:-/Volumes/Ext/DevCache/OmniMemo/test-mongo}"
export OMNIMEM_MONGO_PORT="${OMNIMEM_TEST_MONGO_PORT:-27019}"
exec "$(dirname "$0")/mongodb.sh" "$@"

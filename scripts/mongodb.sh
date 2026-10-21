#!/bin/sh
# Dedicated local MongoDB; never uses Homebrew's normal dbPath.
set -eu
if [ -d /Volumes/Ext/DevCache ]; then ROOT_DEFAULT=/Volumes/Ext/DevCache/OmniMemo; else ROOT_DEFAULT="$HOME/Library/Caches/OmniMemo"; fi
BASE="${OMNIMEM_MONGO_ROOT:-$ROOT_DEFAULT/mongodb}"
PORT="${OMNIMEM_MONGO_PORT:-27018}"
case "${1:-status}" in
  start)
    mkdir -p "$BASE/db"
    # A reused pid of an unrelated process is not this MongoDB.
    if [ -f "$BASE/mongod.pid" ] && ps -p "$(cat "$BASE/mongod.pid")" -o command= 2>/dev/null | grep -F -- "--dbpath $BASE/db" >/dev/null; then
      echo "OmniMemo MongoDB is already running."
      exit 0
    fi
    exec mongod --dbpath "$BASE/db" --bind_ip 127.0.0.1 --port "$PORT" --wiredTigerCacheSizeGB 0.25 --logpath "$BASE/mongod.log" --pidfilepath "$BASE/mongod.pid" --fork
    ;;
  stop)
    if [ -f "$BASE/mongod.pid" ]; then
      pid="$(cat "$BASE/mongod.pid")"
      case "$pid" in *[!0-9]*|'') echo "Invalid MongoDB pid file" >&2; exit 1 ;; esac
      # Only stop the exact MongoDB process using this dedicated dbPath.
      if ps -p "$pid" -o command= | grep -F -- "--dbpath $BASE/db" >/dev/null; then kill -TERM "$pid"; fi
    fi
    ;;
  status)
    if [ -f "$BASE/mongod.pid" ] && kill -0 "$(cat "$BASE/mongod.pid")" 2>/dev/null; then echo "OmniMemo MongoDB running on $PORT"; else echo "OmniMemo MongoDB stopped"; fi
    ;;
  *) echo "Usage: $0 start|stop|status" >&2; exit 2 ;;
esac

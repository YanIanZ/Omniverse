#!/usr/bin/env bash
# One process, one launch project. No implicit initialization or project fallback.
set -euo pipefail
[[ $# == 3 ]] || { echo 'Usage: global-mcp.sh BINARY DATA_DIR memory|rea' >&2; exit 2; }
BINARY="$1"; DATA="$2"; MODE="$3"
if [[ -n "${OMNIMEM_PROJECT:-}" ]]; then
  PROJECT="$OMNIMEM_PROJECT"
else
  PROJECT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || {
    echo 'OmniMemo: launch from a Git project, set its MCP working directory, or set OMNIMEM_PROJECT explicitly. No default project was selected.' >&2
    exit 1
  }
fi
[[ -d "$PROJECT" && "$PROJECT" == /* ]] || { echo 'OmniMemo: project directory is unavailable.' >&2; exit 1; }
[[ -d "$DATA" && -f "$DATA/meta.json" ]] || { echo 'OmniMemo: storage_unavailable; initialize the configured store explicitly.' >&2; exit 1; }
case "$MODE" in
  memory) exec "$BINARY" --data-dir "$DATA" --project "$PROJECT" mcp serve --stdio ;;
  rea) exec "$BINARY" --data-dir "$DATA" --project "$PROJECT" rea mcp ;;
  *) echo 'OmniMemo: unsupported MCP profile.' >&2; exit 2 ;;
esac

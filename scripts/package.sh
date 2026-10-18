#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/swift.sh build -c release
BIN_DIR="$(./scripts/swift.sh build -c release --show-bin-path)"
DEST="${1:-/Volumes/Ext/DevCache/OmniMemo/dist/0.2.0}"
mkdir -p "$DEST"
cp "$BIN_DIR/omnimem" "$DEST/omnimem"
for asset in "$BIN_DIR"/*.bundle "$BIN_DIR"/*.resources; do
  [ -e "$asset" ] || continue
  cp -R "$asset" "$DEST/"
done
# React is built once here; the release serves static files from Vapor with no Node runtime.
if [ ! -f frontend/dist/index.html ] || [ -n "$(find frontend/src frontend/index.html frontend/package.json -newer frontend/dist/index.html 2>/dev/null)" ]; then
  command -v npm >/dev/null 2>&1 || { echo 'npm is required to build the frontend.' >&2; exit 1; }
  (cd frontend && npm ci --no-audit --no-fund && npm run build)
fi
rm -rf "$DEST/frontend"
cp -R frontend/dist "$DEST/frontend"
ln -sf omnimem "$DEST/om"
cp Package.resolved "$DEST/Package.resolved"
cp LICENSE "$DEST/LICENSE"
REA_RUNTIME="${OMNIMEM_REA_RUNTIME:-/Volumes/Ext/DevCache/OmniMemo/integrations/rea-runtime.json}"
if [ -f "$REA_RUNTIME" ]; then cp "$REA_RUNTIME" "$DEST/rea-runtime.json"; fi
"$DEST/omnimem" --version
printf 'Packaged at %s\n' "$DEST"

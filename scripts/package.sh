#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/swift.sh build -c release
BIN_DIR="$(./scripts/swift.sh build -c release --show-bin-path)"
DEST="${1:-/Volumes/Ext/DevCache/OmniMemo/dist/0.1.0}"
mkdir -p "$DEST"
cp "$BIN_DIR/omnimem" "$DEST/omnimem"
for asset in "$BIN_DIR"/*.bundle "$BIN_DIR"/*.resources; do
  [ -e "$asset" ] || continue
  cp -R "$asset" "$DEST/"
done
cp Package.resolved "$DEST/Package.resolved"
cp LICENSE "$DEST/LICENSE"
"$DEST/omnimem" --version
printf 'Packaged at %s\n' "$DEST"

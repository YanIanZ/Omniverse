#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
./scripts/swift.sh build -c release
BIN_DIR="$(./scripts/swift.sh build -c release --show-bin-path)"
if [ -d /Volumes/Ext/DevCache ]; then ROOT_DEFAULT=/Volumes/Ext/DevCache/OmniMemo; else ROOT_DEFAULT="$HOME/Library/Caches/OmniMemo"; fi
DEST="${1:-$ROOT_DEFAULT/dist/0.3.0}"
mkdir -p "$DEST"
# A new inode: overwriting a signed binary in place gets it killed by the kernel.
rm -f "$DEST/omnimem"
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
# Claude Code plugin (its official replacement for settings hooks), as a local marketplace
# `claude plugin marketplace add <install dir>` reads; engine-written types and tests stay out.
rm -rf "$DEST/claude-plugins" "$DEST/.claude-plugin"
mkdir -p "$DEST/claude-plugins/omniverse-bridge/hooks" "$DEST/.claude-plugin"
cp plugins/omniverse-bridge-mod/hooks/hooks.json plugins/omniverse-bridge-mod/hooks/register.tsx "$DEST/claude-plugins/omniverse-bridge/hooks/"
cp -R plugins/omniverse-bridge-mod/.claude-plugin "$DEST/claude-plugins/omniverse-bridge/"
rm -rf "$DEST/claude-plugins/omniverse-bridge/.claude-plugin/types"
cp -R plugins/omniverse-bridge-mod/types plugins/omniverse-bridge-mod/README.md "$DEST/claude-plugins/omniverse-bridge/"
cat > "$DEST/.claude-plugin/marketplace.json" <<'JSON'
{
  "name": "omnimemo",
  "owner": { "name": "YanIanZ" },
  "plugins": [{ "name": "omniverse-bridge", "source": "./claude-plugins/omniverse-bridge" }]
}
JSON
cp LICENSE "$DEST/LICENSE"
# Unset: the development default. Set but empty: package without an REA runtime.
REA_RUNTIME="${OMNIMEM_REA_RUNTIME-$ROOT_DEFAULT/integrations/rea-runtime.json}"
if [ -n "$REA_RUNTIME" ] && [ -f "$REA_RUNTIME" ]; then cp "$REA_RUNTIME" "$DEST/rea-runtime.json"; fi
"$DEST/omnimem" --version
printf 'Packaged at %s\n' "$DEST"

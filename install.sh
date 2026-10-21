#!/usr/bin/env bash
# Build/install locally. Project and database setup require explicit flags.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${OMNIMEM_PREFIX:-$HOME/.local}"
if [[ -d /Volumes/Ext ]]; then CACHE_DEFAULT=/Volumes/Ext/DevCache/OmniMemo; else CACHE_DEFAULT="$HOME/Library/Caches/OmniMemo"; fi
CACHE="${OMNIMEM_INSTALL_CACHE:-$CACHE_DEFAULT}"
DATA="${OMNIMEM_HOME:-$HOME/Library/Application Support/OmniMemo/data}"
PROJECT="$PWD"
URI=mongodb://127.0.0.1:27018/omnimemo
BACKEND=mongodb
AGENTS=codex,claude
SETUP=0; START_MONGO=0; WITH_REA=0; DRY_RUN=0; GLOBAL=0; WITH_HOOKS=0
fail() { printf 'OmniMemo installer: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'EOF'
Usage: bash install.sh [options]
  --prefix PATH       Install bin/omnimem and lib/omnimemo (default: ~/.local)
  --cache-dir PATH    Build/REA cache (default: Ext DevCache, or macOS user cache)
  --data-dir PATH     Memory metadata/cache (default: macOS user application data)
  --project PATH      Project for --setup (default: current directory)
  --setup             Initialize memory and apply project Codex/Claude adapters
  --global            Register MCP + npx skills for detected user-level hosts
                      (Python 3.11+ and Node/npm required; preview with --dry-run)
  --with-hooks        With --global, add lifecycle presence: Claude Code plugin, Codex/Gemini hooks (opt-in)
  --agents LIST       Project adapters: codex,claude (default: both)
  --backend NAME      Storage profile for --setup: mongodb (default) or sqlite (no server needed)
  --mongo-uri URI     Existing mongodb:// server; OMNIMEM_MONGO_URI overrides it (use it for secrets)
  --start-mongo       With --setup, start the dedicated local server on port 27018
  --with-rea          Prepare the pinned Node REA runtime and include its skills
  --dry-run           Print the plan without building, downloading or writing
  -h, --help          Show help
Requires macOS, Swift 6+, and Git. Setup with the mongodb backend requires a running MongoDB server.
REA additionally requires compatible Node/npm and Python 3. No sudo, shell-profile
changes, global agent config, Git hooks or Homebrew services are installed.
EOF
}
while (($#)); do
  case "$1" in
    --prefix|--cache-dir|--data-dir|--project|--agents|--mongo-uri|--backend)
      (($# >= 2)) && [[ -n "$2" && "$2" != --* ]] || fail "Missing value for $1"
      case "$1" in
        --prefix) PREFIX="$2" ;; --cache-dir) CACHE="$2" ;; --data-dir) DATA="$2" ;;
        --project) PROJECT="$2" ;; --agents) AGENTS="$2" ;; --mongo-uri) URI="$2" ;; --backend) BACKEND="$2" ;;
      esac
      shift 2 ;;
    --global) GLOBAL=1; shift ;; --with-hooks) WITH_HOOKS=1; shift ;;
    --setup) SETUP=1; shift ;; --start-mongo) START_MONGO=1; shift ;;
    --with-rea) WITH_REA=1; shift ;; --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;; *) fail "Unknown option: $1" ;;
  esac
done
for path in "$PREFIX" "$CACHE" "$DATA" "$PROJECT"; do
  [[ "$path" == /* && "$path" != / && "$path" != *$'\n'* ]] || fail 'Paths must be absolute, non-root paths without newlines.'
  case "$path" in
    /Volumes/*)
      volume="${path#/Volumes/}"; volume="/Volumes/${volume%%/*}"
      if ! /sbin/mount | /usr/bin/grep -Fq -- " on $volume ("; then
        fail "External volume is not mounted: $volume"
      fi ;;
  esac
done
[[ "$URI" == mongodb://* && "$URI" != *@* ]] || fail 'Use mongodb:// without credentials; supply credentials via OMNIMEM_MONGO_URI.'
case ",$AGENTS," in *,codex,*|*,claude,*) ;; *) fail 'Choose codex and/or claude adapters.' ;; esac
IFS=, read -r -a selected_agents <<< "$AGENTS"
for agent in "${selected_agents[@]}"; do [[ "$agent" == codex || "$agent" == claude ]] || fail 'Unsupported project adapter.'; done
((!WITH_HOOKS || GLOBAL)) || fail '--with-hooks requires --global.'
[[ "$BACKEND" == mongodb || "$BACKEND" == sqlite ]] || fail '--backend must be mongodb or sqlite.'
[[ "$BACKEND" == mongodb || "$START_MONGO" == 0 ]] || fail '--start-mongo is only for the mongodb backend.'
if ((START_MONGO)); then
  ((SETUP)) || fail '--start-mongo requires --setup.'
  [[ "$URI" == mongodb://127.0.0.1:27018/* ]] || fail '--start-mongo requires loopback port 27018.'
  [[ -z "${OMNIMEM_MONGO_URI:-}" ]] || fail '--start-mongo cannot be combined with OMNIMEM_MONGO_URI.'
fi
printf 'Install CLI: %s/bin/omnimem\nCache: %s\n' "$PREFIX" "$CACHE"
if ((WITH_REA)); then printf 'Prepare pinned REA runtime and full skill.\n'; fi
if ((SETUP)); then
  printf 'Initialize data: %s\n' "$DATA"
  if ((!GLOBAL)); then printf 'Apply %s adapters to: %s\n' "$AGENTS" "$PROJECT"; fi
fi
if ((START_MONGO)); then printf 'Start dedicated MongoDB on loopback port 27018.\n'; fi
if ((GLOBAL)); then printf 'Register detected global MCP hosts and install skills with npx.\n'; fi
if ((DRY_RUN)); then exit 0; fi
[[ "$(uname -s)" == Darwin ]] || fail 'Only macOS is currently supported.'
for tool in swift git; do command -v "$tool" >/dev/null || fail "Missing $tool. Install Swift 6+ and Xcode Command Line Tools first."; done
SWIFT_VERSION="$(swift --version)"
if [[ ! "$SWIFT_VERSION" =~ Swift\ version\ ([0-9]+) ]]; then fail 'Cannot parse Swift version.'; fi
if ((BASH_REMATCH[1] < 6)); then fail 'Swift 6 or newer is required.'; fi
if ((SETUP)); then [[ -d "$PROJECT" ]] || fail 'Project directory does not exist.'; fi
if ((START_MONGO)); then command -v mongod >/dev/null || fail 'mongod is missing. Install MongoDB Community first.'; fi
if ((WITH_REA)); then
  for tool in python3 node npm; do command -v "$tool" >/dev/null || fail "Missing $tool for REA."; done
fi
if ((GLOBAL)); then
  command -v npx >/dev/null || fail 'Node/npm (npx) is required for global skills.'
  "$ROOT/scripts/install-global.sh" --help >/dev/null
fi
TARGET="$PREFIX/lib/omnimemo"
LAUNCHER="$PREFIX/bin/omnimem"
OM_LAUNCHER="$PREFIX/bin/om"
LAUNCHER_TEXT="$(cat <<'EOF'
#!/bin/sh
# OmniMemo installer launcher v1
exec "$(CDPATH='' cd -- "$(dirname -- "$0")/../lib/omnimemo" && pwd)/omnimem" "$@"
EOF
)"
# Refuse to replace unrelated installations or follow redirected destination leaves.
for path in "$PREFIX/bin" "$PREFIX/lib" "$TARGET" "$LAUNCHER" "$OM_LAUNCHER"; do [[ ! -L "$path" ]] || fail "Destination is a symlink: $path"; done
if [[ -e "$TARGET" || -e "$LAUNCHER" ]]; then
  [[ -f "$TARGET/.omnimemo-install" ]] && [[ "$(cat "$TARGET/.omnimemo-install")" == 'YanIanZ/OmniMemo installer v1' ]] || fail 'Destination already exists and is not owned by this installer.'
  if [[ -e "$LAUNCHER" ]]; then
    [[ "$(cat "$LAUNCHER")" == "$LAUNCHER_TEXT" ]] || fail 'Existing launcher was changed; review it before reinstalling.'
  fi
fi
export OMNIMEM_BUILD_CACHE="${OMNIMEM_BUILD_CACHE:-$CACHE/swift}"
# Do not accidentally bundle a runtime pointer from the development-machine default, nor a
# pointer an earlier --with-rea run left in the cache: empty means no REA runtime.
if ((WITH_REA)); then export OMNIMEM_REA_RUNTIME="$CACHE/integrations/rea-runtime.json"; else export OMNIMEM_REA_RUNTIME=''; fi
if ((WITH_REA)); then python3 "$ROOT/scripts/prepare-rea.py" --base "$CACHE"; fi
mkdir -p "$PREFIX/bin" "$PREFIX/lib"
LOCK="$PREFIX/lib/.omnimemo-install.lock"
mkdir "$LOCK" 2>/dev/null || fail 'Another installation is active (or its lock needs review).'
STAGE=""; OLD=""; COMMITTED=0
cleanup() {
  [[ -z "$STAGE" ]] || rm -rf -- "$STAGE"
  if [[ -n "$OLD" && -d "$OLD" ]]; then
    # The previous install is dropped only once the new launcher has answered.
    if ((COMMITTED)); then rm -rf -- "$OLD"
    else [[ ! -e "$TARGET" ]] || rm -rf -- "$TARGET"; mv -- "$OLD" "$TARGET"; fi
  fi
  rmdir "$LOCK"
}
trap cleanup EXIT
STAGE="$(mktemp -d "$PREFIX/lib/.omnimemo-stage.XXXXXX")"
"$ROOT/scripts/package.sh" "$STAGE"
printf 'YanIanZ/OmniMemo installer v1\n' > "$STAGE/.omnimemo-install"
printf '%s\n' "$LAUNCHER_TEXT" > "$STAGE/launcher"
chmod +x "$STAGE/launcher"
if [[ -e "$TARGET" ]]; then
  OLD="$(mktemp -d "$PREFIX/lib/.omnimemo-old.XXXXXX")"
  rmdir "$OLD"
  mv -- "$TARGET" "$OLD"
fi
mv -- "$STAGE" "$TARGET"; STAGE=""
mv -f -- "$TARGET/launcher" "$LAUNCHER"
# Short `om` alias; never replace an unrelated command of the same name.
if [[ ! -e "$OM_LAUNCHER" || "$(cat "$OM_LAUNCHER")" == "$LAUNCHER_TEXT" ]]; then
  printf '%s\n' "$LAUNCHER_TEXT" > "$OM_LAUNCHER"; chmod +x "$OM_LAUNCHER"
else
  printf 'Skipped %s: an unrelated file exists; use omnimem instead.\n' "$OM_LAUNCHER"
fi
"$LAUNCHER" --version
COMMITTED=1
# Claude Code runs its own copy of an installed plugin; refresh it so new sessions get this code.
# Captured first: with pipefail, `grep -q` closing the pipe early would read as "not installed".
if command -v claude >/dev/null && [[ "$(claude plugin list 2>/dev/null || true)" == *'omniverse-bridge@omnimemo'* ]]; then
  claude plugin marketplace update omnimemo >/dev/null && claude plugin update omniverse-bridge@omnimemo \
    || printf 'Claude Code plugin not refreshed; run: claude plugin update omniverse-bridge@omnimemo\n'
fi
if ((START_MONGO)); then
  OMNIMEM_MONGO_ROOT="${OMNIMEM_MONGO_ROOT:-$CACHE/mongodb}" OMNIMEM_MONGO_PORT=27018 "$ROOT/scripts/mongodb.sh" start
fi
if ((SETUP)); then
  if [[ "$BACKEND" == sqlite ]]; then
    init_args=(--data-dir "$DATA" --project "$PROJECT" init --backend sqlite)
  else
    init_args=(--data-dir "$DATA" --project "$PROJECT" init --mongo-uri "$URI")
  fi
  if ((GLOBAL)); then init_args+=(--set-default); fi
  "$LAUNCHER" "${init_args[@]}"
  if ((!GLOBAL)); then
  install_args=(--data-dir "$DATA" --project "$PROJECT" install --agents "$AGENTS" --apply)
  if ((WITH_REA)); then install_args+=(--with-rea); fi
  "$LAUNCHER" "${install_args[@]}"
  fi
fi
if ((GLOBAL)); then
  global_args=(--binary "$TARGET/omnimem" --data-dir "$DATA" --state-dir "$CACHE/global-install" --apply --install-skills)
  if ((WITH_REA)); then global_args+=(--with-rea); fi
  if ((WITH_HOOKS)); then global_args+=(--with-hooks); fi
  "$ROOT/scripts/install-global.sh" "${global_args[@]}"
fi
printf '\nInstalled: %s\nAdd %s/bin to PATH if needed; no shell profile was changed.\n' "$LAUNCHER" "$PREFIX"
if ((SETUP)); then printf 'Restart your agent and approve its project MCP servers.\n'; fi

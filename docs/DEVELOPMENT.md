# Development

How to build, test and package OmniMemo from a checkout. For installing it as a user, see
[INSTALLATION.md](INSTALLATION.md).

## Prerequisites

- macOS (Apple Silicon is the tested platform), Swift 6+ and Xcode Command Line Tools, Git
- MongoDB Community (`mongod`) for the database tests and the `mongodb` profile
- Node/npm for the frontend, the skills installer and the optional REA runtime
- Python 3.11+ for the smoke tests and the global installer
- Claude Code, only to validate and test the `omniverse-bridge` plugin

## Where build output goes

The scripts keep caches and artifacts outside the checkout:

| What | Default | Override |
|---|---|---|
| Swift caches and build output | `~/Library/Caches/OmniMemo/swift` | `OMNIMEM_BUILD_CACHE` |
| Packaged release | `~/Library/Caches/OmniMemo/dist/0.3.0` | first argument of `scripts/package.sh` |
| Dedicated MongoDB | `~/Library/Caches/OmniMemo/mongodb` | `OMNIMEM_MONGO_ROOT`, `OMNIMEM_MONGO_PORT` |
| Test MongoDB | `~/Library/Caches/OmniMemo/test-mongo` (port 27019) | `OMNIMEM_TEST_MONGO_ROOT`, `OMNIMEM_TEST_MONGO_PORT` |
| REA runtime pointer | `~/Library/Caches/OmniMemo/integrations/rea-runtime.json` | `OMNIMEM_REA_RUNTIME` (empty: none) |

On the maintainer's machine these defaults are under `/Volumes/Ext/DevCache/OmniMemo` when that
disk is mounted; nothing else depends on it.

## Build and package

```sh
./scripts/swift.sh build              # debug build
./scripts/package.sh                  # release build + resources + frontend/dist + Claude plugin
./scripts/package.sh /tmp/omnimemo    # into another directory
```

Keep the executable and its `*.bundle`/`*.resources` directories together. No Xcode project
or application server is needed.

Frontend (Mission Control):

```sh
cd frontend
npm ci
npm run dev        # with: om serve --dev-origin http://127.0.0.1:5173
npm run build      # typecheck + production build into frontend/dist
```

## Run a local database and a project

```sh
./scripts/mongodb.sh start            # loopback 127.0.0.1:27018; never a Homebrew service
BIN=~/Library/Caches/OmniMemo/dist/0.3.0/omnimem
DATA="$HOME/Library/Application Support/OmniMemo/data"
"$BIN" --data-dir "$DATA" --project "$PWD" init --mongo-uri mongodb://127.0.0.1:27018/omnimemo
"$BIN" --data-dir "$DATA" --project "$PWD" status
./scripts/mongodb.sh stop
```

No database server? Use `init --backend sqlite` instead.

## Tests

```sh
./scripts/test-mongo.sh start         # dedicated test server on port 27019
OMNIMEM_TEST_MONGO_URI=mongodb://127.0.0.1:27019/omnimemo_tests ./scripts/swift.sh test
./scripts/test-mongo.sh stop
```

Without `OMNIMEM_TEST_MONGO_URI` the database tests are reported as skipped. Set
`OMNIMEM_TEST_REA_MANIFEST` to a prepared `rea-runtime.json` to include the REA tests, and
`OMNIMEM_TEST_ROOT` to choose where test workspaces are created.

Smoke tests run against a packaged binary:

```sh
BIN=~/Library/Caches/OmniMemo/dist/0.3.0/omnimem
python3 Tests/mcp_smoke.py "$BIN"
python3 Tests/cli_smoke.py "$BIN"      # Python 3.11+
python3 Tests/office_smoke.py "$BIN"   # needs redis-server on PATH
python3 Tests/rea_smoke.py "$BIN"      # needs a packaged REA runtime
```

The Claude Code plugin:

```sh
claude plugin validate plugins/omniverse-bridge-mod
claude plugin test plugins/omniverse-bridge-mod
```

Recorded results and their limits are in [VALIDATION.md](VALIDATION.md).

## REA runtime (optional)

```sh
python3 scripts/prepare-rea.py        # pinned Node runtime under the cache root
./scripts/package.sh                  # bundles the runtime pointer
"$BIN" rea status
```

See [REA.md](REA.md) for capabilities and engine prerequisites.

## Repository layout

| Path | Contents |
|---|---|
| `Sources/OmniMemoCore` | memory store, context, rollover, runtime events, adapters; canonical skills in `Skills/` |
| `Sources/omnimem` | the CLI and MCP stdio server (`om`) |
| `Sources/OmniServer` | Vapor HTTP/WebSocket server for Mission Control |
| `frontend/` | Mission Control (React + TypeScript + Vite) |
| `plugins/omniverse-bridge-mod` | Claude Code plugin: lifecycle, agent cards, context rollover |
| `scripts/` | build, package, install and local database scripts |
| `skills/` | distribution symlink to the canonical skills for `npx skills` |
| `Tests/` | XCTest suites and Python smoke tests |
| `docs/` | install, development, runtime contracts, and the supplied PRDs/specs |
| `*.example.toml` | example configuration for the optional components |

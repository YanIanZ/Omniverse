# OmniMemo v1.9 — Swift + Vapor + React Technical Architecture

**Canonical:** `OmniMemo_PRD_v1.9_Swift_Vapor_React.md` §§112–126. This is a design spec, not runnable software.

## Design decisions

- All backend functions including `om` CLI, MCP stdio, runtime coordination and HTTP API are Swift 6.
- Vapor 4 is the **only HTTP server**, including REST API, WebSocket endpoint and static production hosting.
- React + TypeScript + Vite is the **frontend**, not a backend. Production loads built `dist/` from Vapor.
- MongoDB is durable truth and Redis is bounded disposable cache / live signals. React never reads DBs directly.
- Optional SQLite-only mode is retained when low footprint matters; disable entire HTTP process when not needed.
- The first supported host hook and MCP discovery signal wake OmniMemo lazily. Unavailable IDE startup hooks never trigger fictitious sessions.

## Process topology

```text
Agent IDEs / Terminals / CLI
  ├── official events/hooks -> om wake / om context / om checkpoint
  └── MCP stdio -----------                             Swift Core + MongoDB + Redis
User -> om office -> Vapor HTTP + WebSocket -> React Mission Control
                                  |                ^
                                  +--- /api + /ws -+
```

Vapor and MCP are separate executable entrypoints sharing only the Swift domain layer and MongoDB data. The Vapor server does not have to remain running for core MCP calls. Redis is never used as unique durable storage.

## API

- `GET /api/v1/health`
- `GET /api/v1/agents`
- `GET, POST /api/v1/tasks`
- `PATCH /api/v1/tasks/:id` conditional version writes
- `GET /api/v1/memory/search`
- `GET /api/v1/events` bounded reconnect event history
- `POST /api/v1/approvals/:id/decision` human confirmation only
- `GET /ws/v1/live` WebSocket event stream

WebSocket messages are versioned and typed; task changes are committed to MongoDB before broadcasting. Use heartbeat expiry and `unknown` statuses when telemetry is missing. Authenticate the browser and validate WebSocket Origin / allowed project scope.

## React Views

1. Dashboard: online/unknown agents, current tasks, issues and degraded storage.
2. Office 2D: DOM/CSS/SVG avatars for verified activities only; no agent spawning to drive animations.
3. Tasks: Kanban, assignment, handoff and real test outcomes.
4. Agent Detail: runtime provider, claimed capabilities, confidence and heartbeat.
5. Approvals: require fresh user actions and verified server-side authorization.
6. Memory Explorer and Settings: scoped memory / token cache / diagnostic health.

## Startup modes

- `om status`: direct CLI status; does not start UI by default.
- `om wake`: idempotent lifecycle signal from approved client hook, no duplicate daemon.
- First prompt: short pre-prompt context only on supported host events; unknown hosts use manual commands/MCP fallback.
- `om office`: start or reuse one Vapor server instance, then open dashboard.
- `om serve`: foreground Vapor process; explicit startup at login is opt-in.
- `om stop`: stops only OmniMemo-owned service (never external Mongo/Redis server).

## Packaging

```text
backend/  SwiftPM modules / Vapor / CLI / MCP
frontend/ React / TypeScript / Vite
skills/   Host-neutral opt-in instructions
```

`pnpm build` or `npm run build` in the frontend produces `dist`; Vapor serves `dist` at `/`, with proper fallback for client-side routes but never for `/api` or `/ws`. Vite development proxy forwards `/api` and `/ws` to Vapor. No production Node.js server is required.

## Engineering warnings

- The official MongoDB Swift server driver is archived; validate MongoKitten against actual Swift/Mongo versions before commit.
- RediStack transition and Valkey-Swift compatibility require version-specific verification for Redis; do not assume newest Redis supports all commands.
- Swift strict concurrency requires protecting mutable state and testing JSON send/receive races in WebSocket hub.
- Single-process WebSocket fanout suffices until measured multi-process deployment. Redis signals are optional and never authoritative.
- Avoid heavy UI frameworks or an extra microservice without measured benefit.
- Local HTTP bind != authentication; provide secure origin/token/scoping controls.
- `YanIanZ` identity and per-push user approval remain mandatory.

## Validation tests

See PRD §§122–123. Prioritize Swift core + one real host hook + one Vapor WS event + one React status card; all remaining UI is incremental.

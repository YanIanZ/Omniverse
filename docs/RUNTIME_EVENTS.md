# Runtime adapter contract (v2.3 + v2.4 context)

Adapters send normalized JSON to the existing workspace-bound Vapor server. Events
describe observed activity; they do not grant task ownership, process control or approval.
Use supported host hooks/plugins or an explicitly managed Codex app-server session.
Externally opened Codex sessions remain limited/manual.

## Event fields

| JSON field | Contract |
| --- | --- |
| `schema_version` | Required string: `"1"` or `"2.3"`. |
| `event_id` | Required UUID; reuse it on retries. |
| `source` | Required adapter label, e.g. `claude_hook`. |
| `provider` | Required: `claude`, `codex`, `opencode`, `gemini`. |
| `external_session_id` | Required stable host session label; never use a model name as identity. |
| `workspace_id` | Optional; must match the server binding ID or `local`. Omission uses the server binding. |
| `event_type` | Required member of the list below. |
| `occurred_at` | Required ISO 8601 timestamp (fractional seconds accepted), less than one day into the future. |
| `received_at` | Optional string; server receipt time is authoritative for last seen. |
| `sequence` | Optional integer, increasing within a session. |
| `model_id` | Optional reported model label, 1–80 UTF-8 bytes; omit when unavailable. |
| `task_id` | Optional task label; needed with `task.assigned` to link a card. |
| `milestone_id` | Optional milestone label; required along with `task_id` for `milestone.verified`. |
| `status` | Optional compatibility field; state is derived from event type, not this value. |
| `source_confidence` | Required: `observed`, `reported`, `inferred`. |
| `metadata` | Optional object of allowlisted scalar values (string, number, bool, null); no arrays or nested objects. |

Source, external session, task and milestone labels use 1–128 UTF-8 bytes and only
`A-Z a-z 0-9 . _ : -`. UUIDs are normalized to lowercase for deduplication.

Allowed metadata keys: `tool_category`, `error_kind`, `observability`, `title`,
`client_version`, `turn_id`, `reason`, `permission_mode`. Unknown keys are rejected.
Non-null values are converted to text and truncated to 120 characters by ingest.
`observability` is `managed` or `passive`; a new session defaults to passive.
Titles require the workspace's title-saving opt-in; only the first line, up to
80 characters, is used on the session card.

## Event types and status

| Event types | State proved |
| --- | --- |
| `session.started`, `session.resumed`, `turn.completed`, `turn.failed` | `waiting` |
| `prompt.received`, `tool.started`, `tool.succeeded`, `tool.failed` | `working` |
| `task.blocked`, `approval.requested` | `blocked` |
| `session.ended` | `offline` |
| `model.changed`, `task.assigned`, `milestone.verified`, `heartbeat` | Preserve current state |

These are all allowed event types. A new session begins in `waiting`. Legacy
`ready`/`active`/`disconnected` map to `waiting`/`working`/`offline`.
Tool events set `tool_category` (default `unknown`); session start/resume/end and
turn completion/failure clear it. Map host tool names with `RuntimeMapping` to
`file_edit`, `file_read`, `search`, `shell`, `web`, `subagent`, `planning`, `mcp`,
`other` or `unknown`. Do not send raw tool names containing user data.

## Deduplication, ordering and presence

Within the bound project, the dedup key is
`provider|external_session_id|event_id`. A duplicate changes neither session state
nor event count nor durable event cursor. Different providers/sessions may reuse
an event UUID. Validation occurs before claiming the key.
Dedup claims are retained for seven days (MongoDB TTL cleanup is asynchronous);
adapters should not depend on indefinite replay protection.

An event is older if its sequence is lower than the last applied sequence **or**
its occurrence timestamp predates the last applied timestamp. Older events are
accepted and counted, refresh server receipt time and produce an activity event,
but do not replace the applied status, model, task link, tool category or last
event/sequence. Equal sequence and timestamp are not considered older. Source
and observability describe receipt and may still update. Milestone verification
is processed separately from session ordering.

Last seen uses server receipt time, not adapter occurrence time. Silence longer
than 45 seconds for managed sessions or 600 seconds for passive sessions derives
`stale` on reads, preserving last seen and the durable status. Observed `offline`
remains offline. Passive hooks must not invent heartbeats. Silence never proves
completion or an observed session end.

The internal `runtime_id` is stable per provider/session. Model changes update
the display label only; absent model metadata yields `model-unavailable`.

## Milestones and progress

Add milestones to an existing task using `addMilestone`; titles are 1–160 UTF-8
bytes, weight is 1–100, and at most 50 milestones are allowed. Verify/revert with
`setMilestone`, including 1–240 UTF-8 bytes of evidence. Mutations use task revision
checks and emit `task.updated`. `milestone.verified` requires both IDs and attempts
verification with an event/source evidence reference, only when the task is the one
assigned to that session (`task.assigned`); for any other task it is recorded as activity. Acceptance of the event
alone does not prove that the referenced milestone was updated; read task state.

Without milestones, progress is `indeterminate` with no percentage. Otherwise it
is `determinate`: floor(100 × verified weight / total weight), with `completed`
and `total` milestone counts. Tool counts, time and tokens are never progress.

## HTTP and authentication

| Route | Response |
| --- | --- |
| `POST /api/runtime/events` | `202` accepted or `200` duplicate; JSON `accepted`, `duplicate`, `cursor`, `status`. Duplicate cursor/status are null. |
| `GET /api/runtime/sessions` | `workspace_id` and `agents` cards with derived status/progress. |
| `GET /api/runtime/tasks` | `tasks`, each containing `task` and `progress`. |
| `GET /api/runtime/health` | Storage health, workspace ID, event revision and Redis state. |

Use `Authorization: Bearer <configured server token>` for adapters. Browser session
cookies also authenticate; `/auth` mints a random session value for the cookie, never
the server token itself, so the token sent as a cookie is refused. Cookie-authenticated
writes require an allowed `Origin`. Any supplied Origin must be allowed, including bearer requests. Host
validation and the server's configured request limits also apply. Never include
tokens in event JSON. Missing/invalid authentication returns `401`; rejected scope
or Origin returns `403`; malformed/invalid events return `400`; detected secrets
return `422`; unavailable storage returns `503`.

Sessions/tasks GET routes accept optional `workspace_id`, restricted to the
binding ID or `local`. POST checks the event's `workspace_id`. Durable writes
precede broadcast; accepted events trigger polling of the committed event stream.
`/ws/office` is the authenticated, Origin-checked office WebSocket stream; reconnect
clients must reconcile snapshots and missed durable events.

## Privacy

Send categories and short, consented task labels only. Never send prompts,
transcripts, source text, tool arguments, credentials, API keys or secrets in any
field. `prompt.received` is a signal, not permission to attach prompt content.
Secret filtering is a defense in depth, not a replacement for adapter-side data
minimization. An allowlisted `reason` or `title` key does not authorize arbitrary
text capture. Metadata and model labels are secret-checked; unknown metadata keys
are rejected rather than retained.

## Host adapters

| Host | Adapter | Observability | Events |
|---|---|---|---|
| Claude Code | `om hook claude` (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, Stop, SessionEnd) | passive | session, prompt, tool, turn; model from the hook payload |
| Codex (any session) | `om hook codex` (SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop) | passive | session, prompt, tool, turn |
| Codex (OmniMemo-launched) | `om codex run` over `codex app-server` stdio | managed (20 s heartbeat, stale after 45 s) | session, task, prompt, tool, turn, context usage |
| Gemini CLI | `om hook gemini` (SessionStart, BeforeAgent, BeforeTool, AfterTool, AfterAgent, SessionEnd) | passive | session, prompt, tool, turn |
| OpenCode 2.x | plugin (`ctx.tool.hook` execute.before/after, `ctx.session.hook` prompt/context, a detached `ctx.event.subscribe`) -> `om hook opencode`, verified on 2.0.32 | passive | session, prompt, tool (by name only; `execute` is shell), turn end (with the model label), offline on shutdown, context usage |
| Claude Code mod | `plugins/omniverse-bridge-mod` | passive | context usage after each turn, agent cards, fresh-context rollover |

`om runtime ingest` accepts one JSON event or JSONL on stdin for any other adapter.

### Managed Codex runs

`om codex run --prompt <text> [--task <id>] [--sandbox read-only|workspace-write] [--timeout <s>]` starts `codex app-server`, opens a fresh thread (`approvalPolicy: never`, read-only sandbox by default) and runs one turn. The prompt and the replies go only to Codex and the terminal; OmniMemo records categories, statuses and reported usage. Thread items map to tool categories (`commandExecution` shell, `fileChange` file_edit, `mcpToolCall` mcp, `webSearch` web). A server request for approval is declined and shown as `blocked`, because a managed run has no approval channel. `--task` claims a todo task (revision-checked, owner `codex`) and never takes another owner's task. Verified with codex-cli 0.163.0; the protocol schema is generated with `codex app-server generate-json-schema`.

## Context usage and rollover (v2.4)

Context usage is the host-reported occupancy of the active context window, never lifetime tokens or cost:

- Claude Code: `om statusline claude` as the `statusLine` command (`context_window.used_percentage`, `context_window_size`). The installer adds it only with `--with-statusline` and only when no status line exists.
- Managed Codex: `thread/tokenUsage/updated`, as `last.inputTokens / modelContextWindow`.

Samples are kept at most every 10 s unless the level changes or usage moves by 1 point, and only for sessions a lifecycle event already announced. Cards expose `context` (`measurement` reported/unknown, `level` normal/prepare/handoff/critical at 70/80/90 %), separate from task `progress`. A stale or offline session reports `unknown`. Event: `context.usage.updated`.

Manual handoff (suggest mode): `om rollover preview` prints a bounded capsule (session task first, open tasks, unverified milestones, git branch/commit, changed files); `om rollover prepare` saves it as a checkpoint first (`rollover.prepared`, once per capsule) and prints it with the handoff id.

Managed rollover (opt-in): `om codex run --rollover [--rollover-at 80] [--max-rollovers 1]`. After a completed turn at or above the threshold:

1. Prepare and persist the checkpoint.
2. Reserve the only child of the parent atomically (a second request gets nothing).
3. Start an empty thread (`rollover.created`) and deliver the capsule once.
4. The child's first line must be `ACK <digest16>`.
5. With the acknowledgement, the task moves to the child, the parent is retired and the run continues in the child (`rollover.completed`). Without it, the parent keeps its task, the capsule is printed for a manual handoff, and `rollover.failed` is recorded.

Session fields: `parent_session_id`, `child_session_id`, `rollover_state` (`starting_child`, `waiting_ack`, `completed`, `failed_recoverable`).

Claude Code (mod, `rollover` option `auto`, or `/om-rollover`): a fresh session with the same lineage as managed Codex.
1. `om rollover prepare` saves the checkpoint.
2. `om rollover begin` reserves the only child.
3. `/clear` starts a new session id with an empty context.
4. `om rollover link` records parent → child.
5. The capsule is delivered once with an `ACK <digest>` request, and `om rollover report --child` settles it.

At most 3 per hour. A parent left without an acknowledgement keeps its task and stays resumable with `claude --resume`. `om rollover report` without `--child` records a same-session reset (`mode: in_place`) for hosts that cannot start a new session.

OpenCode context: the last step's input plus cache tokens (`session.step.ended`, or `session.step.failed` when it reports tokens) over the model's `limit.context` from `ctx.model.list()`. The model ref comes from the `context` session hook or from `session.step.started`, so a turn that fails before any step completes still labels the session; it still has no context sample, because none was measured.

Not implemented: OpenCode or Gemini rollover, compaction guards, a rollovers-per-hour cap across `om codex run` runs.

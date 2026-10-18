# Omni Agent — Standalone Technical Product Requirements Document

**Version:** 1.4  
**Date:** 18 Oktober 2026  
**Relation:** OmniMemo PRD v1.4, Part V, sections 40–55  
**Status:** Proposed (not yet implemented)

This document is a focused, portable extraction of the Omni Agent feature. The full OmniMemo PRD contains prior memory core, security policies, Mission Control, and acceptance criteria that remain binding.


---

# PART V — OMNI AGENT UNIVERSAL RUNTIME (v1.4)

> **Status:** Proposed; specifications and example commands are not implemented features.
> **Hierarchy:** OmniMemo = shared knowledge; Omni Agent = portable delegation runtime; Mission Control = optional visibility/control plane. Omni Agent must remain useful without dashboard, office view, external database, or resident daemon.

## 40. Product Definition: What Omni Agent Is / Is Not

**Omni Agent** is a local-first, provider-neutral *subagent and task delegation system* running across Codex, Claude Code, Gemini CLI, OpenCode, and future compatible runtimes. It coordinates isolated tasks via a small common contract, bounded context packages, durable checkpoints, and capability-aware adapters. A user may start with Codex in VS Code, hand off to Claude Code in a terminal, send independent QA to Gemini CLI, and inspect state from OpenCode or Mission Control without manually copying a whole transcript. A *workspace* may span distinct IDE windows; *projects* remain isolated by default even when the same disk stores their memory.

**Omni Agent IS:** context broker, task scheduler, delegation tool, cross-host adapter layer, guardrail enforcer, selective context exporter, progress/evidence tracker. **Omni Agent IS NOT:** an autonomous LLM or model provider; a replacement for Codex/Claude/Gemini/OpenCode; a method to read private conversations from unintegrated IDEs; guaranteed ability to control arbitrary running IDE sessions; a framework requiring users to install all providers; a reason to run five workers for every task.

Key principles:
1. **Cross-provider first:** each provider remains an independent runtime using its own authentication, model, quotas, permissions, and supported features.
2. **Task-structured, not transcript-based:** only purpose-specific task capsules and verified results cross provider boundaries.
3. **Performance means useful outcomes per total tokens/time/cost**; never claim magic speed-ups or savings.
4. **One-agent default:** dispatch a subagent only if there is explicit user delegation, clear independence, or measured benefit.
5. **Strict permission intersection:** effective action permission = intersection(user approval, repo policy, project scope, adapter capability, runtime permissions).
6. **OmniMemo is the source of truth for shared task state.** Do not build a second overlapping memory database.

## 41. User Stories & Priority

| ID | User story | P | Acceptance summary |
|---|---|---|---|
| OA-01 | As a Codex user I can delegate code review to Claude, even in another terminal | P0 | A bounded capsule is dispatched; Claude returns evidence-linked review |
| OA-02 | As a Claude user I can delegate investigation to Gemini CLI without sharing entire chat | P0 | Task reference and minimal relevant context, not full transcript |
| OA-03 | As an OpenCode user I can take over task T with decisions preserved | P0 | Restore latest accepted checkpoint, report stale evidence |
| OA-04 | I can see work done in two IDEs as one canonical task | P0 | Same task ID across agents and UI, no invented status |
| OA-05 | I can choose manual/native/cross-provider execution per task | P0 | Clear capabilities and fallback status |
| OA-06 | I can cap delegation by maximum workers and token budget | P0 | Bounded scheduling, stop on exhausted budget |
| OA-07 | Multiple agents edit independent files without trampling one another | P0 | Worktree ownership, conflicts detected before applying changes |
| OA-08 | I can run two separate ideas/projects on one machine | P0 | Project ACL and memory isolation enforced |
| OA-09 | I can relocate data to external SSD without losing coordination | P0 | Shutdown/restart/reopen/restore failure behavior is tested |
| OA-10 | I can inspect why a subagent was chosen and what it returned | P1 | Explainable dispatch reason and evidence available |
| OA-11 | If a provider isn't installed, task still works through manual handoff | P0 | No fake launch, task capsule export/import available |
| OA-12 | I can visualize live tasks in optional Mission Control | P1 | Observed event vs inferred state visibly distinguished |

## 42. Supported Execution Modes

### 42.1 Native-subagent mode

Register existing host-native subagents as **capabilities**, not as a unified implementation. Anthropic Claude Code, Gemini CLI, and OpenCode document their own subagent mechanisms; provider-specific restrictions apply, including whether subagents can further delegate. Codex has CLI, SDK and app-server integration routes depending on installed distribution. Omni Agent must not assume the same programmatic access for all. A native subagent is host-controlled; Omni Agent observes or delegates only if integration hooks actually exist.

### 42.2 Cross-runtime delegated mode

Launch a *new, bounded worker process* only through a version-validated CLI/SDK/API adapter and only when user consent, provider availability and runtime permissions permit. Do not inject commands into a private interactive IDE chat by screen scraping or internal files. Prefer supported structured output (JSON/JSONL), workdir, timeout, and read-only permission flags. On headless workers, **process != active IDE chat**: show that distinction.

### 42.3 Manual/portable handoff mode

When no safe dispatch API is supported, generate a signed/hashed **Task Capsule** with task ID and references. User may paste or load it in any IDE. Worker claims the task via MCP; its result is re-attached to the same task record. No fabricated presence or output streaming.

### 42.4 Observe-only mode

If an existing IDE is connected via MCP but cannot be controlled, expose shared memory/tasks and accept worker-posted checkpoints; display `not_observed` rather than idle/running when no reliable event source is available.

## 43. Cross-IDE Connectivity & Shared Task Bus

**Control plane:** one SQLite-backed persistent task/assignment/event schema reused from Mission Control, plus an on-demand orchestration process. MCP `stdio` supports per-host tools; all instances open the same configured local database *only when filesystem locking and SQLite concurrency semantics allow*. Optional bound-to-loopback HTTP/SSE provides dashboard updates; not required for worker cooperation. Cross-machine coordination is explicitly **not** supported in MVP.

**Flow**:
1. Each IDE/agent registers a `client_instance_id`, `runtime_id`, `workspace_id`, `capabilities`, and `observed_at` via MCP handshake or read-only CLI discovery.
2. User/host submits a task; coordinator assigns persistent `task_id` and `revision`, stores allowed files and success criteria.
3. Worker obtains exclusive lease (atomic CAS on task revision); tasks without claimed leases remain queued.
4. Worker receives short context capsule, reads only permitted files, writes a checkpoint and evidence.
5. Coordinator routes next task or manual handoff; Mission Control displays observed events, not guessed worker activity.
6. On cancellation or disappearance, lease expires; a retry runs only after comparing checkpoint, side effects, and revision.

**IDE independence:** an IDE window never owns the canonical task; it holds only an ephemeral connection to it. Closing VS Code must not delete Codex's shared tasks, and closing Mission Control must not stop independently supported worker execution. Cancellation of a worker should terminate only an explicitly managed child process, not someone else's terminal session.

**No automatic arbitrary cross-project share:** accessing idea/project B from project A needs the user's explicit consent; workspace selectors and ACLs are enforced on both query and task claim.

## 44. Core Runtime Components

| Component | Purpose | Implementation bias |
|---|---|---|
| Agent Registry | Discovered executables, version, capability flags, local IDs | SQLite + executable checks, no global always-on scanner |
| Task Router | Accept/reject/defer delegation by dependency and expected value | Deterministic rules, no LLM scheduler for MVP |
| Context Capsule Builder | Bounded task objective/constraints/evidence references | Reuse OmniMemo memory search and token budget |
| Runtime Adapter | Provider-specific process/session interface | 4 small adapters, capability detection at startup |
| Lease Coordinator | Atomic task claim, optimistic revision, timeout | SQLite transaction; no Redis/RabbitMQ |
| Artifact/Result Collector | Diff hashes, test output refs, summary | Files on disk or SQLite metadata; no full log duplication |
| Budget Guard | Track requests/usage only when surfaced; enforce local hard bounds | Max runs, turns, wall clock, bytes; unknown token reports explicit |
| Policy Gate | File access, command allowlist, GitHub owner lock, push approvals | Reuse canonical v1.2/v1.3 guardrails |
| Event Timeline | Optional UI updates and audit | Existing Mission Control event schema |

**Boundary rule:** isolated modules are warranted only when at least two features use them. P0 can be a single Rust crate's internal modules; do not split into seven services or crates before real demand.

## 45. Omni Agent Task Contract (OATC v1)

Use a versioned JSON envelope and canonical JSON Schema for interoperability. Below is an illustrative compact payload (not a final validated schema):

```json
{
  "schema_version": "oatc/1",
  "task_id": "T-104",
  "project_id": "p-sourbycraft",
  "workspace_id": "w-local",
  "source": { "runtime": "codex", "client_instance_id": "cli-a" },
  "target": { "runtime": "claude", "role": "reviewer", "mode": "delegated" },
  "objective": "Review the plugin startup patch for regressions",
  "scope": { "read_paths": ["src/**"], "write_paths": [] },
  "context": {
    "capsule_id": "C-023",
    "memory_refs": ["M-18", "M-43"],
    "git_base_commit": "<resolved-at-dispatch>",
    "relevance": "startup"
  },
  "limits": { "context_tokens": 450, "max_turns": 6, "wall_seconds": 300 },
  "permissions": { "read": true, "edit": false, "push": false },
  "completion": { "required": ["findings", "file_references", "test_recommendations"] },
  "revision": 4,
  "idempotency_key": "task104-review-v1"
}
```

**Output contract:** `task_id`, `status`, `summary` (default max 200 words), `findings` with severity and file/range/evidence, `changed_files` (if any), `tests_executed` with actual pass/fail/skipped, `remaining_work`, `token_usage` with measurement source or `null`, `cost` or `null`, `artifact_refs`, `memory_refs`, `policy_violations` and `revision`. Results must never contain private model reasoning, raw credentials, hidden chain-of-thought, or unsanitized full session transcripts.

**Runtime state machine:** `created → queued → claimed → running → submitted → reviewing → done` with alternative transitions to `blocked`, `failed`, `canceled`, `timed_out`, `stale`, `needs_approval`. `done` means passing review/tests appropriate to risk, *not* permission to commit, merge or push. Every transition increments revision and appends a deduplicated audit event.

**Artifact integrity:** persist relative path + content hash + source commit + run ID, not raw source files as memory. Reject symlink escape, traversal (`../`), and workspace root mismatch. Check hashes before consuming from another agent.

## 46. Token Efficiency: Context Capsule & Delta Handoff

**Objective:** improve task success / *total* input + output tokens used by *all* workers plus coordinator, including MCP tool schema, retries, validation calls, and summarization. Saving parent context can raise total spend; never present it as universal savings.

**Context Capsule construction:**
1. Resolve project, branch, trust scope, task type, current Git status and evidence freshness.
2. Fetch up to the target budget from OmniMemo: architecture facts, relevant decisions, tests, and latest checkpoint. Include stable memory IDs, not full text for every referenced entity.
3. Include task objective, constraints, allowed paths, acceptance criteria, security rules, and `must_not` list.
4. Provide targeted file paths; worker reads required file ranges on demand, not the entire repository.
5. Cap output length; use structured outcome and source refs rather than raw tool logs.
6. Store delta (changed files, decisions, test outcomes) for next worker; deduplicate repeated handoff material.

**Capsule tiers** (defaults to be benchmarked and user-overridable): `micro` ≤150 token factual capsule (read-only inspection); `standard` ≤450 token handoff; `extended` ≤1,200 token complex isolated engineering. These are *capsule-only* budgets; full worker context, system instructions and scanned files are not included. Show actual total telemetry separately.

**Reuse rule:** do not create a new worker if a suitable existing one can safely continue with lower expected re-briefing cost. Reuse only when runtime actually supports session resume and task/project scope is unchanged. Never resume another user's private conversation.

**Prompt caching:** do not conflate OmniMemo disk cache with a provider's prompt cache; no guarantee of cache hit or savings. Preserve stable static prefix where supported; avoid storing provider tokens in persistent memo.

**Optimization objective for dispatch** (qualitative MVP; numeric weights only after benchmark):
`expected_value = predicted_quality_gain + predicted_wall_time_gain - delegation_tokens - tool_setup - coordination_risk - cross_provider_cost - merge_conflict_risk`.
If score is uncertain or nonpositive → do the job in the current agent. For very simple tasks, never spawn a reviewer merely to demonstrate multi-agent.

## 47. Scheduling, Concurrency & Quality

### 47.1 Task eligibility

Eligible for concurrent execution if tasks have independent acceptance criteria, limited dependencies, and non-overlapping mutable resources. Read-only research tasks may run in parallel. Mutating tasks default to sequential mode unless isolated Git worktrees exist and the user has enabled parallel edits.

### 47.2 Scheduling modes

- `economy`: single worker; no speculative delegation; 1 retry max and only on safely idempotent stages.
- `balanced`: default, one worker normally; up to 2 independent workers when verified useful.
- `performance`: up to 3 concurrent workers and isolated worktrees when user explicitly enables; still bounded by provider limits, token budget and quality gates.

No recursive subagents through Omni Agent in v1.4; coordinator depth=1. Host-native subagent recursion remains controlled by host configuration and is not promised to be intercepted.

### 47.3 Failure and conflict handling

- Workspace lease: one mutating owner per worktree/file allocation. Reviewer may read a frozen diff without claiming write ownership.
- When two tasks target same file, serialize or branch/worktree separate; no silent overlapping edits.
- Use optimistic concurrency (`revision`) for task and memory updates, unique idempotency key for retries.
- Detect provider timeout, rate limits, unavailable CLI, storage disconnection, and partially applied changes. Mark as `blocked`/`needs_review` without fabricated success.
- On cancellation, never kill unowned OS process. Only terminate child owned by a particular execution run; record side effects.
- Require review of changed diff and impacted tests; do not accept self-approval as independent verification.

### 47.4 Operator-visible performance metrics

Measure end-to-end token usage per worker, aggregated token usage, calls, duration, successful task completion, diff conflicts, retry counts, and optional actual API spend. Unknown value is `unavailable`; estimates must be labeled `estimated`, never billed as fact. Run benchmark against the same set of realistic tasks with equal quality gates.

**Provisional success criteria:** aim ≥20% median reduction in total tokens on repeated handoff workloads at noninferior acceptance-test pass rate; aim ≥25% median lower handoff context than naive transcript copying; do not publish claims without measurement. It is acceptable to fail these targets and improve design; no arbitrary hard promise of maximum performance.

## 48. Capability Matrix & Adapter Contracts

| Runtime | Native subagents | Independent headless / programmable execution | Cross-IDE coordination | Important limitations |
|---|---|---|---|---|
| Codex | Provider features depend on Codex product/version | `codex exec`, SDK, or app-server when supported | Shared task/MCP layer; cross-runtime dispatch via adapter | Cannot assume all interactive Codex sessions are controllable |
| Claude Code | Documented custom subagents | `claude -p` output-format JSON/stream-json where supported | MCP and task capsules | Own account/rate limits, native subagents have private contexts |
| Gemini CLI | Documented local and remote subagents | Headless `gemini -p --output-format json` where supported | MCP/task capsule, remote capabilities when configured | Remote/A2A support does **not** automatically bridge every third-party runtime |
| OpenCode | Documented primary/subagents | `opencode run --format json` / server mode version-specific | MCP and task capsules | V1/V2 config differences; detect rather than guess |
| Unknown client | `unknown` | `unknown` | Manual capsule export/import | Do not invent capability or status |

**Adapter interface (conceptual Rust pseudocode):**

```rust
trait RuntimeAdapter {
    fn detect(&self) -> CapabilityReport;
    fn validate_permissions(&self, task: &Task) -> Result<(), PolicyError>;
    fn launch_bounded(&self, capsule: &ContextCapsule) -> Result<RunHandle, Error>;
    fn observe(&self, run: &RunHandle) -> Result<ObservedStatus, Error>;
    fn cancel_owned(&self, run: &RunHandle) -> Result<(), Error>;
    fn normalize_result(&self, raw: &str) -> Result<TaskResult, Error>;
}
```

This is an **illustrative contract**, not a mandate to build 20 generic traits. Implementation should start with 2 adapters that prove cross-provider dispatch end-to-end (Codex + Claude), followed by Gemini and OpenCode.

**Detection order:** executable discovered → version parsed → documented CLI `--help` capability flags → authenticated by runtime's own supported checks (never store credentials) → safe read-only smoke test with user opt-in → capability status `available | requires_setup | unsupported | unknown`. Provider availability and rates vary; missing adapters must not prevent memory-only usage.

**Official references checked October 18, 2026:**
- Codex integration: https://developers.openai.com/blog/codex-as-a-platform
- Claude Code subagents: https://code.claude.com/docs/en/sub-agents
- Claude CLI (print mode): https://docs.anthropic.com/en/docs/claude-code/cli-usage
- Gemini CLI subagents: https://geminicli.com/docs/core/subagents/
- Gemini CLI headless: https://geminicli.com/docs/cli/headless/
- OpenCode agents: https://opencode.ai/v2/docs/agents
- OpenCode CLI: https://dev.opencode.ai/v2/docs/cli/commands/
- MCP spec: https://modelcontextprotocol.io/specification/2026-07-28

## 49. MCP & CLI Surface — New v1.4 Proposals

Avoid adding all capabilities as MCP tool schemas to every agent. Expose four essential task tools in base Omni Agent mode, with advanced tools gated by module features:

| MCP tool | Action | Notes |
|---|---|---|
| `omni_task_create` | Create task and scoped capsule | Does not launch automatically |
| `omni_task_claim` | Atomically claim assigned task | Lease/revision required |
| `omni_task_checkpoint` | Save delta, progress, and evidence | Secrets redacted |
| `omni_task_result` | Submit structured work result | Cannot auto-approve/push |
| `omni_agent_delegate` (opt-in) | Dispatch a verified bounded adapter | Explicit mode/permissions; privileged |
| `omni_agent_status` (optional) | Get observed worker status + budget | Unknown not treated as idle |

```bash
# Proposed CLI, not runnable until implemented
omnimem agent doctor
omnimem agent list --capabilities
omnimem agent task create "Review startup performance patch" --project .
omnimem agent delegate T-104 --runtime claude --mode read-only --approve-launch
omnimem agent task handoff T-104 --runtime gemini --mode manual
omnimem agent task show T-104 --events
omnimem agent budget --task T-104
omnimem agent cancel T-104        # managed owned child process only
```

**Default execution mode**: `manual` unless opt-in dispatch capability is enabled by the user. User may approve one worker launch without blanket approving all future runtime invocations. No automatic push in any mode.

## 50. Proposed Config — Lean Defaults

```toml
[omni_agent]
enabled = true                  # registry + manual task tools, no background process
execution_mode = "manual"     # manual | native | delegated
strategy = "balanced"        # economy | balanced | performance
max_concurrent = 2
max_depth = 1
provider_auto_discovery = false
persist_transcripts = false

[omni_agent.context]
capsule_default_tokens = 450
capsule_max_tokens = 1200
store_raw_logs = false

auto_compact = true

[omni_agent.budget]
max_worker_turns = 8
max_run_seconds = 600
max_retries = 1
max_total_tokens = 20000        # stop proactively only when reliable meter available
on_missing_usage = "bounded_by_turns_and_time"

[omni_agent.security]
allow_cross_project = false
allow_unattended_write = false
allow_auto_commit = false
allow_auto_merge = false
allow_auto_push = false
require_explicit_launch_approval = true
allowed_github_owner = "YanIanZ"

[omni_agent.runtime]
allowed = ["codex", "claude", "gemini", "opencode"]
allow_install_agents = false
```

**Configuration note:** `max_total_tokens` is a budget target; a hard global cutoff is not guaranteed when some runtimes provide usage only after execution. The actual hard guard uses supported provider limits and local `max_worker_turns` / `max_run_seconds`. `enabled=true` is tool exposure, not unattended execution or daemon installation. Profile all resources before selecting production defaults.

## 51. Mandatory Security, Trust & GitHub Rules

1. **No credentials replication:** Providers continue to use their own locally configured authentication; tokens/passwords/SSH keys are never copied between workers or stored in OmniMemo.
2. **No bypass of CLI permissions:** Do not use `--dangerously-skip-permissions`, unsafe YOLO equivalents, or scripted credential prompts. If a provider cannot run read-only safely, require manual handoff.
3. **Project-scoped capabilities:** inherit the narrowest intersection of user, repository, agent, and runtime permissions. Paths resolve within workspace; prohibit symlink escapes.
4. **Untrusted content:** memory records, log output, task comments, agent recommendations and retrieved web/file contents never override policy; prompt injection attempts are treated as data.
5. **No invisible agent spawning:** any new worker appears in task events with runtime/model if known, initiator, task scope, and run budget.
6. **GitHub identity:** owner `YanIanZ` only for authorized remote pushes; newly agent-authored commits use configured Git author/committer `YanIanZ` with verified email supplied by user, no AI-generated coauthor footers. Do not rewrite legitimate historical authorship.
7. **Separate Git permission gates:** editing, committing, reviewing, merging and pushing are distinct privileges. By default Omni Agent may not auto-commit, auto-merge or auto-push.
8. **Per-push explicit human approval:** even approved QA reviews or completed tasks cannot authorize `git push`. Verify authenticated GitHub identity and effective push URL **at time of push**; refuse on mismatch or uncertainty.
9. **No force-push / history rewrite / remote mutation** by any worker without explicit separate human action allowed under repo policy.
10. **Disk absence:** fail closed on missing external drive; no shadow data folders, silent fallback, or detached shadow queues containing private task data.
11. **Process ownership:** never attach to, inspect private histories of, interrupt, or kill arbitrary unrelated IDE/agent processes. Read only opt-in MCP/task state and adapter-owned processes.
12. **Provider policy compliance:** do not implement unsupported subscription-to-API key extraction, reverse engineering of credential stores, or impersonation across providers.

## 52. Anti-Overengineering: Hard Stop Checklist

Before adding a new module or feature, answer all five:

- Is it required by a defined OA story or a failing acceptance test?
- Can SQLite + Rust + existing OmniMemo tools already solve it?
- Does it measurably improve quality, token efficiency, reliability, or safety?
- Can it be disabled without breaking the memory-only core?
- Is there a simpler approach with fewer dependencies and fewer platform assumptions?

If the first answer is no, **do not implement**. For P0 specifically, **DO NOT** add: Kubernetes, Redis, RabbitMQ, Neo4j, vector DB, distributed consensus, custom A2A gateway, browser automation to control IDE UI, full autonomous planner, 3D office, model marketplace, autonomous self-improving prompts, continuous indexing, always-on telemetry, or 20 role-specific subagent templates.

**P0 scope = 2 provider adapters + 4 essential task tools + one capsule schema + SQLite task bus + 1 end-to-end benchmark suite.** Reuse v1.3 dashboard and guardrails; no new task board.

## 53. Benchmark, Instrumentation & Release Gates

Benchmark tasks (same prompts / same repository state / comparable model entitlement / matching tests):
1. **Tiny bug fix**: single agent baseline vs auto-route. Expected policy: no delegation; minimal overhead.
2. **Cross-agent review**: Codex patch -> Claude review via 450-token capsule vs full transcript copy.
3. **Independent investigation**: two read-only diagnoses in parallel; measure wall time, aggregate tokens, utility.
4. **Cross-IDE handoff**: Claude terminal -> OpenCode desktop with persistent checkpoint; no raw transcript.
5. **Multiple separate projects**: intentional project A/B isolation, no mixed results.
6. **Disruption**: SSD unplug, child crash/timeout, provider rate limit, second task claim, stale Git base.

Required telemetry: wall time end-to-end, token input/output per runtime when available, total measured/estimated tokens with provenance, launch overhead, output bytes, context capsule size, number of turns, acceptance pass rate, task conflicts, verified user approvals, and failure reason.

Hard release gates: **security and project isolation, no unauthorized push, no hallucinated provider presence/usage, no database corruption, and no data loss under documented supported filesystem assumptions.** Soft performance goals are measured and published without overstating results.

## 54. Acceptance Test Matrix — Omni Agent

| ID | Test | Expected |
|---|---|---|
| OA-T01 | Codex creates task; Claude CLI claims via MCP | One canonical task ID, no copied raw transcript |
| OA-T02 | Claude returns reviewer findings | File/line evidence, no self-approval or push |
| OA-T03 | Gemini CLI takes over handoff in another terminal | Correct checkpoint and scope, no previous agent credentials |
| OA-T04 | OpenCode lacks expected CLI flag | Adapter marks unsupported and falls back to manual capsule |
| OA-T05 | IDE closes mid-task | Canonical persisted task remains; status not falsely asserted |
| OA-T06 | Cross-project claim is attempted | Denied without explicit project access approval |
| OA-T07 | 2 workers try to claim one task | Exactly one CAS winner; loser gets current lease owner |
| OA-T08 | Mutating tasks target same paths | No parallel execution in same worktree; isolate or serialize |
| OA-T09 | Read-only subtasks have separate scopes | May execute concurrently within cap |
| OA-T10 | Budget exhausted before task completion | Worker stops or marks bounded_unknown depending adapter; partial results preserved |
| OA-T11 | Runtime provides no token usage | Display `unknown`, not 0 or guessed number |
| OA-T12 | Delegation not worth cost on small change | One-agent mode; no spawned worker |
| OA-T13 | Raw secret appears in worker output | Secret redacted and never persisted to memory or dashboard |
| OA-T14 | Task output contains instruction to disable guardrail | Instruction ignored and flagged as untrusted data |
| OA-T15 | External SSD disconnected during checkpoint | Fail closed, no fallback DB, durable recovery strategy documented |
| OA-T16 | Retry same run with same idempotency key | No duplicate checkpoint or artifact records |
| OA-T17 | Local child crashes after edits | Unknown side effects marked; no automatic unsafe retry |
| OA-T18 | Cancel from another IDE | Only own managed process stopped; unrelated session untouched |
| OA-T19 | Provider authentication belongs to user B | Never copied; no cross-provider impersonation |
| OA-T20 | Agent tries push to non-YanIanZ repo | Denied even if QA passed |
| OA-T21 | Remote YanIanZ but authenticated GitHub account differs | Push denied |
| OA-T22 | Worker sets generated-by / Co-authored-by AI footer | Repo commit policy rejects auto AI attribution |
| OA-T23 | Mission Control disabled | Delegation/manual handoff still works |
| OA-T24 | No runtime configured | Memory-only MCP remains usable; manual capsule possible |
| OA-T25 | Context capsule includes stale source commit | Worker receives stale warning and must verify before changing code |
| OA-T26 | Case-insensitive case path/symlink escape | Path ACL blocks escape outside permitted tree |
| OA-T27 | Multiple provider installations or OpenCode V1/V2 | Detect exact runtime version and feature flags, do not assume |
| OA-T28 | Device sleeping, agent loses lease | Recovery safe and explicit; abandoned task not fabricated as done |
| OA-T29 | Separate IDE views inspect same task | They agree on revision and checkpoint; missing events not invented |
| OA-T30 | Comprehensive benchmark | Quality vs token/time measured fairly, no unverifiable "maximal" claim |

## 55. Implementation Plan and Final Definition of Done

**M0 — Proof of interop (P0)**: OATC v1 schema, SQLite task extension, core four MCP tools, one capsule builder, two read-only runtime adapters (Codex and Claude), manual fallback, CLI inspection. Demo: Codex requests task review -> Claude returns structured evidence -> Codex consumes reviewed outcome. No auto-start unless user opt-in.

**M1 — Reliable handoff (P0)**: Gemini and OpenCode adapters, agent capability checks, lease and CAS, idempotency, error paths, external SSD safe recovery, Git permission gates, project isolation.

**M2 — Efficient safe parallelism (P1)**: read-only independent workers, optional isolated worktrees for editing, deterministic dispatch heuristic, reuse/compaction, measured benchmarking and telemetry.

**M3 — Mission Control UI extension (P1)**: visible Omni Agent roster, cross-IDE task timeline, capsule metadata, observed vs unknown status, approvals. Reuse existing UI; do not make mission UI a dependency for the core.

**M4 — Optional advanced coordination (P2, only with evidence)**: durable provider resumptions, streaming event bridges, A2A adapter where genuinely demanded by a real client. Do not include cloud or distributed scheduling in MVP.

**Definition of done for Omni Agent v1.4**: in a supported local environment, at least Codex and Claude can complete an authenticated and scoped cross-provider task handoff end-to-end; Gemini and OpenCode adapters have documented verified capabilities or explicit fallback; task claims are concurrency-safe; capsule and result have provenance; Git and privacy rules block unauthorized actions; benchmark reports total token/time impacts honestly; no additional heavy daemon/DB is required.

**Vision statement:** **“Satu memori, banyak agent, banyak IDE—tanpa membayar konteks yang sama dua kali jika bisa dihindari.”**

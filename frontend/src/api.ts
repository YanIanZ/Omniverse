// Scoped REST client. Auth is the HttpOnly session cookie set by /auth; the
// browser never sees database credentials or the raw server token.

export type Health = {
  status: string
  storage: string
  redis: 'disabled' | 'connected' | 'unavailable'
  project_id: string
  /** The project folder's name, for people; project_id is the identity. */
  project_name?: string
  records: string
  revision: string
}

export type AgentStatus = 'waiting' | 'working' | 'blocked' | 'offline' | 'stale'

export type Agent = {
  agent: string
  session_id: string
  status: AgentStatus
  source: string
  first_seen: string
  last_seen: string
  /** Reported by the host adapter; absent means the model is unknown. */
  model?: string
  /** A few-word task label, stored only where session titles are opted in. */
  title?: string
  tool_category?: string
  /** Active context occupancy reported by the host; absence means unknown. */
  context_used_percent?: number
  context_window_tokens?: number
  /** Tokens in use when the window is unknown (a subagent on another model): no percent. */
  context_used_tokens?: number
  context_observed_at?: string
  /** Set on a subagent: the session that spawned it, and its type. */
  spawned_by?: string
  agent_type?: string
}

/** `claude` for a session, `claude › Explore · haiku` for a subagent. */
export const agentName = (a: Agent) =>
  a.spawned_by ? `${a.agent} › ${a.agent_type ?? 'subagent'}${family(a.model)}` : a.agent
/** ` · opus` from `claude-opus-5-5`: tells apart subagents of one type running different models. */
const family = (model?: string) => {
  const name = model?.match(/^claude-([a-z]+)/)?.[1]
  return name ? ` · ${name}` : ''
}

// Records written before the runtime bridge still carry the old status names.
const LEGACY: Record<string, AgentStatus> = {
  ready: 'waiting',
  active: 'working',
  disconnected: 'offline',
  unknown: 'stale',
}
const STATUSES: readonly string[] = ['waiting', 'working', 'blocked', 'offline', 'stale']

export function normalizeStatus(status: string): AgentStatus {
  return LEGACY[status] ?? (STATUSES.includes(status) ? (status as AgentStatus) : 'stale')
}

export const PRIORITIES = ['P0', 'P1', 'P2', 'P3'] as const
export type Priority = (typeof PRIORITIES)[number]

export type Approval = {
  id: string
  action: string
  reason: string
  requested_by: string
  status: 'pending' | 'approved' | 'denied'
  revision: number
  created_at: string
  decided_at?: string
}

export const TASK_STATUSES = ['todo', 'doing', 'review', 'done', 'blocked'] as const
export type TaskStatus = (typeof TASK_STATUSES)[number]

export type Task = {
  id: string
  title: string
  status: TaskStatus
  revision: number
  owner?: string
  priority?: Priority
  created_at: string
  updated_at: string
}

export type Memory = {
  id: string
  title: string
  summary: string
  state: string
  source_refs?: string[]
}

export type LiveEvent = {
  v: number
  event_id: string
  project_id: string
  type: string
  entity_id: string
  revision: number
  timestamp: string
  data: Record<string, string>
}

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message)
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch('/api/v1' + path, {
    credentials: 'same-origin',
    ...init,
    headers: { 'Content-Type': 'application/json', ...init?.headers },
  })
  const body = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new ApiError(response.status, (body as { error?: string }).error ?? response.statusText)
  }
  return body as T
}

export const api = {
  health: () => request<Health>('/health'),
  agents: () =>
    request<Agent[]>('/agents').then((list) => list.map((a) => ({ ...a, status: normalizeStatus(a.status) }))),
  tasks: () => request<Task[]>('/tasks'),
  createTask: (title: string, priority: Priority) =>
    request<Task>('/tasks', {
      method: 'POST',
      body: JSON.stringify({ title, priority, idempotency_key: 'ui-' + crypto.randomUUID() }),
    }),
  updateTask: (task: Task, change: { status?: TaskStatus; owner?: string; priority?: Priority }) =>
    request<Task>('/tasks/' + encodeURIComponent(task.id), {
      method: 'PATCH',
      headers: { 'If-Match': String(task.revision) },
      body: JSON.stringify(change),
    }),
  approvals: () => request<Approval[]>('/approvals'),
  decide: (approval: Approval, decision: 'approved' | 'denied') =>
    request<Approval>('/approvals/' + encodeURIComponent(approval.id) + '/decision', {
      method: 'POST',
      body: JSON.stringify({ decision }),
    }),
  events: (after: number) => request<LiveEvent[]>('/events?after=' + after),
  search: (q: string) => request<Memory[]>('/memory/search?q=' + encodeURIComponent(q)),
}

// Scoped REST client. Auth is the HttpOnly session cookie set by /auth; the
// browser never sees database credentials or the raw server token.

export type Health = {
  status: string
  storage: string
  redis: 'disabled' | 'connected' | 'unavailable'
  project_id: string
  records: string
  revision: string
}

export type Agent = {
  agent: string
  session_id: string
  status: 'ready' | 'active' | 'disconnected' | 'unknown'
  source: string
  first_seen: string
  last_seen: string
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
  agents: () => request<Agent[]>('/agents'),
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

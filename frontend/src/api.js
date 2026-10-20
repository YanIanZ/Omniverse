// Scoped REST client. Auth is the HttpOnly session cookie set by /auth; the
// browser never sees database credentials or the raw server token.
/** `claude` for a session, `claude › Explore` for a subagent. */
export const agentName = (a) => (a.spawned_by ? `${a.agent} › ${a.agent_type ?? 'subagent'}` : a.agent);
// Records written before the runtime bridge still carry the old status names.
const LEGACY = {
    ready: 'waiting',
    active: 'working',
    disconnected: 'offline',
    unknown: 'stale',
};
const STATUSES = ['waiting', 'working', 'blocked', 'offline', 'stale'];
export function normalizeStatus(status) {
    return LEGACY[status] ?? (STATUSES.includes(status) ? status : 'stale');
}
export const PRIORITIES = ['P0', 'P1', 'P2', 'P3'];
export const TASK_STATUSES = ['todo', 'doing', 'review', 'done', 'blocked'];
export class ApiError extends Error {
    status;
    constructor(status, message) {
        super(message);
        this.status = status;
    }
}
async function request(path, init) {
    const response = await fetch('/api/v1' + path, {
        credentials: 'same-origin',
        ...init,
        headers: { 'Content-Type': 'application/json', ...init?.headers },
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
        throw new ApiError(response.status, body.error ?? response.statusText);
    }
    return body;
}
export const api = {
    health: () => request('/health'),
    agents: () => request('/agents').then((list) => list.map((a) => ({ ...a, status: normalizeStatus(a.status) }))),
    tasks: () => request('/tasks'),
    createTask: (title, priority) => request('/tasks', {
        method: 'POST',
        body: JSON.stringify({ title, priority, idempotency_key: 'ui-' + crypto.randomUUID() }),
    }),
    updateTask: (task, change) => request('/tasks/' + encodeURIComponent(task.id), {
        method: 'PATCH',
        headers: { 'If-Match': String(task.revision) },
        body: JSON.stringify(change),
    }),
    approvals: () => request('/approvals'),
    decide: (approval, decision) => request('/approvals/' + encodeURIComponent(approval.id) + '/decision', {
        method: 'POST',
        body: JSON.stringify({ decision }),
    }),
    events: (after) => request('/events?after=' + after),
    search: (q) => request('/memory/search?q=' + encodeURIComponent(q)),
};

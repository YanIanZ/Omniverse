import { type FormEvent, useCallback, useEffect, useState } from 'react'
import {
  type Agent,
  ApiError,
  type Health,
  type LiveEvent,
  type Memory,
  type Task,
  TASK_STATUSES,
  type TaskStatus,
  api,
} from './api'
import { type Connection, useLive } from './useLive'

const ago = (iso: string) => {
  const seconds = Math.max(0, Math.round((Date.now() - Date.parse(iso)) / 1000))
  if (seconds < 60) return `${seconds}s ago`
  if (seconds < 3600) return `${Math.round(seconds / 60)}m ago`
  return `${Math.round(seconds / 3600)}h ago`
}

const tone: Record<string, string> = {
  active: 'green',
  ready: 'green',
  live: 'green',
  connected: 'green',
  unknown: 'yellow',
  reconnecting: 'yellow',
  connecting: 'yellow',
  unavailable: 'red',
  offline: 'red',
  blocked: 'red',
  disconnected: 'gray',
  disabled: 'gray',
}

function Badge({ value }: { value: string }) {
  return <span className={`badge ${tone[value] ?? 'blue'}`}>{value}</span>
}

export function App() {
  const [health, setHealth] = useState<Health>()
  const [agents, setAgents] = useState<Agent[]>([])
  const [tasks, setTasks] = useState<Task[]>([])
  const [events, setEvents] = useState<LiveEvent[]>([])
  const [error, setError] = useState<string>()
  const [unauthorized, setUnauthorized] = useState(false)

  const report = useCallback((e: unknown) => {
    if (e instanceof ApiError && e.status === 401) setUnauthorized(true)
    else setError(e instanceof Error ? e.message : String(e))
  }, [])

  const snapshot = useCallback(async () => {
    try {
      const [h, a, t] = await Promise.all([api.health(), api.agents(), api.tasks()])
      setHealth(h)
      setAgents(a)
      setTasks(t)
      setUnauthorized(false)
    } catch (e) {
      report(e)
    }
  }, [report])

  useEffect(() => {
    void snapshot()
    // Presence ages into `unknown` without new events; refresh slowly, never per frame.
    const timer = window.setInterval(() => void api.agents().then(setAgents, report), 30_000)
    return () => window.clearInterval(timer)
  }, [snapshot, report])

  const onEvent = useCallback(
    (event: LiveEvent) => {
      setEvents((list) => [event, ...list].slice(0, 30))
      setHealth((h) => (h ? { ...h, revision: String(event.revision) } : h))
      if (event.type === 'task.updated') void api.tasks().then(setTasks, report)
      if (event.type === 'agent.status.changed') void api.agents().then(setAgents, report)
    },
    [report],
  )
  const connection = useLive(health?.project_id, onEvent, snapshot)

  if (unauthorized) {
    return (
      <main className="shell narrow">
        <h1>OmniMemo</h1>
        <p className="muted">
          This browser is not signed in. Run <kbd>om office</kbd> in your project to open an
          authenticated session.
        </p>
      </main>
    )
  }

  return (
    <main className="shell">
      <header className="top">
        <div>
          <h1>Mission Control</h1>
          <p className="muted mono">
            project {health ? health.project_id.slice(0, 12) : '...'} · revision{' '}
            {health?.revision ?? '...'}
          </p>
        </div>
        <ConnectionStatus connection={connection} />
      </header>
      {error && (
        <p className="notice" role="alert">
          {error}{' '}
          <button className="link" onClick={() => setError(undefined)}>
            Dismiss
          </button>
        </p>
      )}
      <div className="grid">
        <StatusCard health={health} connection={connection} />
        <AgentsCard agents={agents} />
        <EventsCard events={events} />
        <TasksCard tasks={tasks} onError={report} onChanged={snapshot} />
        <MemoryCard onError={report} />
      </div>
    </main>
  )
}

function ConnectionStatus({ connection }: { connection: Connection }) {
  return (
    <p className="status" aria-live="polite">
      <span className={`dot ${tone[connection]}`} aria-hidden="true" />
      {connection === 'live' ? 'Live' : connection}
    </p>
  )
}

function StatusCard({ health, connection }: { health?: Health; connection: Connection }) {
  return (
    <section className="card">
      <h2>Runtime</h2>
      <dl className="facts">
        <dt>Server</dt>
        <dd>{health ? <Badge value={health.status === 'ok' ? 'connected' : 'unavailable'} /> : '...'}</dd>
        <dt>MongoDB</dt>
        <dd>{health ? <Badge value="connected" /> : '...'}</dd>
        <dt>Redis</dt>
        <dd>{health ? <Badge value={health.redis} /> : '...'}</dd>
        <dt>Live events</dt>
        <dd>
          <Badge value={connection} />
        </dd>
        <dt>Memories</dt>
        <dd className="mono">{health?.records ?? '...'}</dd>
      </dl>
    </section>
  )
}

function AgentsCard({ agents }: { agents: Agent[] }) {
  return (
    <section className="card">
      <h2>Agents</h2>
      {agents.length === 0 ? (
        <p className="muted">
          No observed sessions. Agents appear after a supported hook or <kbd>om wake</kbd> reports
          one.
        </p>
      ) : (
        <ul className="rows">
          {agents.map((a) => (
            <li key={a.agent + a.session_id}>
              <div>
                <strong>{a.agent}</strong>
                <span className="muted mono"> {a.session_id.slice(0, 8)}</span>
                <p className="muted small">
                  {a.source === 'claude_hook' ? 'verified hook' : a.source} · seen {ago(a.last_seen)}
                </p>
              </div>
              <Badge value={a.status} />
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}

function TasksCard({
  tasks,
  onError,
  onChanged,
}: {
  tasks: Task[]
  onError: (e: unknown) => void
  onChanged: () => Promise<void>
}) {
  const [title, setTitle] = useState('')
  const [busy, setBusy] = useState(false)

  const add = async (e: FormEvent) => {
    e.preventDefault()
    if (!title.trim()) return
    setBusy(true)
    try {
      await api.createTask(title.trim())
      setTitle('')
    } catch (err) {
      onError(err)
    } finally {
      setBusy(false)
    }
  }
  const move = async (task: Task, status: TaskStatus) => {
    try {
      await api.moveTask(task, status)
    } catch (err) {
      // A stale revision means another agent moved it first: reload instead of overwriting.
      if (err instanceof ApiError && err.status === 409) await onChanged()
      onError(err)
    }
  }

  return (
    <section className="card wide">
      <h2>Tasks</h2>
      <form className="inline" onSubmit={add}>
        <label className="sr-only" htmlFor="task-title">
          New task
        </label>
        <input
          id="task-title"
          value={title}
          maxLength={240}
          placeholder="Describe a task for an agent"
          onChange={(e) => setTitle(e.target.value)}
        />
        <button className="primary" disabled={busy || !title.trim()}>
          Add task
        </button>
      </form>
      <div className="board">
        {TASK_STATUSES.map((status) => (
          <div className="column" key={status}>
            <h3>
              {status} <span className="muted">{tasks.filter((t) => t.status === status).length}</span>
            </h3>
            {tasks
              .filter((t) => t.status === status)
              .map((task) => (
                <article className="task" key={task.id}>
                  <p>{task.title}</p>
                  <p className="muted small mono">
                    rev {task.revision}
                    {task.owner ? ` · ${task.owner}` : ''}
                  </p>
                  <label className="sr-only" htmlFor={`move-${task.id}`}>
                    Move {task.title}
                  </label>
                  <select
                    id={`move-${task.id}`}
                    value={task.status}
                    onChange={(e) => void move(task, e.target.value as TaskStatus)}
                  >
                    {TASK_STATUSES.map((s) => (
                      <option key={s} value={s}>
                        {s}
                      </option>
                    ))}
                  </select>
                </article>
              ))}
          </div>
        ))}
      </div>
    </section>
  )
}

function MemoryCard({ onError }: { onError: (e: unknown) => void }) {
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<Memory[]>()

  const search = async (e: FormEvent) => {
    e.preventDefault()
    try {
      setResults(await api.search(query))
    } catch (err) {
      onError(err)
    }
  }
  return (
    <section className="card wide">
      <h2>Memory</h2>
      <form className="inline" onSubmit={search}>
        <label className="sr-only" htmlFor="memory-query">
          Search memory
        </label>
        <input
          id="memory-query"
          value={query}
          maxLength={200}
          placeholder="Search this project"
          onChange={(e) => setQuery(e.target.value)}
        />
        <button>Search</button>
      </form>
      {results && results.length === 0 && <p className="muted">No matching memories.</p>}
      <ul className="rows">
        {results?.map((m) => (
          <li key={m.id}>
            <div>
              <strong>{m.title}</strong>
              <p className="muted small">{m.summary}</p>
              {m.source_refs && <p className="mono small">{m.source_refs.join(', ')}</p>}
            </div>
            <Badge value={m.state === 'active' ? 'connected' : m.state} />
          </li>
        ))}
      </ul>
    </section>
  )
}

function EventsCard({ events }: { events: LiveEvent[] }) {
  return (
    <section className="card">
      <h2>Live events</h2>
      {events.length === 0 ? (
        <p className="muted">Waiting for committed events.</p>
      ) : (
        <ol className="events">
          {events.map((e) => (
            <li key={e.event_id}>
              <span className="mono small">#{e.revision}</span> {e.type}{' '}
              <span className="muted small">
                {e.data.status ?? ''} · {new Date(e.timestamp).toLocaleTimeString()}
              </span>
            </li>
          ))}
        </ol>
      )}
    </section>
  )
}

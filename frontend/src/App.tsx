import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  type Agent,
  ApiError,
  type Approval,
  type Health,
  type LiveEvent,
  type Task,
  api,
} from './api'
import { place } from './office'
import { Logo } from './Figure'
import { useLive } from './useLive'
import { AgentsView, ApprovalsView, EventsView, MemoryView, OfficeView, TasksView } from './views'

const VIEWS = ['office', 'tasks', 'agents', 'approvals', 'memory', 'events'] as const
export type View = (typeof VIEWS)[number]

const viewFromHash = (): View => {
  const name = location.hash.replace('#', '') as View
  return VIEWS.includes(name) ? name : 'office'
}

export type Store = {
  health?: Health
  agents: Agent[]
  tasks: Task[]
  approvals: Approval[]
  events: LiveEvent[]
  now: number
  /** False until the first snapshot arrives, so views never present "nothing" before they know. */
  loaded: boolean
  /** True while the live event stream is connected. */
  live: boolean
  report: (e: unknown) => void
  refresh: () => Promise<void>
}

export function App() {
  const [view, setView] = useState<View>(viewFromHash)
  const [health, setHealth] = useState<Health>()
  const [agents, setAgents] = useState<Agent[]>([])
  const [tasks, setTasks] = useState<Task[]>([])
  const [approvals, setApprovals] = useState<Approval[]>([])
  const [events, setEvents] = useState<LiveEvent[]>([])
  const [error, setError] = useState<string>()
  const [unauthorized, setUnauthorized] = useState(false)
  const [now, setNow] = useState(Date.now())
  const [loaded, setLoaded] = useState(false)

  useEffect(() => {
    const onHash = () => setView(viewFromHash())
    window.addEventListener('hashchange', onHash)
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  const report = useCallback((e: unknown) => {
    if (e instanceof ApiError && e.status === 401) setUnauthorized(true)
    else setError(e instanceof Error ? e.message : String(e))
  }, [])

  // Events can trigger overlapping reads of one list; only the newest request may apply,
  // so a slower, older response never overwrites a newer snapshot.
  const latest = useRef({ agents: 0, tasks: 0, approvals: 0 })
  const load = useCallback(
    <T,>(key: keyof typeof latest.current, read: () => Promise<T>, apply: (value: T) => void) => {
      const n = ++latest.current[key]
      void read().then((value) => n === latest.current[key] && apply(value), report)
    },
    [report],
  )

  const refresh = useCallback(async () => {
    try {
      const n = { agents: ++latest.current.agents, tasks: ++latest.current.tasks, approvals: ++latest.current.approvals }
      const [h, a, t, p] = await Promise.all([api.health(), api.agents(), api.tasks(), api.approvals()])
      setHealth(h)
      if (n.agents === latest.current.agents) setAgents(a)
      if (n.tasks === latest.current.tasks) setTasks(t)
      if (n.approvals === latest.current.approvals) setApprovals(p)
      setUnauthorized(false)
      const revision = Number(h.revision)
      const recent = await api.events(Math.max(0, revision - 60))
      setEvents(recent.reverse())
      setLoaded(true)
      setError(undefined)
    } catch (e) {
      report(e)
    }
  }, [report])

  useEffect(() => {
    void refresh()
    // Presence ages without new events: re-read sessions slowly, and tick relative times.
    const slow = window.setInterval(() => load('agents', api.agents, setAgents), 30_000)
    const tick = window.setInterval(() => setNow(Date.now()), 15_000)
    return () => {
      window.clearInterval(slow)
      window.clearInterval(tick)
    }
  }, [refresh, load])

  const onEvent = useCallback(
    (event: LiveEvent) => {
      setNow(Date.now())
      setEvents((list) => (list.some((e) => e.event_id === event.event_id) ? list : [event, ...list].slice(0, 200)))
      setHealth((h) => (h ? { ...h, revision: String(event.revision) } : h))
      if (event.type === 'task.updated') load('tasks', api.tasks, setTasks)
      if (event.type === 'agent.status.changed' || event.type === 'runtime.activity' || event.type === 'context.usage.updated')
        load('agents', api.agents, setAgents)
      if (event.type.startsWith('approval.')) load('approvals', api.approvals, setApprovals)
    },
    [load],
  )
  const connection = useLive(health?.project_id, onEvent, refresh)
  const store: Store = { health, agents, tasks, approvals, events, now, loaded, live: connection === 'live', report, refresh }

  const office = useMemo(() => place(agents, tasks, approvals, events, now), [agents, tasks, approvals, events, now])
  const pending = approvals.filter((a) => a.status === 'pending').length
  const present = agents.filter((a) => a.status !== 'offline')
  const stale = present.filter((a) => a.status === 'stale').length

  if (unauthorized) {
    return (
      <main className="signin">
        <Logo size={48} />
        <h1>OmniMemo is locked</h1>
        <p>
          This browser isn't signed in, or its sign-in link was already used. Run <kbd>om office</kbd> in your
          project's terminal: it opens Mission Control with a fresh one-time sign-in link.
        </p>
      </main>
    )
  }

  const nav: { id: View; label: string; title: string; count?: number; unit?: string; attention?: boolean }[] = [
    { id: 'office', label: 'Office', title: 'Agent Office' },
    { id: 'tasks', label: 'Tasks', title: 'Tasks', count: tasks.filter((t) => t.status !== 'done').length, unit: 'open' },
    { id: 'agents', label: 'Agents', title: 'Agents', count: present.length, unit: 'present' },
    { id: 'approvals', label: 'Approvals', title: 'Approvals', count: pending, unit: 'waiting for you', attention: pending > 0 },
    { id: 'memory', label: 'Memory', title: 'Memory' },
    { id: 'events', label: 'Events', title: 'Events' },
  ]
  const liveLabel = { live: 'Live', connecting: 'Connecting', reconnecting: 'Reconnecting', offline: 'Offline' }[connection]

  return (
    <div className="shell">
      <a className="skip" href="#work">
        Skip to content
      </a>
      <nav className="rail" aria-label="Mission Control">
        <div className="brand">
          <Logo size={30} />
          <div>
            <div className="brand-name">OmniMemo</div>
            <div className="brand-sub">Mission Control</div>
          </div>
        </div>
        <ul>
          {nav.map((item) => (
            <li key={item.id}>
              <a href={'#' + item.id} aria-current={view === item.id ? 'page' : undefined}>
                {item.label}
                {item.count ? (
                  <span className={'count' + (item.attention ? ' attention' : '')}>
                    {item.count}
                    <span className="sr-only"> {item.unit}</span>
                  </span>
                ) : null}
              </a>
            </li>
          ))}
        </ul>
        <dl className="rail-meta">
          <dt>Project</dt>
          <dd className="mono" title={health?.project_id}>
            {health ? health.project_name ?? health.project_id.slice(0, 12) : '…'}
          </dd>
          <dt>Events recorded</dt>
          <dd className="mono">{health?.revision ?? '…'}</dd>
          <dt>Live</dt>
          <dd className={'live live-' + connection}>{connection === 'live' ? 'Connected' : liveLabel}</dd>
        </dl>
      </nav>

      <main id="work" className="work">
        <header className="topbar">
          <h1>{nav.find((n) => n.id === view)?.title}</h1>
          <p className="summary">
            <span className={'live-chip live-' + connection}>
              <span className="live-led" aria-hidden="true" />
              {liveLabel}
            </span>
            {loaded ? (
              <>
                {present.length} {present.length === 1 ? 'session' : 'sessions'} present
                {stale ? ` · ${stale} with no recent signal` : ''}
              </>
            ) : (
              'Reading the project…'
            )}
          </p>
          <div className="topbar-right">
            {(['todo', 'doing', 'review'] as const).map((s) => (
              <a key={s} className={'stat stat-' + s} href="#tasks">
                {s} <b>{loaded ? tasks.filter((t) => t.status === s).length : '…'}</b>
              </a>
            ))}
            {pending > 0 && (
              <a className="needs-you" href="#approvals">
                Needs you · {pending}
              </a>
            )}
          </div>
        </header>
        {error && (
          <div className="notice" role="alert">
            <p>
              <b>Something went wrong.</b> {error}
            </p>
            <div className="notice-actions">
              <button type="button" className="link" onClick={() => void refresh()}>
                Reload data
              </button>
              <button type="button" className="link" onClick={() => setError(undefined)}>
                Dismiss
              </button>
            </div>
          </div>
        )}
        {view === 'office' && <OfficeView store={store} office={office} />}
        {view === 'tasks' && <TasksView store={store} />}
        {view === 'agents' && <AgentsView store={store} office={office} />}
        {view === 'approvals' && <ApprovalsView store={store} />}
        {view === 'memory' && <MemoryView store={store} />}
        {view === 'events' && <EventsView store={store} />}
      </main>
    </div>
  )
}

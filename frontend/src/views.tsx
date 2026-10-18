import { type FormEvent, type ReactNode, useEffect, useState } from 'react'
import type { Store } from './App'
import {
  type Agent,
  ApiError,
  type Approval,
  type Memory,
  PRIORITIES,
  type Priority,
  TASK_STATUSES,
  type Task,
  type TaskStatus,
  api,
} from './api'
import { ago, type Placement, ROOMS, type RoomId } from './office'
import { OfficeMap } from './OfficeMap'
import { AgentSprite } from './Sprite'

type Office = { placed: Placement[]; overflow: Partial<Record<RoomId, number>> }
type Event = Store['events'][number]

const SOURCE: Record<string, { label: string; how: string }> = {
  claude_hook: { label: 'Claude Code hook', how: 'SessionStart, UserPromptSubmit and SessionEnd hooks.' },
  codex_hook: { label: 'Codex hook', how: 'Codex hooks.json session events.' },
  gemini_hook: { label: 'Gemini CLI hook', how: 'Gemini CLI session hooks.' },
  opencode_hook: { label: 'OpenCode plugin', how: 'The OmniMemo OpenCode plugin.' },
  mcp: { label: 'MCP connection', how: 'The first tool call from an MCP client.' },
  cli: { label: 'om CLI', how: 'An explicit om wake command; not a host hook.' },
}
const sourceLabel = (s: string) => SOURCE[s]?.label ?? s
const roomLabel = (id: RoomId) => ROOMS.find((r) => r.id === id)?.label ?? id

const STATUS_HELP: Record<Agent['status'], string> = {
  active: 'The host reported a prompt or tool call in this session.',
  ready: 'The session reported in and is waiting for work.',
  unknown: 'No signal for 10 minutes. It may still be running; OmniMemo cannot tell.',
  disconnected: 'The host reported that the session ended.',
}
const MEMORY_HELP: Record<string, string> = {
  active: 'saved with source evidence',
  unverified: 'saved without evidence',
  stale: 'a source file changed since it was saved',
}
const PRIORITY_HELP: Record<Priority, string> = { P0: 'urgent', P1: 'high', P2: 'normal', P3: 'low' }

/* Shared states */

function Loading({ label, rows = 3 }: { label: string; rows?: number }) {
  return (
    <div className="panel skeleton" role="status">
      <span className="sr-only">{label}</span>
      {Array.from({ length: rows }, (_, i) => (
        <span key={i} className="skeleton-bar" aria-hidden="true" />
      ))}
    </div>
  )
}

function Empty({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="panel empty">
      <h2>{title}</h2>
      {children && <p className="muted">{children}</p>}
    </div>
  )
}

/* Events */

const EVENT_LABEL: Record<string, string> = {
  'agent.status.changed': 'Session status',
  'task.updated': 'Task updated',
  'approval.requested': 'Approval requested',
  'approval.decided': 'Approval decided',
  'memory.checkpoint.created': 'Handoff saved',
  'session.created': 'Session started',
  'session.idle': 'Session idle',
  'session.deleted': 'Session ended',
}
const EVENT_KINDS = [
  { id: 'all', label: 'All' },
  { id: 'session', label: 'Sessions' },
  { id: 'task', label: 'Tasks' },
  { id: 'approval', label: 'Approvals' },
  { id: 'memory', label: 'Handoffs' },
] as const
type EventKind = (typeof EVENT_KINDS)[number]['id']
const kindOf = (type: string): EventKind => {
  const head = type.split('.')[0]
  if (head === 'agent' || head === 'session') return 'session'
  if (head === 'task' || head === 'approval' || head === 'memory') return head
  return 'all'
}

/** What the event is about, resolved only from records the store already holds. */
function subjectOf(e: Event, store: Store) {
  if (e.type === 'task.updated') return store.tasks.find((t) => t.id === e.entity_id)?.title
  if (e.type.startsWith('approval.')) return store.approvals.find((a) => a.id === e.entity_id)?.action
  if (e.type === 'agent.status.changed') return e.entity_id.split(':').slice(1).join(':') || undefined
  return undefined
}

function EventLine({ e, store }: { e: Event; store: Store }) {
  const who = e.data.agent || e.entity_id.split(':')[0]
  const subject = subjectOf(e, store)
  return (
    <li className="event">
      <span className="mono rev">#{e.revision}</span>
      <span className="event-main" title={e.type}>
        <span className="event-label">{EVENT_LABEL[e.type] ?? e.type}</span>
        {subject ? (
          <span className="event-subject">{subject}</span>
        ) : !EVENT_LABEL[e.type] ? (
          <span className="event-subject mono">{e.entity_id}</span>
        ) : null}
      </span>
      <span className="event-who">
        <AgentSprite agent={who} scale={1} />
        {who}
      </span>
      {e.data.status ? (
        <span className={'pill pill-' + e.data.status}>{e.data.status}</span>
      ) : (
        <span className="pill-none" />
      )}
      <time className="event-time" dateTime={e.timestamp} title={new Date(e.timestamp).toLocaleString()}>
        {ago(e.timestamp, store.now)}
      </time>
    </li>
  )
}

/* Office */

export function OfficeView({ store, office }: { store: Store; office: Office }) {
  const [selected, setSelected] = useState<string>()
  const current = office.placed.find((p) => p.key === selected) ?? office.placed[0]
  return (
    <div className="office">
      <section className="office-map" aria-label="Office map">
        <OfficeMap
          placed={office.placed}
          overflow={office.overflow}
          health={store.health}
          selected={current?.key}
          onSelect={setSelected}
        />
        {store.loaded && office.placed.length === 0 && (
          <div className="map-empty">
            <p>
              {store.agents.length === 0
                ? 'No agent has reported in yet.'
                : 'Nobody is in the office: every observed session has disconnected.'}
            </p>
            <p className="muted">
              Agents appear when a supported hook fires, an MCP client connects, or you run{' '}
              <kbd>om --agent claude wake --session demo</kbd>.
            </p>
          </div>
        )}
      </section>
      <aside className="office-side">
        <section className="panel detail" aria-live="polite">
          {current ? (
            <>
              <div className="detail-head">
                <span className="portrait">
                  <AgentSprite agent={current.agent.agent} scale={4} />
                </span>
                <div className="detail-id">
                  <h2>{current.agent.agent}</h2>
                  <span className={'pill pill-tone-' + current.tone}>{current.state}</span>
                  <p className="mono muted">{current.agent.session_id}</p>
                </div>
              </div>
              <dl className="facts">
                <dt>Signal</dt>
                <dd>{sourceLabel(current.agent.source)}</dd>
                <dt>Last seen</dt>
                <dd>{ago(current.agent.last_seen, store.now)}</dd>
                <dt>Room</dt>
                <dd>{roomLabel(current.room)}</dd>
                <dt>Task</dt>
                <dd>
                  {current.task ? (
                    <>
                      {current.task.title} <span className="mono muted">rev {current.task.revision}</span>
                    </>
                  ) : (
                    <span className="muted">none claimed</span>
                  )}
                </dd>
                {current.approval && (
                  <>
                    <dt>Waiting on</dt>
                    <dd>
                      <a href="#approvals">{current.approval.action}</a>
                    </dd>
                  </>
                )}
              </dl>
            </>
          ) : (
            <p className="muted">
              {store.loaded ? 'Select an agent on the map to see where its status comes from.' : 'Loading sessions…'}
            </p>
          )}
        </section>
        <section className="panel">
          <h2>Latest events</h2>
          {store.events.length === 0 ? (
            <p className="muted">{store.loaded ? 'No committed events yet.' : 'Loading events…'}</p>
          ) : (
            <>
              {/* Six rows, not eight: each rail row now also carries the agent and
                  the resulting state, and the map stays the hero of this view. */}
              <ol className="events compact">
                {store.events.slice(0, 6).map((e) => (
                  <EventLine key={e.event_id} e={e} store={store} />
                ))}
              </ol>
              <a className="more" href="#events">
                All events
              </a>
            </>
          )}
        </section>
      </aside>
    </div>
  )
}

/* Tasks */

const COLUMN_EMPTY: Record<TaskStatus, ReactNode> = {
  todo: (
    <>
      No open tasks. Add one above or run <kbd>om tasks add "title"</kbd>.
    </>
  ),
  doing: (
    <>
      Nothing in progress. An agent claims work with <kbd>om tasks move &lt;id&gt; doing</kbd>.
    </>
  ),
  review: 'Nothing waiting for review.',
  done: 'Nothing finished yet.',
  blocked: 'Nothing blocked.',
}

function TaskCard({ task, store, owners }: { task: Task; store: Store; owners: string[] }) {
  const [saving, setSaving] = useState(false)
  const [conflict, setConflict] = useState<number>()
  const priority = task.priority ?? 'P2'

  const change = async (patch: { status?: TaskStatus; owner?: string; priority?: Priority }) => {
    setSaving(true)
    try {
      await api.updateTask(task, patch)
      setConflict(undefined)
    } catch (err) {
      // Another agent changed it first: reload instead of overwriting their revision.
      if (err instanceof ApiError && err.status === 409) {
        setConflict(task.revision)
        await store.refresh()
      } else store.report(err)
    } finally {
      setSaving(false)
    }
  }

  return (
    <article className="card" aria-busy={saving || undefined}>
      <div className="card-top">
        <span className={'prio prio-' + priority} title={`${priority} · ${PRIORITY_HELP[priority]} priority`}>
          {priority}
        </span>
        <time className="card-age" dateTime={task.updated_at} title={new Date(task.updated_at).toLocaleString()}>
          {ago(task.updated_at, store.now)}
        </time>
      </div>
      <p className="card-title">{task.title}</p>
      <div className="card-meta">
        {task.owner ? (
          <span className="owner">
            <AgentSprite agent={task.owner} scale={2} />
            {task.owner}
          </span>
        ) : (
          <span className="owner owner-none">Unassigned</span>
        )}
        <span className="mono muted" title={task.id}>
          rev {task.revision}
        </span>
      </div>
      {conflict !== undefined && (
        <p className="card-conflict" role="alert">
          Not saved: another agent changed this task while you had revision {conflict}. The card now shows the latest
          state; choose again if your change still applies.
        </p>
      )}
      {/* Two compact labelled rows keep the controls lighter than the task
          title; the visible word plus a hidden "of {task.title}" keeps each
          select's accessible name unique on the board. */}
      <div className="card-controls">
        <label className="control control-status">
          <span className="control-label" aria-hidden="true">
            Status
          </span>
          <span className="sr-only">Status of {task.title}</span>
          <select
            value={task.status}
            disabled={saving}
            onChange={(e) => void change({ status: e.target.value as TaskStatus })}
          >
            {TASK_STATUSES.map((s) => (
              <option key={s}>{s}</option>
            ))}
          </select>
        </label>
        <label className="control control-priority">
          <span className="control-label" aria-hidden="true">
            Priority
          </span>
          <span className="sr-only">Priority of {task.title}</span>
          <select
            value={priority}
            disabled={saving}
            onChange={(e) => void change({ priority: e.target.value as Priority })}
          >
            {PRIORITIES.map((p) => (
              <option key={p}>{p}</option>
            ))}
          </select>
        </label>
        <label className="control control-owner">
          <span className="control-label" aria-hidden="true">
            Owner
          </span>
          <span className="sr-only">Owner of {task.title}</span>
          <select
            value={task.owner ?? ''}
            disabled={saving}
            onChange={(e) => e.target.value && void change({ owner: e.target.value })}
          >
            <option value="">Assign an agent…</option>
            {owners.map((o) => (
              <option key={o}>{o}</option>
            ))}
          </select>
        </label>
      </div>
    </article>
  )
}

export function TasksView({ store }: { store: Store }) {
  const [title, setTitle] = useState('')
  const [priority, setPriority] = useState<Priority>('P2')
  const [busy, setBusy] = useState(false)
  const owners = [...new Set([...store.agents.map((a) => a.agent), ...store.tasks.flatMap((t) => t.owner ?? [])])].sort()

  const add = async (e: FormEvent) => {
    e.preventDefault()
    if (!title.trim()) return
    setBusy(true)
    try {
      await api.createTask(title.trim(), priority)
      setTitle('')
    } catch (err) {
      store.report(err)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="stack">
      <form className="toolbar" onSubmit={add}>
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
        <label className="sr-only" htmlFor="task-priority">
          Priority
        </label>
        <select id="task-priority" value={priority} onChange={(e) => setPriority(e.target.value as Priority)}>
          {PRIORITIES.map((p) => (
            <option key={p} value={p}>
              {p} · {PRIORITY_HELP[p]}
            </option>
          ))}
        </select>
        <button className="primary" disabled={busy || !title.trim()}>
          {busy ? 'Adding…' : 'Add task'}
        </button>
      </form>
      <div className="board">
        {TASK_STATUSES.map((status) => {
          const column = store.tasks
            .filter((t) => t.status === status)
            .sort(
              (a, b) =>
                (a.priority ?? 'P2').localeCompare(b.priority ?? 'P2') || b.updated_at.localeCompare(a.updated_at),
            )
          return (
            <section className={'column column-' + status} key={status} aria-labelledby={'col-' + status}>
              <h2 id={'col-' + status}>
                {status} <span className="column-count">{store.loaded ? column.length : '…'}</span>
              </h2>
              {!store.loaded ? (
                <span className="skeleton-bar tall" aria-hidden="true" />
              ) : column.length === 0 ? (
                <p className="column-empty">{COLUMN_EMPTY[status]}</p>
              ) : (
                column.map((task) => <TaskCard key={task.id} task={task} store={store} owners={owners} />)
              )}
            </section>
          )
        })}
      </div>
      <p className="muted small lede">
        Every change is revision-checked. If an agent moved a task first, your change is refused and the board reloads
        instead of overwriting theirs.
      </p>
    </div>
  )
}

/* Agents */

export function AgentsView({ store, office }: { store: Store; office: Office }) {
  if (!store.loaded) return <Loading label="Loading sessions" />
  if (store.agents.length === 0) {
    return (
      <Empty title="No sessions observed">
        Install host hooks with <kbd>install.sh --global --with-hooks</kbd>, connect an agent over MCP, or announce
        one by hand with <kbd>om --agent claude wake --session demo</kbd>.
      </Empty>
    )
  }
  const order: Agent['status'][] = ['active', 'ready', 'unknown', 'disconnected']
  const agents = [...store.agents].sort((a, b) => order.indexOf(a.status) - order.indexOf(b.status))
  const sources = [...new Set(store.agents.map((a) => a.source))]
  return (
    <div className="stack">
      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr>
              <th scope="col">Agent</th>
              <th scope="col">Status</th>
              <th scope="col">Room</th>
              <th scope="col">Signal</th>
              <th scope="col">Last seen</th>
              <th scope="col">First seen</th>
              <th scope="col">Session</th>
            </tr>
          </thead>
          <tbody>
            {agents.map((a) => {
              const p = office.placed.find((x) => x.agent === a)
              return (
                <tr key={a.agent + a.session_id} className={'row-' + a.status}>
                  <th scope="row">
                    <span className="cell-agent">
                      <AgentSprite agent={a.agent} scale={2} />
                      {a.agent}
                    </span>
                  </th>
                  <td>
                    <span className={'pill pill-' + a.status} title={STATUS_HELP[a.status]}>
                      {a.status}
                    </span>
                  </td>
                  <td>
                    {p ? (
                      roomLabel(p.room)
                    ) : (
                      <span className="muted">{a.status === 'disconnected' ? 'Left the office' : 'Room full'}</span>
                    )}
                  </td>
                  <td>{sourceLabel(a.source)}</td>
                  <td>
                    <time dateTime={a.last_seen} title={new Date(a.last_seen).toLocaleString()}>
                      {ago(a.last_seen, store.now)}
                    </time>
                  </td>
                  <td>
                    <time dateTime={a.first_seen} title={new Date(a.first_seen).toLocaleString()}>
                      {ago(a.first_seen, store.now)}
                    </time>
                  </td>
                  <td className="mono muted">{a.session_id}</td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>
      <div className="legend-grid">
        <section className="panel">
          <h2>What each status means</h2>
          <dl className="legend">
            {order.map((s) => (
              <div key={s}>
                <dt>
                  <span className={'pill pill-' + s}>{s}</span>
                  <span className="legend-count">{store.agents.filter((a) => a.status === s).length}</span>
                </dt>
                <dd>{STATUS_HELP[s]}</dd>
              </div>
            ))}
          </dl>
        </section>
        <section className="panel">
          <h2>Where these signals come from</h2>
          <dl className="legend">
            {sources.map((s) => (
              <div key={s}>
                <dt>{sourceLabel(s)}</dt>
                <dd>{SOURCE[s]?.how ?? 'A source this version of Mission Control does not describe.'}</dd>
              </div>
            ))}
          </dl>
        </section>
      </div>
    </div>
  )
}

/* Approvals */

export function ApprovalsView({ store }: { store: Store }) {
  const [busy, setBusy] = useState<string>()
  const pending = store.approvals.filter((a) => a.status === 'pending')
  const decided = store.approvals
    .filter((a) => a.status !== 'pending')
    .sort((a, b) => (b.decided_at ?? '').localeCompare(a.decided_at ?? ''))

  const decide = async (approval: Approval, decision: 'approved' | 'denied') => {
    setBusy(approval.id)
    try {
      await api.decide(approval, decision)
      await store.refresh()
    } catch (err) {
      store.report(err)
    } finally {
      setBusy(undefined)
    }
  }

  if (!store.loaded) return <Loading label="Loading approval requests" />

  return (
    <div className="stack">
      <p className="lede" id="approval-consequence">
        Your answer is a record, not a command. The agent reads it and acts on its own; OmniMemo never runs the action
        and an approval here never authorizes a Git push.
      </p>
      {pending.length === 0 ? (
        <Empty title="Nothing is waiting for you">
          Agents ask with <kbd>om approvals request "push main to origin" --reason "…"</kbd>; requests appear here
          and in the office's Approvals room.
        </Empty>
      ) : (
        <ul className="approvals" aria-label="Waiting for your decision">
          {pending.map((a) => (
            <li className="approval" key={a.id}>
              <span className="approval-who">
                <AgentSprite agent={a.requested_by} scale={3} />
                <span>{a.requested_by}</span>
              </span>
              <div className="approval-body">
                <h2>{a.action}</h2>
                {a.reason ? <p>{a.reason}</p> : <p className="muted">No reason given.</p>}
                <p className="muted small">
                  Asked{' '}
                  <time dateTime={a.created_at} title={new Date(a.created_at).toLocaleString()}>
                    {ago(a.created_at, store.now)}
                  </time>{' '}
                  · <span className="mono">{a.id}</span>
                </p>
              </div>
              <div className="approval-actions">
                <button
                  type="button"
                  className="primary"
                  disabled={busy === a.id}
                  aria-describedby="approval-consequence"
                  onClick={() => void decide(a, 'approved')}
                >
                  Approve
                </button>
                <button
                  type="button"
                  disabled={busy === a.id}
                  aria-describedby="approval-consequence"
                  onClick={() => void decide(a, 'denied')}
                >
                  Deny
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
      {decided.length > 0 && (
        <section className="panel">
          <h2>Decided</h2>
          <ul className="rows">
            {decided.map((a) => (
              <li key={a.id}>
                <span>{a.action}</span>
                <span className="muted small">asked by {a.requested_by}</span>
                <span className={'pill pill-' + a.status}>{a.status}</span>
                <span className="muted small">{a.decided_at ? ago(a.decided_at, store.now) : ''}</span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  )
}

/* Memory */

type Checkpoint = Partial<Record<'done' | 'next' | 'blocked' | 'tests' | 'changed_files', string[]>>
const CHECKPOINT_PARTS: [keyof Checkpoint, string][] = [
  ['done', 'Done'],
  ['next', 'Next'],
  ['blocked', 'Blocked'],
  ['tests', 'Tests reported'],
  ['changed_files', 'Changed files'],
]
/** Checkpoints are stored as JSON; anything else is shown as plain text. */
function parseCheckpoint(summary: string): Checkpoint | undefined {
  if (!summary.trimStart().startsWith('{')) return undefined
  try {
    const value = JSON.parse(summary) as Checkpoint
    return CHECKPOINT_PARTS.some(([k]) => Array.isArray(value[k])) ? value : undefined
  } catch {
    return undefined
  }
}

function MemoryItem({ m }: { m: Memory }) {
  const checkpoint = parseCheckpoint(m.summary)
  return (
    <li className="panel memory">
      <div className="memory-head">
        <h2>{m.title}</h2>
        {checkpoint && <span className="tag">handoff</span>}
        <span className={'pill pill-' + m.state} title={MEMORY_HELP[m.state]}>
          {m.state}
        </span>
      </div>
      {checkpoint ? (
        <dl className="checkpoint">
          {CHECKPOINT_PARTS.filter(([k]) => checkpoint[k]?.length).map(([k, label]) => (
            <div key={k}>
              <dt>{label}</dt>
              <dd>
                <ul>
                  {checkpoint[k]!.map((item, i) => (
                    <li key={i} className={k === 'changed_files' ? 'mono' : undefined}>
                      {item}
                    </li>
                  ))}
                </ul>
              </dd>
            </div>
          ))}
        </dl>
      ) : (
        <p>{m.summary}</p>
      )}
      {m.source_refs && m.source_refs.length > 0 && <p className="mono muted small">{m.source_refs.join(' · ')}</p>}
    </li>
  )
}

export function MemoryView({ store }: { store: Store }) {
  const [query, setQuery] = useState('')
  const [shown, setShown] = useState('')
  const [results, setResults] = useState<Memory[]>()
  const [searching, setSearching] = useState(false)
  const run = async (q: string) => {
    setSearching(true)
    try {
      setResults(await api.search(q))
      setShown(q)
    } catch (err) {
      store.report(err)
    } finally {
      setSearching(false)
    }
  }
  useEffect(() => {
    void run('')
    // Load once on arrival; later searches are explicit.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  const search = (e: FormEvent) => {
    e.preventDefault()
    void run(query.trim())
  }
  return (
    <div className="stack">
      <form className="toolbar" onSubmit={search} role="search">
        <label className="sr-only" htmlFor="memory-query">
          Search memory
        </label>
        <input
          id="memory-query"
          type="search"
          value={query}
          maxLength={200}
          placeholder="Search decisions, facts and handoffs"
          onChange={(e) => setQuery(e.target.value)}
        />
        <button className="primary" disabled={searching}>
          {searching ? 'Searching…' : 'Search'}
        </button>
      </form>
      {!results ? (
        <Loading label="Loading memory" rows={2} />
      ) : results.length === 0 ? (
        shown ? (
          <Empty title={`No memory matches “${shown}”`}>Try a shorter word, or a file path an agent recorded.</Empty>
        ) : (
          <Empty title="No memory saved yet">
            Agents save through MCP or with <kbd>om memory save</kbd>; handoffs come from <kbd>om checkpoint</kbd>.
          </Empty>
        )
      ) : (
        <>
          <div className="results-head" aria-live="polite">
            <p>
              <b>{results.length}</b> {results.length === 1 ? 'memory' : 'memories'}
              {shown ? <> matching “{shown}”</> : null}
            </p>
            <p className="muted small">
              {Object.entries(MEMORY_HELP).map(([state, help], i) => (
                <span key={state}>
                  {i > 0 && ' · '}
                  <span className="legend-word">{state}</span>: {help}
                </span>
              ))}
            </p>
          </div>
          <ul className="memories">
            {results.map((m) => (
              <MemoryItem key={m.id} m={m} />
            ))}
          </ul>
        </>
      )}
    </div>
  )
}

/* Events */

export function EventsView({ store }: { store: Store }) {
  const [kind, setKind] = useState<EventKind>('all')
  if (!store.loaded) return <Loading label="Loading events" rows={5} />
  if (store.events.length === 0) {
    return (
      <Empty title="No committed events yet">
        Every session signal, task move, approval and handoff is committed here in order, starting with the first.
      </Empty>
    )
  }
  const count = (k: EventKind) => (k === 'all' ? store.events.length : store.events.filter((e) => kindOf(e.type) === k).length)
  const list = kind === 'all' ? store.events : store.events.filter((e) => kindOf(e.type) === kind)
  return (
    <div className="stack">
      <div className="filters" role="group" aria-label="Filter events by kind">
        {EVENT_KINDS.map((k) => (
          <button key={k.id} type="button" aria-pressed={kind === k.id} onClick={() => setKind(k.id)}>
            {k.label} <span className="count">{count(k.id)}</span>
          </button>
        ))}
        <p className="muted small filters-note">Newest first · the most recent committed events, revision numbered.</p>
      </div>
      <section className="panel" aria-label="Events">
        {list.length === 0 ? (
          <p className="muted">No events of this kind in the recent window.</p>
        ) : (
          <ol className="events">
            {list.map((e) => (
              <EventLine key={e.event_id} e={e} store={store} />
            ))}
          </ol>
        )}
      </section>
    </div>
  )
}

import { type FormEvent, type ReactNode, useEffect, useRef, useState } from 'react'
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
import { AgentMark } from './Figure'
import { ago, PLAN, type Placement, ROOMS, type RoomId } from './office'
import { OfficeMap } from './OfficeMap'

type Office = { placed: Placement[]; overflow: Partial<Record<RoomId, number>> }
type Event = Store['events'][number]

const SOURCE: Record<string, { label: string; how: string }> = {
  // `om hook claude` names its source claude_hook; it is called by the omniverse-bridge plugin.
  claude_hook: { label: 'Claude Code plugin', how: 'The omniverse-bridge plugin: session, prompt, tool and turn events; tools by category only.' },
  codex_hook: { label: 'Codex hook', how: 'Codex hooks.json session and tool events.' },
  codex_app_server: { label: 'Managed Codex', how: 'om codex run: OmniMemo owns the app-server process and its heartbeat.' },
  gemini_hook: { label: 'Gemini CLI hook', how: 'Gemini CLI session and tool hooks.' },
  opencode_hook: { label: 'OpenCode plugin', how: 'The OmniMemo OpenCode plugin.' },
  mcp: { label: 'MCP connection', how: 'The first tool call from an MCP client.' },
  cli: { label: 'om CLI', how: 'An explicit om wake command; not a host hook.' },
}
const sourceLabel = (s: string) => SOURCE[s]?.label ?? s
const roomLabel = (id: RoomId) => ROOMS.find((r) => r.id === id)?.label ?? id

const STATUS_HELP: Record<Agent['status'], string> = {
  working: 'The host reported a prompt or tool call in this session.',
  waiting: 'The session reported in and is waiting for work.',
  blocked: 'The host reported the session is waiting on an approval or a blocker.',
  stale: 'No recent signal. It may still be running; OmniMemo cannot tell.',
  offline: 'The host reported that the session ended.',
}
const MEMORY_HELP: Record<string, string> = {
  active: 'saved with source evidence',
  unverified: 'saved without evidence',
  stale: 'a source file changed since it was saved',
}
const PRIORITY_HELP: Record<Priority, string> = { P0: 'urgent', P1: 'high', P2: 'normal', P3: 'low' }

/* Shared states */

function ContextIndicator({ agent, now }: { agent: Agent; now: number }) {
  const percent = agent.context_used_percent
  if (typeof percent !== 'number' || !Number.isFinite(percent) || percent < 0 || percent > 100 ||
      agent.status === 'stale' || agent.status === 'offline') {
    return <span className="muted" title="Context unknown: no current reported sample">unknown</span>
  }
  const level = percent >= 90 ? 'critical' : percent >= 80 ? 'handoff' : percent >= 70 ? 'prepare' : 'normal'
  const tokens = agent.context_window_tokens
  const capacity = typeof tokens === 'number' && Number.isInteger(tokens) && tokens > 0
    ? ` of ${tokens >= 1000 && tokens % 1000 === 0 ? `${tokens / 1000}k` : tokens.toLocaleString()} tokens`
    : ''
  const observed = agent.context_observed_at
  const reported = observed && Number.isFinite(Date.parse(observed))
    ? `reported ${ago(observed, now)}` : 'report time unknown'
  const handoff = agent.agent === 'claude' ? '/om-rollover in Claude Code' : 'om rollover prepare'
  const advice = level === 'critical' ? `; critical: hand off to a fresh session now (${handoff})`
    : level === 'handoff' ? `; hand off to a fresh session (${handoff})`
    : level === 'prepare' ? '; a checkpoint is worth saving (om rollover prepare)' : ''
  const description = `Context ${percent}%${capacity}, ${reported}${advice}`
  return (
    <span className={'context-usage context-' + level} title={description} role="meter"
      aria-label={description} aria-valuemin={0} aria-valuemax={100} aria-valuenow={percent}>
      <span className="context-track" aria-hidden="true">
        <span className="context-fill" style={{ width: `${percent}%` }} />
      </span>
      <span className="mono" aria-hidden="true">{percent}%</span>
    </span>
  )
}

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
  'runtime.activity': 'Agent activity',
  'context.usage.updated': 'Context usage',
  'rollover.prepared': 'Rollover prepared',
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
  if (e.type === 'agent.status.changed' || e.type === 'runtime.activity' || e.type === 'context.usage.updated')
    return e.entity_id.split(':').slice(1).join(':') || undefined
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
        <AgentMark agent={who} size={16} />
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

/** One state vocabulary for the plan, the schedule and the Agents table; each maps to a verified record. */
const PLAN_STATES: [string, Placement['tone'], string][] = [
  ['asks you', 'attention', 'The agent requested an approval that is waiting on you.'],
  ['blocked', 'attention', 'The host reported the session is blocked, with no pending approval.'],
  ['doing', 'working', 'The agent owns a task in doing; its host status shows whether it is active now.'],
  ['working', 'working', 'The host reported a prompt or tool call; no task is claimed.'],
  ['reviewing', 'flight', 'The agent owns a task in review.'],
  ['handing off', 'flight', 'The agent saved a checkpoint in the last three minutes.'],
  ['waiting', 'neutral', 'The session reported in and is waiting for work.'],
  ['stale', 'unknown', 'No recent signal, even if it owns a task. It may still be running; OmniMemo cannot tell.'],
]

const stateLabel = (p: Placement) => p.state[0].toUpperCase() + p.state.slice(1)

export function OfficeView({ store, office }: { store: Store; office: Office }) {
  const [selected, setSelected] = useState<string>()
  const scroller = useRef<HTMLDivElement>(null)
  const [scrollable, setScrollable] = useState(false)
  const current = office.placed.find((p) => p.key === selected) ?? office.placed[0]
  // On narrow screens the plan scrolls: open it at the room that waits on you, else the selection.
  const focusRoom = (office.placed.find((p) => p.approval) ?? current)?.room
  useEffect(() => {
    const el = scroller.current
    if (!el) return
    const fit = () => {
      const over = el.scrollWidth > el.clientWidth + 1
      setScrollable(over)
      const room = ROOMS.find((r) => r.id === focusRoom)
      if (!over || !room) return
      const scale = el.scrollWidth / PLAN.w
      el.scrollLeft = (room.x + room.w / 2) * scale - el.clientWidth / 2
    }
    fit()
    const observer = new ResizeObserver(fit)
    observer.observe(el)
    return () => observer.disconnect()
  }, [focusRoom])
  // Schedule order: what asks you first, then live work, then quiet and unknown sessions.
  const order: Placement['tone'][] = ['attention', 'working', 'flight', 'neutral', 'unknown']
  const schedule = [...office.placed].sort(
    (a, b) => order.indexOf(a.tone) - order.indexOf(b.tone) || b.agent.last_seen.localeCompare(a.agent.last_seen),
  )
  const hidden = Object.values(office.overflow).reduce((a, b) => a + (b ?? 0), 0)
  return (
    <div className="office">
      <section className={'sheet' + (scrollable ? ' is-scrollable' : '')} aria-label="Office floor plan">
        <div className="sheet-scroll" ref={scroller}>
          <OfficeMap
            placed={office.placed}
            overflow={office.overflow}
            health={store.health}
            selected={current?.key}
            now={store.now}
            live={store.live}
            onSelect={setSelected}
          />
        </div>
        <div className="sheet-cue" aria-hidden="true">
          <p>
            <span>Swipe for more rooms</span>
            <span>{office.placed.length} on the plan</span>
          </p>
          <ul className="sheet-key">
            <li className="key-working">working</li>
            <li className="key-attention">asks you</li>
            <li className="key-flight">reviewing</li>
            <li className="key-unknown">stale</li>
          </ul>
        </div>
        {store.loaded && office.placed.length === 0 && (
          <div className="map-empty">
            <p>
              {store.agents.length === 0
                ? 'No agent has reported in yet.'
                : 'Nobody is in the office: every observed session has gone offline.'}
            </p>
            <p className="muted">
              Agents appear once their host reports in: Claude Code through the omniverse-bridge plugin, Codex and
              Gemini through <kbd>install.sh --global --with-hooks</kbd>, any other agent by connecting over MCP.
            </p>
          </div>
        )}
      </section>
      <aside className="office-side">
        <section className="panel schedule" aria-labelledby="schedule-title">
          <h2 id="schedule-title">
            Agent schedule <span className="panel-note">{office.placed.length + hidden} present</span>
          </h2>
          {!store.loaded ? (
            <span className="skeleton-bar" aria-hidden="true" />
          ) : schedule.length === 0 ? (
            <p className="muted panel-body">Nobody on the plan.</p>
          ) : (
            <table className="table dense">
              <thead>
                <tr>
                  <th scope="col">Agent</th>
                  <th scope="col">Room</th>
                  <th scope="col">State</th>
                  <th scope="col" className="num">
                    Signal
                  </th>
                </tr>
              </thead>
              <tbody>
                {schedule.map((p) => (
                  <tr key={p.key} className={current?.key === p.key ? 'is-selected' : undefined}>
                    <th scope="row">
                      <button type="button" className="row-select" aria-pressed={current?.key === p.key} onClick={() => setSelected(p.key)}>
                        <AgentMark agent={p.agent.agent} size={16} unknown={p.tone === 'unknown'} />
                        {p.agent.agent}
                      </button>
                    </th>
                    <td>{roomLabel(p.room)}</td>
                    <td>
                      <span className={'pill pill-tone-' + p.tone}>{stateLabel(p)}</span>
                    </td>
                    <td className="num mono">{ago(p.agent.last_seen, store.now).replace(' ago', '')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          {hidden > 0 && (
            <p className="panel-foot muted small">
              {hidden} more in full rooms. <a href="#agents">All agents</a>
            </p>
          )}
        </section>
        <section className="panel detail" aria-live="polite">
          {current ? (
            <>
              <h2>
                <span className="detail-name">
                  <AgentMark agent={current.agent.agent} size={22} unknown={current.tone === 'unknown'} />
                  {current.agent.agent}
                </span>
                <span className="panel-note mono">{current.agent.session_id}</span>
              </h2>
              <dl className="facts">
                <dt>State</dt>
                <dd>
                  <span className={'pill pill-tone-' + current.tone}>{stateLabel(current)}</span>
                </dd>
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
                    <dt>Asks you</dt>
                    <dd>
                      <a href="#approvals">{current.approval.action}</a>
                    </dd>
                  </>
                )}
                <dt>Signal</dt>
                <dd>{sourceLabel(current.agent.source)}</dd>
                <dt>Last seen</dt>
                <dd>{ago(current.agent.last_seen, store.now)}</dd>
                <dt>Context</dt>
                <dd>
                  <ContextIndicator agent={current.agent} now={store.now} />
                </dd>
              </dl>
            </>
          ) : (
            <p className="muted panel-body">
              {store.loaded ? 'Select an agent on the plan to see where its status comes from.' : 'Loading sessions…'}
            </p>
          )}
        </section>
        <section className="panel" aria-labelledby="latest-title">
          <h2 id="latest-title">
            Latest events <a className="panel-note" href="#events">All events</a>
          </h2>
          {store.events.length === 0 ? (
            <p className="muted panel-body">{store.loaded ? 'No committed events yet.' : 'Loading events…'}</p>
          ) : (
            <ol className="events compact">
              {store.events.slice(0, 5).map((e) => (
                <EventLine key={e.event_id} e={e} store={store} />
              ))}
            </ol>
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

function TaskRow({
  task,
  store,
  owners,
  conflict,
  setConflict,
}: {
  task: Task
  store: Store
  owners: string[]
  conflict?: number
  setConflict: (id: string, revision?: number) => void
}) {
  const [saving, setSaving] = useState(false)
  const priority = task.priority ?? 'P2'

  const change = async (patch: { status?: TaskStatus; owner?: string; priority?: Priority }) => {
    setSaving(true)
    try {
      await api.updateTask(task, patch)
      setConflict(task.id, undefined)
    } catch (err) {
      // Another agent changed it first: reload instead of overwriting their revision.
      if (err instanceof ApiError && err.status === 409) {
        setConflict(task.id, task.revision)
        await store.refresh()
      } else store.report(err)
    } finally {
      setSaving(false)
    }
  }

  return (
    <>
      <tr className={saving ? 'is-saving' : undefined} aria-busy={saving || undefined}>
        <td>
          <label className="sr-only" htmlFor={'prio-' + task.id}>
            Priority of {task.title}
          </label>
          <select
            id={'prio-' + task.id}
            className={'prio prio-' + priority}
            value={priority}
            disabled={saving}
            title={`${priority} · ${PRIORITY_HELP[priority]} priority`}
            onChange={(e) => void change({ priority: e.target.value as Priority })}
          >
            {PRIORITIES.map((p) => (
              <option key={p}>{p}</option>
            ))}
          </select>
        </td>
        <th scope="row" className="task-title">
          {task.title}
        </th>
        <td>
          <label className="sr-only" htmlFor={'owner-' + task.id}>
            Owner of {task.title}
          </label>
          <span className="owner">
            {task.owner && <AgentMark agent={task.owner} size={16} />}
            <select
              id={'owner-' + task.id}
              value={task.owner ?? ''}
              disabled={saving}
              onChange={(e) => e.target.value && void change({ owner: e.target.value })}
            >
              <option value="">Unassigned</option>
              {owners.map((o) => (
                <option key={o}>{o}</option>
              ))}
            </select>
          </span>
        </td>
        <td>
          <label className="sr-only" htmlFor={'status-' + task.id}>
            Status of {task.title}
          </label>
          <select
            id={'status-' + task.id}
            value={task.status}
            disabled={saving}
            onChange={(e) => void change({ status: e.target.value as TaskStatus })}
          >
            {TASK_STATUSES.map((s) => (
              <option key={s}>{s}</option>
            ))}
          </select>
        </td>
        <td className="num">
          <time dateTime={task.updated_at} title={new Date(task.updated_at).toLocaleString()}>
            {ago(task.updated_at, store.now)}
          </time>
        </td>
        <td className="num mono muted" title={task.id}>
          {task.revision}
        </td>
      </tr>
      {conflict !== undefined && (
        <tr className="conflict-row">
          <td colSpan={6} role="alert">
            Not saved: another agent changed this task while you had revision {conflict}. The row now shows the latest
            state; choose again if your change still applies.
          </td>
        </tr>
      )}
    </>
  )
}

export function TasksView({ store }: { store: Store }) {
  // Kept here, keyed by task, so a warning survives the refresh moving its row to another status group.
  const [conflicts, setConflicts] = useState<Record<string, number>>({})
  const setConflict = (id: string, revision?: number) =>
    setConflicts(({ [id]: _, ...rest }) => (revision === undefined ? rest : { ...rest, [id]: revision }))
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
      {!store.loaded ? (
        <Loading label="Loading tasks" rows={4} />
      ) : (
        <div className="table-wrap">
          <table className="table tasks">
            <colgroup>
              <col className="col-prio" />
              <col />
              <col className="col-owner" />
              <col className="col-status" />
              <col className="col-age" />
              <col className="col-rev" />
            </colgroup>
            <thead>
              <tr>
                <th scope="col">Priority</th>
                <th scope="col">Task</th>
                <th scope="col">Owner</th>
                <th scope="col">Status</th>
                <th scope="col" className="num">
                  Updated
                </th>
                <th scope="col" className="num">
                  Rev
                </th>
              </tr>
            </thead>
            {TASK_STATUSES.map((status) => {
              const group = store.tasks
                .filter((t) => t.status === status)
                .sort(
                  (a, b) =>
                    (a.priority ?? 'P2').localeCompare(b.priority ?? 'P2') || b.updated_at.localeCompare(a.updated_at),
                )
              return (
                <tbody key={status} className={'group group-' + status} aria-labelledby={'group-' + status}>
                  <tr className="group-head">
                    <th scope="colgroup" colSpan={6} id={'group-' + status}>
                      {status} <span className="count">{group.length}</span>
                    </th>
                  </tr>
                  {group.length === 0 ? (
                    <tr className="group-empty">
                      <td colSpan={6}>{COLUMN_EMPTY[status]}</td>
                    </tr>
                  ) : (
                    group.map((task) => (
                      <TaskRow
                        key={task.id}
                        task={task}
                        store={store}
                        owners={owners}
                        conflict={conflicts[task.id]}
                        setConflict={setConflict}
                      />
                    ))
                  )}
                </tbody>
              )
            })}
          </table>
        </div>
      )}
      <p className="muted small lede">
        Every change is revision-checked. If an agent moved a task first, your change is refused and the list reloads
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
        Agents appear once their host reports in. Run <kbd>install.sh --global --with-hooks</kbd> once: Claude Code
        gets the omniverse-bridge plugin, Codex and Gemini get hooks, OpenCode its plugin. Any other agent appears
        when it connects over MCP.
      </Empty>
    )
  }
  const order: Agent['status'][] = ['working', 'blocked', 'waiting', 'stale', 'offline']
  const agents = [...store.agents].sort((a, b) => order.indexOf(a.status) - order.indexOf(b.status))
  const sources = [...new Set(store.agents.map((a) => a.source))]
  return (
    <div className="stack">
      <p className="muted small">
        Status: working, waiting, blocked, offline, or stale (no recent signal). Context is the share of the
        model's window the host reported: at 70% save a checkpoint, at 80% hand off to a fresh session, 90% is
        critical.
      </p>
      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr>
              <th scope="col">Agent</th>
              <th scope="col">Status</th>
              <th scope="col">Context</th>
              <th scope="col">Room · plan state</th>
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
                      <AgentMark agent={a.agent} size={20} unknown={a.status === 'stale'} />
                      {a.agent}
                    </span>
                  </th>
                  <td>
                    <span className={'pill pill-' + a.status} title={STATUS_HELP[a.status]}>
                      {a.status}
                    </span>
                  </td>
                  <td><ContextIndicator agent={a} now={store.now} /></td>
                  <td>
                    {p ? (
                      <>
                        {roomLabel(p.room)} <span className="muted">· {p.state}</span>
                      </>
                    ) : (
                      <span className="muted">{a.status === 'offline' ? 'Left the office' : 'Room full'}</span>
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
          <h2>What each state means</h2>
          <dl className="legend">
            {PLAN_STATES.map(([state, tone, help]) => (
              <div key={state}>
                <dt>
                  <span className={'pill pill-tone-' + tone}>{state[0].toUpperCase() + state.slice(1)}</span>
                  <span className="legend-count">{office.placed.filter((p) => p.state === state).length}</span>
                </dt>
                <dd>{help}</dd>
              </div>
            ))}
          </dl>
          <p className="panel-foot muted small">
            The Status column and Events show the host status as reported (working, waiting, blocked, stale,
            offline); the plan state comes from it plus the agent's tasks and approvals.
          </p>
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

  const [notice, setNotice] = useState<string>()
  const decide = async (approval: Approval, decision: 'approved' | 'denied') => {
    setBusy(approval.id)
    setNotice(undefined)
    try {
      await api.decide(approval, decision)
      await store.refresh()
    } catch (err) {
      // Expected outcomes, not failures: the Mac check was cancelled, or someone decided first.
      if (err instanceof ApiError && err.status === 403 && decision === 'approved') {
        setNotice('Not approved: the confirmation at this Mac was cancelled. The request is still waiting.')
      } else if (err instanceof ApiError && err.status === 409) {
        setNotice('This request was already decided; the list has been refreshed.')
        await store.refresh()
      } else store.report(err)
    } finally {
      setBusy(undefined)
    }
  }

  if (!store.loaded) return <Loading label="Loading approval requests" />

  return (
    <div className="stack">
      <p className="lede" id="approval-consequence">
        Your answer is a record, not a command. The agent reads it and acts on its own; OmniMemo never runs the action
        and an approval here never authorizes a Git push. Approving opens a macOS dialog: confirm with Touch ID or
        your password.
      </p>
      {notice ? (
        <p className="muted" role="status">
          {notice}
        </p>
      ) : null}
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
                <AgentMark agent={a.requested_by} size={36} />
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
      {m.source_refs && m.source_refs.length > 0 && (
        <p className="muted small">
          Source evidence: <span className="mono">{m.source_refs.join(' · ')}</span>
        </p>
      )}
    </li>
  )
}

export function MemoryView({ store }: { store: Store }) {
  const [query, setQuery] = useState('')
  const [shown, setShown] = useState('')
  const [results, setResults] = useState<Memory[]>()
  const [searching, setSearching] = useState(false)
  const latest = useRef(0)
  const run = async (q: string) => {
    // A slow earlier search must not replace the results of a later one.
    const n = ++latest.current
    setSearching(true)
    try {
      const found = await api.search(q)
      if (n !== latest.current) return
      setResults(found)
      setShown(q)
    } catch (err) {
      if (n === latest.current) store.report(err)
    } finally {
      if (n === latest.current) setSearching(false)
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

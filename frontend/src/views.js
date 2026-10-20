import { Fragment as _Fragment, jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useRef, useState } from 'react';
import { agentName, ApiError, PRIORITIES, TASK_STATUSES, api, } from './api';
import { AgentMark } from './Figure';
import { ago, inOffice, PLAN, ROOMS } from './office';
import { OfficeMap } from './OfficeMap';
const SOURCE = {
    // `om hook claude` names its source claude_hook; it is called by the omniverse-bridge plugin.
    claude_hook: { label: 'Claude Code plugin', how: 'The omniverse-bridge plugin: session, prompt, tool and turn events; tools by category only.' },
    codex_hook: { label: 'Codex hook', how: 'Codex hooks.json session and tool events.' },
    codex_app_server: { label: 'Managed Codex', how: 'om codex run: OmniMemo owns the app-server process and its heartbeat.' },
    gemini_hook: { label: 'Gemini CLI hook', how: 'Gemini CLI session and tool hooks.' },
    opencode_hook: { label: 'OpenCode plugin', how: 'The OmniMemo OpenCode plugin.' },
    mcp: { label: 'MCP connection', how: 'The first tool call from an MCP client.' },
    cli: { label: 'om CLI', how: 'An explicit om wake command; not a host hook.' },
};
const sourceLabel = (s) => SOURCE[s]?.label ?? s;
const roomLabel = (id) => ROOMS.find((r) => r.id === id)?.label ?? id;
const STATUS_HELP = {
    working: 'The host reported a prompt or tool call in this session.',
    waiting: 'The session reported in and is waiting for work.',
    blocked: 'The host reported the session is waiting on an approval or a blocker.',
    stale: 'No recent signal. It may still be running; OmniMemo cannot tell. It leaves the office map until its next signal.',
    offline: 'The host reported that the session ended.',
};
const MEMORY_HELP = {
    active: 'saved with source evidence',
    unverified: 'saved without evidence',
    stale: 'a source file changed since it was saved',
};
const PRIORITY_HELP = { P0: 'urgent', P1: 'high', P2: 'normal', P3: 'low' };
/* Shared states */
function ContextIndicator({ agent, now }) {
    const percent = agent.context_used_percent;
    if (typeof percent !== 'number' || !Number.isFinite(percent) || percent < 0 || percent > 100 ||
        agent.status === 'stale' || agent.status === 'offline') {
        const used = agent.context_used_tokens;
        if (typeof used === 'number' && Number.isInteger(used) && used >= 0 && agent.status !== 'stale' && agent.status !== 'offline') {
            const text = used >= 1000 ? `${Math.round(used / 1000)}k tokens` : `${used} tokens`;
            const when = agent.context_observed_at ? `, reported ${ago(agent.context_observed_at, now)}` : '';
            const description = `${used.toLocaleString()} tokens in use${when}; this model's window is unknown, so no percent`;
            return _jsx("span", { className: "mono", title: description, "aria-label": description, children: text });
        }
        return _jsx("span", { className: "muted", title: "Context unknown: no current reported sample", children: "unknown" });
    }
    const level = percent >= 90 ? 'critical' : percent >= 80 ? 'handoff' : percent >= 70 ? 'prepare' : 'normal';
    const tokens = agent.context_window_tokens;
    const capacity = typeof tokens === 'number' && Number.isInteger(tokens) && tokens > 0
        ? ` of ${tokens >= 1000 && tokens % 1000 === 0 ? `${tokens / 1000}k` : tokens.toLocaleString()} tokens`
        : '';
    const observed = agent.context_observed_at;
    const reported = observed && Number.isFinite(Date.parse(observed))
        ? `reported ${ago(observed, now)}` : 'report time unknown';
    const handoff = agent.agent === 'claude' ? '/om-rollover in Claude Code' : 'om rollover prepare';
    const advice = level === 'critical' ? `; critical: hand off to a fresh session now (${handoff})`
        : level === 'handoff' ? `; hand off to a fresh session (${handoff})`
            : level === 'prepare' ? '; a checkpoint is worth saving (om rollover prepare)' : '';
    const description = `Context ${percent}%${capacity}, ${reported}${advice}`;
    return (_jsxs("span", { className: 'context-usage context-' + level, title: description, role: "meter", "aria-label": description, "aria-valuemin": 0, "aria-valuemax": 100, "aria-valuenow": percent, children: [_jsx("span", { className: "context-track", "aria-hidden": "true", children: _jsx("span", { className: "context-fill", style: { width: `${percent}%` } }) }), _jsxs("span", { className: "mono", "aria-hidden": "true", children: [percent, "%"] })] }));
}
function Loading({ label, rows = 3 }) {
    return (_jsxs("div", { className: "panel skeleton", role: "status", children: [_jsx("span", { className: "sr-only", children: label }), Array.from({ length: rows }, (_, i) => (_jsx("span", { className: "skeleton-bar", "aria-hidden": "true" }, i)))] }));
}
function Empty({ title, children }) {
    return (_jsxs("div", { className: "panel empty", children: [_jsx("h2", { children: title }), children && _jsx("p", { className: "muted", children: children })] }));
}
/* Events */
const EVENT_LABEL = {
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
};
const EVENT_KINDS = [
    { id: 'all', label: 'All' },
    { id: 'session', label: 'Sessions' },
    { id: 'task', label: 'Tasks' },
    { id: 'approval', label: 'Approvals' },
    { id: 'memory', label: 'Handoffs' },
];
const kindOf = (type) => {
    const head = type.split('.')[0];
    if (head === 'agent' || head === 'session')
        return 'session';
    if (head === 'task' || head === 'approval' || head === 'memory')
        return head;
    return 'all';
};
/** What the event is about, resolved only from records the store already holds. */
function subjectOf(e, store) {
    if (e.type === 'task.updated')
        return store.tasks.find((t) => t.id === e.entity_id)?.title;
    if (e.type.startsWith('approval.'))
        return store.approvals.find((a) => a.id === e.entity_id)?.action;
    if (e.type === 'agent.status.changed' || e.type === 'runtime.activity' || e.type === 'context.usage.updated')
        return e.entity_id.split(':').slice(1).join(':') || undefined;
    return undefined;
}
function EventLine({ e, store }) {
    const who = e.data.agent || e.entity_id.split(':')[0];
    const subject = subjectOf(e, store);
    return (_jsxs("li", { className: "event", children: [_jsxs("span", { className: "mono rev", children: ["#", e.revision] }), _jsxs("span", { className: "event-main", title: e.type, children: [_jsx("span", { className: "event-label", children: EVENT_LABEL[e.type] ?? e.type }), subject ? (_jsx("span", { className: "event-subject", children: subject })) : !EVENT_LABEL[e.type] ? (_jsx("span", { className: "event-subject mono", children: e.entity_id })) : null] }), _jsxs("span", { className: "event-who", children: [_jsx(AgentMark, { agent: who, size: 16 }), who] }), e.data.status ? (_jsx("span", { className: 'pill pill-' + e.data.status, children: e.data.status })) : (_jsx("span", { className: "pill-none" })), _jsx("time", { className: "event-time", dateTime: e.timestamp, title: new Date(e.timestamp).toLocaleString(), children: ago(e.timestamp, store.now) })] }));
}
/* Office */
/** One state vocabulary for the plan, the schedule and the Agents table; each maps to a verified record. */
const PLAN_STATES = [
    ['asks you', 'attention', 'The agent requested an approval that is waiting on you.'],
    ['blocked', 'attention', 'The host reported the session is blocked, with no pending approval.'],
    ['doing', 'working', 'The agent owns a task in doing; its host status shows whether it is active now.'],
    ['working', 'working', 'The host reported a prompt or tool call; no task is claimed.'],
    ['reviewing', 'flight', 'The agent owns a task in review.'],
    ['handing off', 'flight', 'The agent saved a checkpoint in the last three minutes.'],
    ['waiting', 'neutral', 'The session reported in and is waiting for work.'],
];
const stateLabel = (p) => p.state[0].toUpperCase() + p.state.slice(1);
export function OfficeView({ store, office }) {
    const [selected, setSelected] = useState();
    const scroller = useRef(null);
    const [scrollable, setScrollable] = useState(false);
    const current = office.placed.find((p) => p.key === selected) ?? office.placed[0];
    // On narrow screens the plan scrolls: open it at the room that waits on you, else the selection.
    const focusRoom = (office.placed.find((p) => p.approval) ?? current)?.room;
    useEffect(() => {
        const el = scroller.current;
        if (!el)
            return;
        const fit = () => {
            const over = el.scrollWidth > el.clientWidth + 1;
            setScrollable(over);
            const room = ROOMS.find((r) => r.id === focusRoom);
            if (!over || !room)
                return;
            const scale = el.scrollWidth / PLAN.w;
            el.scrollLeft = (room.x + room.w / 2) * scale - el.clientWidth / 2;
        };
        fit();
        const observer = new ResizeObserver(fit);
        observer.observe(el);
        return () => observer.disconnect();
    }, [focusRoom]);
    // Schedule order: what asks you first, then live work, then quiet and unknown sessions.
    const order = ['attention', 'working', 'flight', 'neutral', 'unknown'];
    const schedule = [...office.placed].sort((a, b) => order.indexOf(a.tone) - order.indexOf(b.tone) || b.agent.last_seen.localeCompare(a.agent.last_seen));
    const hidden = Object.values(office.overflow).reduce((a, b) => a + (b ?? 0), 0);
    return (_jsxs("div", { className: "office", children: [_jsxs("section", { className: 'sheet' + (scrollable ? ' is-scrollable' : ''), "aria-label": "Office floor plan", children: [_jsx("div", { className: "sheet-scroll", ref: scroller, children: _jsx(OfficeMap, { placed: office.placed, overflow: office.overflow, health: store.health, selected: current?.key, now: store.now, live: store.live, onSelect: setSelected }) }), _jsxs("div", { className: "sheet-cue", "aria-hidden": "true", children: [_jsxs("p", { children: [_jsx("span", { children: "Swipe for more rooms" }), _jsxs("span", { children: [office.placed.length, " on the plan"] })] }), _jsxs("ul", { className: "sheet-key", children: [_jsx("li", { className: "key-working", children: "working" }), _jsx("li", { className: "key-attention", children: "asks you" }), _jsx("li", { className: "key-flight", children: "reviewing" })] })] }), store.loaded && office.placed.length === 0 && (_jsxs("div", { className: "map-empty", children: [_jsx("p", { children: store.agents.length === 0
                                    ? 'No agent has reported in yet.'
                                    : 'Nobody is in the office: every observed session has ended or gone silent.' }), _jsxs("p", { className: "muted", children: ["Agents appear once their host reports in: Claude Code through the omniverse-bridge plugin, Codex and Gemini through ", _jsx("kbd", { children: "install.sh --global --with-hooks" }), ", any other agent by connecting over MCP."] })] }))] }), _jsxs("aside", { className: "office-side", children: [_jsxs("section", { className: "panel schedule", "aria-labelledby": "schedule-title", children: [_jsxs("h2", { id: "schedule-title", children: ["Agent schedule ", _jsxs("span", { className: "panel-note", children: [office.placed.length + hidden, " present"] })] }), !store.loaded ? (_jsx("span", { className: "skeleton-bar", "aria-hidden": "true" })) : schedule.length === 0 ? (_jsx("p", { className: "muted panel-body", children: "Nobody on the plan." })) : (_jsxs("table", { className: "table dense", children: [_jsx("thead", { children: _jsxs("tr", { children: [_jsx("th", { scope: "col", children: "Agent" }), _jsx("th", { scope: "col", children: "Room" }), _jsx("th", { scope: "col", children: "State" }), _jsx("th", { scope: "col", className: "num", children: "Signal" })] }) }), _jsx("tbody", { children: schedule.map((p) => (_jsxs("tr", { className: current?.key === p.key ? 'is-selected' : undefined, children: [_jsx("th", { scope: "row", children: _jsxs("button", { type: "button", className: "row-select", "aria-pressed": current?.key === p.key, onClick: () => setSelected(p.key), children: [_jsx(AgentMark, { agent: p.agent.agent, size: 16, unknown: p.tone === 'unknown' }), agentName(p.agent)] }) }), _jsx("td", { children: roomLabel(p.room) }), _jsx("td", { children: _jsx("span", { className: 'pill pill-tone-' + p.tone, children: stateLabel(p) }) }), _jsx("td", { className: "num mono", children: ago(p.agent.last_seen, store.now).replace(' ago', '') })] }, p.key))) })] })), hidden > 0 && (_jsxs("p", { className: "panel-foot muted small", children: [hidden, " more in full rooms. ", _jsx("a", { href: "#agents", children: "All agents" })] }))] }), _jsx("section", { className: "panel detail", "aria-live": "polite", children: current ? (_jsxs(_Fragment, { children: [_jsxs("h2", { children: [_jsxs("span", { className: "detail-name", children: [_jsx(AgentMark, { agent: current.agent.agent, size: 22, unknown: current.tone === 'unknown' }), agentName(current.agent)] }), _jsx("span", { className: "panel-note mono", children: current.agent.session_id })] }), _jsxs("dl", { className: "facts", children: [_jsx("dt", { children: "State" }), _jsx("dd", { children: _jsx("span", { className: 'pill pill-tone-' + current.tone, children: stateLabel(current) }) }), _jsx("dt", { children: "Room" }), _jsx("dd", { children: roomLabel(current.room) }), _jsx("dt", { children: "Task" }), _jsx("dd", { children: current.task ? (_jsxs(_Fragment, { children: [current.task.title, " ", _jsxs("span", { className: "mono muted", children: ["rev ", current.task.revision] })] })) : (_jsx("span", { className: "muted", children: "none claimed" })) }), current.approval && (_jsxs(_Fragment, { children: [_jsx("dt", { children: "Asks you" }), _jsx("dd", { children: _jsx("a", { href: "#approvals", children: current.approval.action }) })] })), current.agent.spawned_by && (_jsxs(_Fragment, { children: [_jsx("dt", { children: "Subagent of" }), _jsx("dd", { className: "mono", children: current.agent.spawned_by })] })), _jsx("dt", { children: "Signal" }), _jsx("dd", { children: sourceLabel(current.agent.source) }), _jsx("dt", { children: "Last seen" }), _jsx("dd", { children: ago(current.agent.last_seen, store.now) }), _jsx("dt", { children: "Context" }), _jsx("dd", { children: _jsx(ContextIndicator, { agent: current.agent, now: store.now }) })] })] })) : (_jsx("p", { className: "muted panel-body", children: store.loaded ? 'Select an agent on the plan to see where its status comes from.' : 'Loading sessions…' })) }), _jsxs("section", { className: "panel", "aria-labelledby": "latest-title", children: [_jsxs("h2", { id: "latest-title", children: ["Latest events ", _jsx("a", { className: "panel-note", href: "#events", children: "All events" })] }), store.events.length === 0 ? (_jsx("p", { className: "muted panel-body", children: store.loaded ? 'No committed events yet.' : 'Loading events…' })) : (_jsx("ol", { className: "events compact", children: store.events.slice(0, 5).map((e) => (_jsx(EventLine, { e: e, store: store }, e.event_id))) }))] })] })] }));
}
/* Tasks */
const COLUMN_EMPTY = {
    todo: (_jsxs(_Fragment, { children: ["No open tasks. Add one above or run ", _jsx("kbd", { children: "om tasks add \"title\"" }), "."] })),
    doing: (_jsxs(_Fragment, { children: ["Nothing in progress. An agent claims work with ", _jsx("kbd", { children: "om tasks move <id> doing" }), "."] })),
    review: 'Nothing waiting for review.',
    done: 'Nothing finished yet.',
    blocked: 'Nothing blocked.',
};
function TaskRow({ task, store, owners, conflict, setConflict, }) {
    const [saving, setSaving] = useState(false);
    const priority = task.priority ?? 'P2';
    const change = async (patch) => {
        setSaving(true);
        try {
            await api.updateTask(task, patch);
            setConflict(task.id, undefined);
        }
        catch (err) {
            // Another agent changed it first: reload instead of overwriting their revision.
            if (err instanceof ApiError && err.status === 409) {
                setConflict(task.id, task.revision);
                await store.refresh();
            }
            else
                store.report(err);
        }
        finally {
            setSaving(false);
        }
    };
    return (_jsxs(_Fragment, { children: [_jsxs("tr", { className: saving ? 'is-saving' : undefined, "aria-busy": saving || undefined, children: [_jsxs("td", { children: [_jsxs("label", { className: "sr-only", htmlFor: 'prio-' + task.id, children: ["Priority of ", task.title] }), _jsx("select", { id: 'prio-' + task.id, className: 'prio prio-' + priority, value: priority, disabled: saving, title: `${priority} · ${PRIORITY_HELP[priority]} priority`, onChange: (e) => void change({ priority: e.target.value }), children: PRIORITIES.map((p) => (_jsx("option", { children: p }, p))) })] }), _jsx("th", { scope: "row", className: "task-title", children: task.title }), _jsxs("td", { children: [_jsxs("label", { className: "sr-only", htmlFor: 'owner-' + task.id, children: ["Owner of ", task.title] }), _jsxs("span", { className: "owner", children: [task.owner && _jsx(AgentMark, { agent: task.owner, size: 16 }), _jsxs("select", { id: 'owner-' + task.id, value: task.owner ?? '', disabled: saving, onChange: (e) => e.target.value && void change({ owner: e.target.value }), children: [_jsx("option", { value: "", children: "Unassigned" }), owners.map((o) => (_jsx("option", { children: o }, o)))] })] })] }), _jsxs("td", { children: [_jsxs("label", { className: "sr-only", htmlFor: 'status-' + task.id, children: ["Status of ", task.title] }), _jsx("select", { id: 'status-' + task.id, value: task.status, disabled: saving, onChange: (e) => void change({ status: e.target.value }), children: TASK_STATUSES.map((s) => (_jsx("option", { children: s }, s))) })] }), _jsx("td", { className: "num", children: _jsx("time", { dateTime: task.updated_at, title: new Date(task.updated_at).toLocaleString(), children: ago(task.updated_at, store.now) }) }), _jsx("td", { className: "num mono muted", title: task.id, children: task.revision })] }), conflict !== undefined && (_jsx("tr", { className: "conflict-row", children: _jsxs("td", { colSpan: 6, role: "alert", children: ["Not saved: another agent changed this task while you had revision ", conflict, ". The row now shows the latest state; choose again if your change still applies."] }) }))] }));
}
export function TasksView({ store }) {
    // Kept here, keyed by task, so a warning survives the refresh moving its row to another status group.
    const [conflicts, setConflicts] = useState({});
    const setConflict = (id, revision) => setConflicts(({ [id]: _, ...rest }) => (revision === undefined ? rest : { ...rest, [id]: revision }));
    const [title, setTitle] = useState('');
    const [priority, setPriority] = useState('P2');
    const [busy, setBusy] = useState(false);
    const owners = [...new Set([...store.agents.map((a) => a.agent), ...store.tasks.flatMap((t) => t.owner ?? [])])].sort();
    const add = async (e) => {
        e.preventDefault();
        if (!title.trim())
            return;
        setBusy(true);
        try {
            await api.createTask(title.trim(), priority);
            setTitle('');
        }
        catch (err) {
            store.report(err);
        }
        finally {
            setBusy(false);
        }
    };
    return (_jsxs("div", { className: "stack", children: [_jsxs("form", { className: "toolbar", onSubmit: add, children: [_jsx("label", { className: "sr-only", htmlFor: "task-title", children: "New task" }), _jsx("input", { id: "task-title", value: title, maxLength: 240, placeholder: "Describe a task for an agent", onChange: (e) => setTitle(e.target.value) }), _jsx("label", { className: "sr-only", htmlFor: "task-priority", children: "Priority" }), _jsx("select", { id: "task-priority", value: priority, onChange: (e) => setPriority(e.target.value), children: PRIORITIES.map((p) => (_jsxs("option", { value: p, children: [p, " \u00B7 ", PRIORITY_HELP[p]] }, p))) }), _jsx("button", { className: "primary", disabled: busy || !title.trim(), children: busy ? 'Adding…' : 'Add task' })] }), !store.loaded ? (_jsx(Loading, { label: "Loading tasks", rows: 4 })) : (_jsx("div", { className: "table-wrap", children: _jsxs("table", { className: "table tasks", children: [_jsxs("colgroup", { children: [_jsx("col", { className: "col-prio" }), _jsx("col", {}), _jsx("col", { className: "col-owner" }), _jsx("col", { className: "col-status" }), _jsx("col", { className: "col-age" }), _jsx("col", { className: "col-rev" })] }), _jsx("thead", { children: _jsxs("tr", { children: [_jsx("th", { scope: "col", children: "Priority" }), _jsx("th", { scope: "col", children: "Task" }), _jsx("th", { scope: "col", children: "Owner" }), _jsx("th", { scope: "col", children: "Status" }), _jsx("th", { scope: "col", className: "num", children: "Updated" }), _jsx("th", { scope: "col", className: "num", children: "Rev" })] }) }), TASK_STATUSES.map((status) => {
                            const group = store.tasks
                                .filter((t) => t.status === status)
                                .sort((a, b) => (a.priority ?? 'P2').localeCompare(b.priority ?? 'P2') || b.updated_at.localeCompare(a.updated_at));
                            return (_jsxs("tbody", { className: 'group group-' + status, "aria-labelledby": 'group-' + status, children: [_jsx("tr", { className: "group-head", children: _jsxs("th", { scope: "colgroup", colSpan: 6, id: 'group-' + status, children: [status, " ", _jsx("span", { className: "count", children: group.length })] }) }), group.length === 0 ? (_jsx("tr", { className: "group-empty", children: _jsx("td", { colSpan: 6, children: COLUMN_EMPTY[status] }) })) : (group.map((task) => (_jsx(TaskRow, { task: task, store: store, owners: owners, conflict: conflicts[task.id], setConflict: setConflict }, task.id))))] }, status));
                        })] }) })), _jsx("p", { className: "muted small lede", children: "Every change is revision-checked. If an agent moved a task first, your change is refused and the list reloads instead of overwriting theirs." })] }));
}
/* Agents */
export function AgentsView({ store, office }) {
    const [history, setHistory] = useState(false);
    if (!store.loaded)
        return _jsx(Loading, { label: "Loading sessions" });
    if (store.agents.length === 0) {
        return (_jsxs(Empty, { title: "No sessions observed", children: ["Agents appear once their host reports in. Run ", _jsx("kbd", { children: "install.sh --global --with-hooks" }), " once: Claude Code gets the omniverse-bridge plugin, Codex and Gemini get hooks, OpenCode its plugin. Any other agent appears when it connects over MCP."] }));
    }
    const order = ['working', 'blocked', 'waiting', 'stale', 'offline'];
    const gone = store.agents.filter((a) => !inOffice(a)).length;
    const agents = store.agents
        .filter((a) => history || inOffice(a))
        .sort((a, b) => order.indexOf(a.status) - order.indexOf(b.status));
    const sources = [...new Set(store.agents.map((a) => a.source))];
    return (_jsxs("div", { className: "stack", children: [_jsx("p", { className: "muted small", children: "Status: working, waiting, blocked, offline, or stale (no recent signal). Context is the share of the model's window the host reported: at 70% save a checkpoint, at 80% hand off to a fresh session, 90% is critical." }), gone > 0 && (_jsx("p", { className: "small", children: _jsxs("button", { type: "button", className: "link", onClick: () => setHistory(!history), children: [history ? 'Hide' : 'Show', " ", gone, " ended or silent ", gone === 1 ? 'session' : 'sessions'] }) })), _jsx("div", { className: "table-wrap", children: _jsxs("table", { className: "table", children: [_jsx("thead", { children: _jsxs("tr", { children: [_jsx("th", { scope: "col", children: "Agent" }), _jsx("th", { scope: "col", children: "Status" }), _jsx("th", { scope: "col", children: "Context" }), _jsx("th", { scope: "col", children: "Room \u00B7 plan state" }), _jsx("th", { scope: "col", children: "Signal" }), _jsx("th", { scope: "col", children: "Last seen" }), _jsx("th", { scope: "col", children: "First seen" }), _jsx("th", { scope: "col", children: "Session" })] }) }), _jsxs("tbody", { children: [agents.length === 0 && (_jsx("tr", { children: _jsx("td", { colSpan: 8, className: "muted", children: "No session is reporting right now." }) })), agents.map((a) => {
                                    const p = office.placed.find((x) => x.agent === a);
                                    return (_jsxs("tr", { className: 'row-' + a.status, children: [_jsx("th", { scope: "row", children: _jsxs("span", { className: "cell-agent", children: [_jsx(AgentMark, { agent: a.agent, size: 20, unknown: a.status === 'stale' }), agentName(a)] }) }), _jsx("td", { children: _jsx("span", { className: 'pill pill-' + a.status, title: STATUS_HELP[a.status], children: a.status }) }), _jsx("td", { children: _jsx(ContextIndicator, { agent: a, now: store.now }) }), _jsx("td", { children: p ? (_jsxs(_Fragment, { children: [roomLabel(p.room), " ", _jsxs("span", { className: "muted", children: ["\u00B7 ", p.state] })] })) : (_jsx("span", { className: "muted", children: a.status === 'offline' ? 'Left the office' : a.status === 'stale' ? 'Out of the office' : 'Room full' })) }), _jsx("td", { children: sourceLabel(a.source) }), _jsx("td", { children: _jsx("time", { dateTime: a.last_seen, title: new Date(a.last_seen).toLocaleString(), children: ago(a.last_seen, store.now) }) }), _jsx("td", { children: _jsx("time", { dateTime: a.first_seen, title: new Date(a.first_seen).toLocaleString(), children: ago(a.first_seen, store.now) }) }), _jsx("td", { className: "mono muted", children: a.session_id })] }, a.agent + a.session_id));
                                })] })] }) }), _jsxs("div", { className: "legend-grid", children: [_jsxs("section", { className: "panel", children: [_jsx("h2", { children: "What each state means" }), _jsx("dl", { className: "legend", children: PLAN_STATES.map(([state, tone, help]) => (_jsxs("div", { children: [_jsxs("dt", { children: [_jsx("span", { className: 'pill pill-tone-' + tone, children: state[0].toUpperCase() + state.slice(1) }), _jsx("span", { className: "legend-count", children: office.placed.filter((p) => p.state === state).length })] }), _jsx("dd", { children: help })] }, state))) }), _jsx("p", { className: "panel-foot muted small", children: "The Status column and Events show the host status as reported (working, waiting, blocked, stale, offline); the plan state comes from it plus the agent's tasks and approvals." })] }), _jsxs("section", { className: "panel", children: [_jsx("h2", { children: "Where these signals come from" }), _jsx("dl", { className: "legend", children: sources.map((s) => (_jsxs("div", { children: [_jsx("dt", { children: sourceLabel(s) }), _jsx("dd", { children: SOURCE[s]?.how ?? 'A source this version of Mission Control does not describe.' })] }, s))) })] })] })] }));
}
/* Approvals */
export function ApprovalsView({ store }) {
    const [busy, setBusy] = useState();
    const pending = store.approvals.filter((a) => a.status === 'pending');
    const decided = store.approvals
        .filter((a) => a.status !== 'pending')
        .sort((a, b) => (b.decided_at ?? '').localeCompare(a.decided_at ?? ''));
    const [notice, setNotice] = useState();
    const decide = async (approval, decision) => {
        setBusy(approval.id);
        setNotice(undefined);
        try {
            await api.decide(approval, decision);
            await store.refresh();
        }
        catch (err) {
            // Expected outcomes, not failures: the Mac check was cancelled, or someone decided first.
            if (err instanceof ApiError && err.status === 403 && decision === 'approved') {
                setNotice('Not approved: the confirmation at this Mac was cancelled. The request is still waiting.');
            }
            else if (err instanceof ApiError && err.status === 409) {
                setNotice('This request was already decided; the list has been refreshed.');
                await store.refresh();
            }
            else
                store.report(err);
        }
        finally {
            setBusy(undefined);
        }
    };
    if (!store.loaded)
        return _jsx(Loading, { label: "Loading approval requests" });
    return (_jsxs("div", { className: "stack", children: [_jsx("p", { className: "lede", id: "approval-consequence", children: "Your answer is a record, not a command. The agent reads it and acts on its own; OmniMemo never runs the action and an approval here never authorizes a Git push. Approving opens a macOS dialog: confirm with Touch ID or your password." }), notice ? (_jsx("p", { className: "muted", role: "status", children: notice })) : null, pending.length === 0 ? (_jsxs(Empty, { title: "Nothing is waiting for you", children: ["Agents ask with ", _jsx("kbd", { children: "om approvals request \"push main to origin\" --reason \"\u2026\"" }), "; requests appear here and in the office's Approvals room."] })) : (_jsx("ul", { className: "approvals", "aria-label": "Waiting for your decision", children: pending.map((a) => (_jsxs("li", { className: "approval", children: [_jsxs("span", { className: "approval-who", children: [_jsx(AgentMark, { agent: a.requested_by, size: 36 }), _jsx("span", { children: a.requested_by })] }), _jsxs("div", { className: "approval-body", children: [_jsx("h2", { children: a.action }), a.reason ? _jsx("p", { children: a.reason }) : _jsx("p", { className: "muted", children: "No reason given." }), _jsxs("p", { className: "muted small", children: ["Asked", ' ', _jsx("time", { dateTime: a.created_at, title: new Date(a.created_at).toLocaleString(), children: ago(a.created_at, store.now) }), ' ', "\u00B7 ", _jsx("span", { className: "mono", children: a.id })] })] }), _jsxs("div", { className: "approval-actions", children: [_jsx("button", { type: "button", className: "primary", disabled: busy === a.id, "aria-describedby": "approval-consequence", onClick: () => void decide(a, 'approved'), children: "Approve" }), _jsx("button", { type: "button", disabled: busy === a.id, "aria-describedby": "approval-consequence", onClick: () => void decide(a, 'denied'), children: "Deny" })] })] }, a.id))) })), decided.length > 0 && (_jsxs("section", { className: "panel", children: [_jsx("h2", { children: "Decided" }), _jsx("ul", { className: "rows", children: decided.map((a) => (_jsxs("li", { children: [_jsx("span", { children: a.action }), _jsxs("span", { className: "muted small", children: ["asked by ", a.requested_by] }), _jsx("span", { className: 'pill pill-' + a.status, children: a.status }), _jsx("span", { className: "muted small", children: a.decided_at ? ago(a.decided_at, store.now) : '' })] }, a.id))) })] }))] }));
}
const CHECKPOINT_PARTS = [
    ['done', 'Done'],
    ['next', 'Next'],
    ['blocked', 'Blocked'],
    ['tests', 'Tests reported'],
    ['changed_files', 'Changed files'],
];
/** Checkpoints are stored as JSON; anything else is shown as plain text. */
function parseCheckpoint(summary) {
    if (!summary.trimStart().startsWith('{'))
        return undefined;
    try {
        const value = JSON.parse(summary);
        return CHECKPOINT_PARTS.some(([k]) => Array.isArray(value[k])) ? value : undefined;
    }
    catch {
        return undefined;
    }
}
function MemoryItem({ m }) {
    const checkpoint = parseCheckpoint(m.summary);
    return (_jsxs("li", { className: "panel memory", children: [_jsxs("div", { className: "memory-head", children: [_jsx("h2", { children: m.title }), checkpoint && _jsx("span", { className: "tag", children: "handoff" }), _jsx("span", { className: 'pill pill-' + m.state, title: MEMORY_HELP[m.state], children: m.state })] }), checkpoint ? (_jsx("dl", { className: "checkpoint", children: CHECKPOINT_PARTS.filter(([k]) => checkpoint[k]?.length).map(([k, label]) => (_jsxs("div", { children: [_jsx("dt", { children: label }), _jsx("dd", { children: _jsx("ul", { children: checkpoint[k].map((item, i) => (_jsx("li", { className: k === 'changed_files' ? 'mono' : undefined, children: item }, i))) }) })] }, k))) })) : (_jsx("p", { children: m.summary })), m.source_refs && m.source_refs.length > 0 && (_jsxs("p", { className: "muted small", children: ["Source evidence: ", _jsx("span", { className: "mono", children: m.source_refs.join(' · ') })] }))] }));
}
export function MemoryView({ store }) {
    const [query, setQuery] = useState('');
    const [shown, setShown] = useState('');
    const [results, setResults] = useState();
    const [searching, setSearching] = useState(false);
    const latest = useRef(0);
    const run = async (q) => {
        // A slow earlier search must not replace the results of a later one.
        const n = ++latest.current;
        setSearching(true);
        try {
            const found = await api.search(q);
            if (n !== latest.current)
                return;
            setResults(found);
            setShown(q);
        }
        catch (err) {
            if (n === latest.current)
                store.report(err);
        }
        finally {
            if (n === latest.current)
                setSearching(false);
        }
    };
    useEffect(() => {
        void run('');
        // Load once on arrival; later searches are explicit.
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);
    const search = (e) => {
        e.preventDefault();
        void run(query.trim());
    };
    return (_jsxs("div", { className: "stack", children: [_jsxs("form", { className: "toolbar", onSubmit: search, role: "search", children: [_jsx("label", { className: "sr-only", htmlFor: "memory-query", children: "Search memory" }), _jsx("input", { id: "memory-query", type: "search", value: query, maxLength: 200, placeholder: "Search decisions, facts and handoffs", onChange: (e) => setQuery(e.target.value) }), _jsx("button", { className: "primary", disabled: searching, children: searching ? 'Searching…' : 'Search' })] }), !results ? (_jsx(Loading, { label: "Loading memory", rows: 2 })) : results.length === 0 ? (shown ? (_jsx(Empty, { title: `No memory matches “${shown}”`, children: "Try a shorter word, or a file path an agent recorded." })) : (_jsxs(Empty, { title: "No memory saved yet", children: ["Agents save through MCP or with ", _jsx("kbd", { children: "om memory save" }), "; handoffs come from ", _jsx("kbd", { children: "om checkpoint" }), "."] }))) : (_jsxs(_Fragment, { children: [_jsxs("div", { className: "results-head", "aria-live": "polite", children: [_jsxs("p", { children: [_jsx("b", { children: results.length }), " ", results.length === 1 ? 'memory' : 'memories', shown ? _jsxs(_Fragment, { children: [" matching \u201C", shown, "\u201D"] }) : null] }), _jsx("p", { className: "muted small", children: Object.entries(MEMORY_HELP).map(([state, help], i) => (_jsxs("span", { children: [i > 0 && ' · ', _jsx("span", { className: "legend-word", children: state }), ": ", help] }, state))) })] }), _jsx("ul", { className: "memories", children: results.map((m) => (_jsx(MemoryItem, { m: m }, m.id))) })] }))] }));
}
/* Events */
export function EventsView({ store }) {
    const [kind, setKind] = useState('all');
    if (!store.loaded)
        return _jsx(Loading, { label: "Loading events", rows: 5 });
    if (store.events.length === 0) {
        return (_jsx(Empty, { title: "No committed events yet", children: "Every session signal, task move, approval and handoff is committed here in order, starting with the first." }));
    }
    const count = (k) => (k === 'all' ? store.events.length : store.events.filter((e) => kindOf(e.type) === k).length);
    const list = kind === 'all' ? store.events : store.events.filter((e) => kindOf(e.type) === kind);
    return (_jsxs("div", { className: "stack", children: [_jsxs("div", { className: "filters", role: "group", "aria-label": "Filter events by kind", children: [EVENT_KINDS.map((k) => (_jsxs("button", { type: "button", "aria-pressed": kind === k.id, onClick: () => setKind(k.id), children: [k.label, " ", _jsx("span", { className: "count", children: count(k.id) })] }, k.id))), _jsx("p", { className: "muted small filters-note", children: "Newest first \u00B7 the most recent committed events, revision numbered." })] }), _jsx("section", { className: "panel", "aria-label": "Events", children: list.length === 0 ? (_jsx("p", { className: "muted", children: "No events of this kind in the recent window." })) : (_jsx("ol", { className: "events", children: list.map((e) => (_jsx(EventLine, { e: e, store: store }, e.event_id))) })) })] }));
}

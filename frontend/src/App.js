import { Fragment as _Fragment, jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ApiError, api, } from './api';
import { inOffice, place } from './office';
import { Logo } from './Figure';
import { useLive } from './useLive';
import { AgentsView, ApprovalsView, EventsView, MemoryView, OfficeView, TasksView } from './views';
const VIEWS = ['office', 'tasks', 'agents', 'approvals', 'memory', 'events'];
const viewFromHash = () => {
    const name = location.hash.replace('#', '');
    return VIEWS.includes(name) ? name : 'office';
};
export function App() {
    const [view, setView] = useState(viewFromHash);
    const [health, setHealth] = useState();
    const [agents, setAgents] = useState([]);
    const [tasks, setTasks] = useState([]);
    const [approvals, setApprovals] = useState([]);
    const [events, setEvents] = useState([]);
    const [error, setError] = useState();
    const [unauthorized, setUnauthorized] = useState(false);
    const [now, setNow] = useState(Date.now());
    const [loaded, setLoaded] = useState(false);
    useEffect(() => {
        const onHash = () => setView(viewFromHash());
        window.addEventListener('hashchange', onHash);
        return () => window.removeEventListener('hashchange', onHash);
    }, []);
    const report = useCallback((e) => {
        if (e instanceof ApiError && e.status === 401)
            setUnauthorized(true);
        else
            setError(e instanceof Error ? e.message : String(e));
    }, []);
    // Events can trigger overlapping reads of one list; only the newest request may apply,
    // so a slower, older response never overwrites a newer snapshot.
    const latest = useRef({ agents: 0, tasks: 0, approvals: 0 });
    const load = useCallback((key, read, apply) => {
        const n = ++latest.current[key];
        void read().then((value) => n === latest.current[key] && apply(value), report);
    }, [report]);
    const refresh = useCallback(async () => {
        try {
            const n = { agents: ++latest.current.agents, tasks: ++latest.current.tasks, approvals: ++latest.current.approvals };
            const [h, a, t, p] = await Promise.all([api.health(), api.agents(), api.tasks(), api.approvals()]);
            setHealth(h);
            if (n.agents === latest.current.agents)
                setAgents(a);
            if (n.tasks === latest.current.tasks)
                setTasks(t);
            if (n.approvals === latest.current.approvals)
                setApprovals(p);
            setUnauthorized(false);
            const revision = Number(h.revision);
            const recent = await api.events(Math.max(0, revision - 60));
            setEvents(recent.reverse());
            setLoaded(true);
            setError(undefined);
        }
        catch (e) {
            report(e);
        }
    }, [report]);
    useEffect(() => {
        void refresh();
        // Presence ages without new events: re-read sessions slowly, and tick relative times.
        const slow = window.setInterval(() => load('agents', api.agents, setAgents), 30_000);
        const tick = window.setInterval(() => setNow(Date.now()), 15_000);
        return () => {
            window.clearInterval(slow);
            window.clearInterval(tick);
        };
    }, [refresh, load]);
    const onEvent = useCallback((event) => {
        setNow(Date.now());
        setEvents((list) => (list.some((e) => e.event_id === event.event_id) ? list : [event, ...list].slice(0, 200)));
        setHealth((h) => (h ? { ...h, revision: String(event.revision) } : h));
        if (event.type === 'task.updated')
            load('tasks', api.tasks, setTasks);
        if (event.type === 'agent.status.changed' || event.type === 'runtime.activity' || event.type === 'context.usage.updated')
            load('agents', api.agents, setAgents);
        if (event.type.startsWith('approval.'))
            load('approvals', api.approvals, setApprovals);
    }, [load]);
    const connection = useLive(health?.project_id, onEvent, refresh);
    const store = { health, agents, tasks, approvals, events, now, loaded, live: connection === 'live', report, refresh };
    const office = useMemo(() => place(agents, tasks, approvals, events, now), [agents, tasks, approvals, events, now]);
    const pending = approvals.filter((a) => a.status === 'pending').length;
    const present = agents.filter(inOffice);
    if (unauthorized) {
        return (_jsxs("main", { className: "signin", children: [_jsx(Logo, { size: 48 }), _jsx("h1", { children: "OmniMemo is locked" }), _jsxs("p", { children: ["This browser isn't signed in, or its sign-in link was already used. Run ", _jsx("kbd", { children: "om office" }), " in your project's terminal: it opens Mission Control with a fresh one-time sign-in link."] })] }));
    }
    const nav = [
        { id: 'office', label: 'Office', title: 'Agent Office' },
        { id: 'tasks', label: 'Tasks', title: 'Tasks', count: tasks.filter((t) => t.status !== 'done').length, unit: 'open' },
        { id: 'agents', label: 'Agents', title: 'Agents', count: present.length, unit: 'present' },
        { id: 'approvals', label: 'Approvals', title: 'Approvals', count: pending, unit: 'waiting for you', attention: pending > 0 },
        { id: 'memory', label: 'Memory', title: 'Memory' },
        { id: 'events', label: 'Events', title: 'Events' },
    ];
    const liveLabel = { live: 'Live', connecting: 'Connecting', reconnecting: 'Reconnecting', offline: 'Offline' }[connection];
    return (_jsxs("div", { className: "shell", children: [_jsx("a", { className: "skip", href: "#work", children: "Skip to content" }), _jsxs("nav", { className: "rail", "aria-label": "Mission Control", children: [_jsxs("div", { className: "brand", children: [_jsx(Logo, { size: 30 }), _jsxs("div", { children: [_jsx("div", { className: "brand-name", children: "OmniMemo" }), _jsx("div", { className: "brand-sub", children: "Mission Control" })] })] }), _jsx("ul", { children: nav.map((item) => (_jsx("li", { children: _jsxs("a", { href: '#' + item.id, "aria-current": view === item.id ? 'page' : undefined, children: [item.label, item.count ? (_jsxs("span", { className: 'count' + (item.attention ? ' attention' : ''), children: [item.count, _jsxs("span", { className: "sr-only", children: [" ", item.unit] })] })) : null] }) }, item.id))) }), _jsxs("dl", { className: "rail-meta", children: [_jsx("dt", { children: "Project" }), _jsx("dd", { className: "mono", title: health?.project_id, children: health ? health.project_name ?? health.project_id.slice(0, 12) : '…' }), _jsx("dt", { children: "Events recorded" }), _jsx("dd", { className: "mono", children: health?.revision ?? '…' }), _jsx("dt", { children: "Live" }), _jsx("dd", { className: 'live live-' + connection, children: connection === 'live' ? 'Connected' : liveLabel })] })] }), _jsxs("main", { id: "work", className: "work", children: [_jsxs("header", { className: "topbar", children: [_jsx("h1", { children: nav.find((n) => n.id === view)?.title }), _jsxs("p", { className: "summary", children: [_jsxs("span", { className: 'live-chip live-' + connection, children: [_jsx("span", { className: "live-led", "aria-hidden": "true" }), liveLabel] }), loaded ? (_jsxs(_Fragment, { children: [present.length, " ", present.length === 1 ? 'session' : 'sessions', " present"] })) : ('Reading the project…')] }), _jsxs("div", { className: "topbar-right", children: [['todo', 'doing', 'review'].map((s) => (_jsxs("a", { className: 'stat stat-' + s, href: "#tasks", children: [s, " ", _jsx("b", { children: loaded ? tasks.filter((t) => t.status === s).length : '…' })] }, s))), pending > 0 && (_jsxs("a", { className: "needs-you", href: "#approvals", children: ["Needs you \u00B7 ", pending] }))] })] }), error && (_jsxs("div", { className: "notice", role: "alert", children: [_jsxs("p", { children: [_jsx("b", { children: "Something went wrong." }), " ", error] }), _jsxs("div", { className: "notice-actions", children: [_jsx("button", { type: "button", className: "link", onClick: () => void refresh(), children: "Reload data" }), _jsx("button", { type: "button", className: "link", onClick: () => setError(undefined), children: "Dismiss" })] })] })), view === 'office' && _jsx(OfficeView, { store: store, office: office }), view === 'tasks' && _jsx(TasksView, { store: store }), view === 'agents' && _jsx(AgentsView, { store: store, office: office }), view === 'approvals' && _jsx(ApprovalsView, { store: store }), view === 'memory' && _jsx(MemoryView, { store: store }), view === 'events' && _jsx(EventsView, { store: store })] })] }));
}

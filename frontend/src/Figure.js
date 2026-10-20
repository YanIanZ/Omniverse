import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
const PROVIDERS = {
    claude: { body: '#d97757', head: '#f3c0a2', shape: 'round' },
    codex: { body: '#e8eef2', head: '#3fb8b0', shape: 'square' },
    opencode: { body: '#4caf63', head: '#d6f0dc', shape: 'hex' },
    gemini: { body: '#8b9cf7', head: '#d5dbff', shape: 'drop' },
    cursor: { body: '#c4a95a', head: '#f1e4bb', shape: 'tri' },
};
const FALLBACK = ['#c98b4f', '#b48ad0', '#6fa0d8', '#d27a7a', '#6bbfae'];
export function agentLook(agent) {
    const known = PROVIDERS[agent];
    if (known)
        return known;
    let h = 0;
    for (const ch of agent)
        h = (h * 31 + ch.charCodeAt(0)) >>> 0;
    return { body: FALLBACK[h % FALLBACK.length], head: '#e9eef6', shape: 'round' };
}
const SHOULDERS = 'M-10 0v-4a10 9 0 0 1 20 0v4z';
/** Head outline centred at (0, -18), about 12 units across. */
function headPath(shape) {
    switch (shape) {
        case 'square':
            return 'M-5.5 -23.5h11v11h-11z';
        case 'hex':
            return 'M0 -24.5l5.8 3.3v6.5L0 -11.5l-5.8-3.3v-6.5z';
        case 'drop':
            return 'M0 -26c3 3.5 6 5.5 6 8.5a6 6 0 0 1-12 0c0-3 3-5 6-8.5z';
        case 'tri':
            return 'M0 -25l6.5 12h-13z';
        default:
            return 'M0 -24a6 6 0 1 1 0 12a6 6 0 1 1 0-12z';
    }
}
/** The figure itself, centred on x=0 with its feet at y=0; 24 plan units tall. */
export function FigureGlyph({ agent, unknown = false }) {
    const { body, head, shape } = agentLook(agent);
    if (unknown) {
        // Hatched fill, outline in the provider's colour: unknown, but still recognisably this provider.
        return (_jsxs("g", { className: "figure figure-unknown", style: { stroke: body }, children: [_jsx("path", { d: SHOULDERS, fill: "url(#plan-hatch)" }), _jsx("path", { d: headPath(shape), fill: "url(#plan-hatch)" })] }));
    }
    return (_jsxs("g", { className: "figure", children: [_jsx("path", { d: SHOULDERS, fill: body }), _jsx("path", { d: headPath(shape), fill: head })] }));
}
/** A standalone agent mark for tables, cards and lists. Decorative: the agent's name is always printed beside it. */
export function AgentMark({ agent, size = 20, unknown = false, ...rest }) {
    const { body, head, shape } = agentLook(agent);
    return (_jsxs("svg", { className: 'agent-mark' + (unknown ? ' is-unknown' : ''), width: size, height: size, viewBox: "-12 -27 24 28", "aria-hidden": "true", focusable: "false", ...rest, children: [_jsx("path", { d: SHOULDERS, fill: unknown ? 'none' : body, stroke: unknown ? body : 'none' }), _jsx("path", { d: headPath(shape), fill: unknown ? 'none' : head, stroke: unknown ? body : 'none' })] }));
}
/** OmniMemo mark: a drawn room with a door swing and one occupant. */
export function Logo({ size = 32 }) {
    return (_jsxs("svg", { className: "logo", width: size, height: size, viewBox: "0 0 32 32", "aria-hidden": "true", focusable: "false", children: [_jsx("path", { d: "M3 3h26v26H17M11 29H3V3", fill: "none", stroke: "currentColor", strokeWidth: "2.5" }), _jsx("path", { d: "M11 29V21a8 8 0 0 1 8 8", fill: "none", stroke: "currentColor", strokeWidth: "1", opacity: ".6" }), _jsx("circle", { cx: "16", cy: "12.5", r: "3.4", fill: "currentColor" }), _jsx("path", { d: "M10 21v-1.5a6 5 0 0 1 12 0V21z", fill: "currentColor" })] }));
}

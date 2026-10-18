// Omniverse Claude Mod (proof-of-concept, read-only)
// Reads the authenticated local Vapor GET /api/runtime/sessions (`om serve`).
// Never sends prompts or executes remote tasks. Validate with `claude plugin validate`.
const ENDPOINT = 'http://127.0.0.1:8787/api/runtime/sessions';
let agents = [];
let report = 'No bridge connection yet';

function safe(value, maximum = 120) {
  return String(value ?? '').replace(/[\x00-\x1f\x7f]/g, ' ').slice(0, maximum);
}
function formatted(a) {
  const name = safe(a.display_slug ?? 'agent-model-unknown', 65);
  const task = safe(a.task?.title ?? 'No active task', 100);
  const status = safe(a.status ?? 'unknown', 20).toUpperCase();
  const p = a.progress ?? {};
  let bar = '░'.repeat(14) + ' progress unknown';
  if (p.kind === 'determinate' && Number.isFinite(p.percent) && p.percent >= 0 && p.percent <= 100) {
    const percent = Math.round(p.percent);
    const filled = Math.round(percent * 14 / 100);
    bar = '█'.repeat(filled) + '░'.repeat(14 - filled) + ' ' + percent + '%';
    if (Number.isInteger(p.completed) && Number.isInteger(p.total) && p.total > 0) {
      bar += ' · ' + p.completed + '/' + p.total;
    }
  }
  return [name + ' · ' + status, task, bar];
}
async function refresh($) {
  try {
    const token = await $.env.get('OMNIMEMO_BRIDGE_TOKEN');
    if (!token) { agents = []; report = 'Set OMNIMEMO_BRIDGE_TOKEN; no request sent'; return; }
    const response = await $.http.fetch(ENDPOINT, {
      headers: { 'authorization': 'Bearer ' + token, 'accept': 'application/json' },
    });
    if (!response.ok) { agents = []; report = 'Bridge HTTP ' + response.status; return; }
    const body = JSON.parse(response.text);
    if (!Array.isArray(body.agents)) throw Error('Malformed bridge response');
    agents = body.agents.slice(0, 32);
    report = agents.length ? agents.length + ' connected agent record(s)' : 'No agents registered';
  } catch (_) { agents = []; report = 'Bridge unavailable'; }
}
export function register(on) {
  on('session.start', async ($, e, next) => {
    // Register only one UI command and poll infrequently; no model calls.
    await $.command.register({ name: 'om-agents', description: 'Show live Omniverse agent cards', immediate: true });
    $.clock.after(300, async () => { await refresh($); $.ui.invalidate('ui.render'); });
    $.clock.every(15000, async () => { await refresh($); $.ui.invalidate('ui.render'); });
    return next(e);
  });
  on('command.run', { command: 'om-agents' }, async ($, e) => {
    await refresh($);
    await $.ui.open({ id: 'omniverse-agent-cards', title: 'Omniverse · Agents', focus: true });
    return {};
  });
  on('ui.render', { component: 'Pane' }, async ($, e, next) => {
    if (e.requestId !== 'omniverse-agent-cards') return next(e);
    const { Box, Text } = $.ui.resolve(e);
    const children = [Text({ children: [report] })];
    for (const a of agents) {
      const lines = formatted(a);
      for (const line of lines) children.push(Text({ children: [line] }));
      children.push(Text({ children: [' '] }));
    }
    return Box({ flexDirection: 'column', children });
  });
}

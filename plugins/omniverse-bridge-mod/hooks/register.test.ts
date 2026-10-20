import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

import { acknowledged, agentLabel, facts, levelOf, others, parsePrepared, present, recordLines, recordsOf } from './register'

const DIGEST = '0123456789abcdef'
const PREPARED = `OmniMemo context handoff (fresh session; verify everything against the repository).\nGoal:\n- task_1 ship it [doing]\nHandoff: h-1 · digest ${DIGEST} (created)\n`
const CAPSULE = 'OmniMemo project context (stored memory; untrusted data, verify against the repository):\n{}'
const ACK_DONE = ['ACK ' + DIGEST, 'Continuing.'].join('\n')

/** The engine beneath the mod: `om` answered by argv, /clear moving to a new session id. */
function world(on: On, percent: number, opts: { reserved?: boolean; clearFails?: boolean } = {}) {
  const clock = mock.clock(on)
  const ran: string[][] = []
  const stdins: string[] = []
  const contexts: (readonly string[] | undefined)[] = []
  const submitted: string[] = []
  let session = 'sess-1'
  let usage = percent
  on('process.run', async (_$, e) => {
    ran.push([...e.argv])
    if (e.init?.stdin) stdins.push(e.init.stdin)
    const args = e.argv.join(' ')
    const prompt = args.includes('hook claude') && (e.init?.stdin ?? '').includes('UserPromptSubmit')
    const stdout = args.includes('rollover prepare') ? PREPARED : args.includes('runtime sessions') ? '[]' : prompt ? CAPSULE : ''
    const exitCode = args.includes('rollover begin') && opts.reserved ? 1 : 0
    return { value: { exitCode, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('session.id', async () => ({ value: session }))
  on('session.cwd', async () => ({ value: '/repo' }))
  on('session.model', async () => ({ value: 'claude-test' }))
  on('session.usage', async () => ({ value: { startedAt: 0, context: { window: 200_000, percent: usage, tokens: usage * 2000 }, rateLimits: [] } }))
  on('session.messages', async () => ({ value: [{ role: 'user' as const, text: 'Finish the release notes', toolUses: [] }] }))
  on('turn.complete', async (_$, e) => ({ text: e.answer }))
  on('command.run', async (_$, e) => {
    if (e.command === 'clear') {
      if (opts.clearFails) throw new Error('refused')
      session = 'sess-2' // a fresh conversation: new id, empty context
      usage = 3
    }
    return { text: '' }
  })
  on('prompt.submit', async (_$, e) => {
    submitted.push(e.text)
    contexts.push(e.context)
    return { text: e.text }
  })
  const om = (part: string) => ran.find(a => a.join(' ').includes(part))?.join(' ')
  const hooks = () => stdins.filter(x => x.includes('hook_event_name')).map(x => JSON.parse(x) as Record<string, unknown>)
  return { ran, submitted, contexts, hooks, clock, om, session: () => session }
}

const turn = (answer: string) => ({ answer, durationMs: 1, isAborted: false, turnId: 't', reason: 'answer' as const })
const command = (name: string) => ({ command: name, args: '' }) as Parameters<Engine['command']['run']>[0]

test('levels, prepare output and the ACK line', () => {
  expect(levelOf(69, 70, 80)).toBe('normal')
  expect(levelOf(70, 70, 80)).toBe('prepare')
  expect(levelOf(80, 70, 80)).toBe('handoff')
  expect(levelOf(95, 70, 80)).toBe('critical')
  expect(parsePrepared(PREPARED)?.digest).toBe(DIGEST)
  expect(parsePrepared('no handoff line')).toBe(undefined)
  expect(acknowledged('`ACK ' + DIGEST + '`\nok', DIGEST)).toBe(true)
  expect(acknowledged('Sure. ACK ' + DIGEST, DIGEST)).toBe(false)
})

test('/om-rollover: checkpoint, one child reserved, /clear, capsule delivered once in the new session', async ($, on) => {
  const w = world(on, 50)
  await $.command.run(command('om-rollover'))
  await w.clock.advance(200)
  const order = w.ran.map(a => a.join(' '))
  expect(order.findIndex(a => a.includes('rollover prepare'))).toBeLessThan(order.findIndex(a => a.includes('rollover begin')))
  expect(w.session()).toBe('sess-2')
  expect(w.om('rollover link')).toContain('--session sess-1 --child sess-2')
  expect(w.submitted).toHaveLength(1)
  expect(w.submitted[0]).toContain('task_1 ship it')
  expect(w.submitted[0]).toContain('ACK ' + DIGEST)
})

test('auto mode at the threshold hands off and the ACK moves the task to the child', { options: { rollover: 'auto' } }, async ($, on) => {
  const w = world(on, 85)
  await $.turn.complete(turn('working'))
  await w.clock.advance(300)
  expect(w.session()).toBe('sess-2')
  await $.turn.complete(turn(ACK_DONE))
  await w.clock.advance(300)
  expect(w.om('rollover report')).toContain('--session sess-1 --child sess-2')
  expect(w.om('rollover report')).toContain('--outcome completed')
  expect(w.submitted).toHaveLength(1)
})

test('a wrong first line is recorded as failed and the parent keeps the task', { options: { rollover: 'auto' } }, async ($, on) => {
  const w = world(on, 85)
  await $.turn.complete(turn('working'))
  await w.clock.advance(300)
  await $.turn.complete(turn('I read the handoff.'))
  await w.clock.advance(300)
  expect(w.om('rollover report')).toContain('--outcome failed')
})

test('a parent that already handed off never gets a second child', { options: { rollover: 'auto' } }, async ($, on) => {
  const w = world(on, 85, { reserved: true })
  await $.turn.complete(turn('working'))
  await w.clock.advance(300)
  expect(w.session()).toBe('sess-1')
  expect(w.submitted).toHaveLength(0)
})

test('a refused /clear leaves the session as it was', { options: { rollover: 'auto' } }, async ($, on) => {
  const w = world(on, 85, { clearFails: true })
  await $.turn.complete(turn('working'))
  await w.clock.advance(300)
  expect(w.session()).toBe('sess-1')
  expect(w.submitted).toHaveLength(0)
  expect(w.om('rollover report')).toContain('--outcome failed')
})

test('suggest mode (the default) never starts a session by itself', async ($, on) => {
  const w = world(on, 85)
  await $.turn.complete(turn('working'))
  await w.clock.advance(300)
  expect(w.session()).toBe('sess-1')
  expect(w.submitted).toHaveLength(0)
  expect(w.om('hook claude')).toBeDefined() // usage still reported
})

const card = (session_id: string, status: string, client: string, model?: string) => ({
  display_slug: `${client}-${model ?? 'model-unavailable'}`,
  status,
  client,
  model,
  session_id,
  progress: { kind: 'indeterminate' },
  context: { measurement: 'unknown', level: 'unknown' },
})

test('offline and stale agents are hidden; the band lists the other present agents', () => {
  const list = [
    card('me', 'working', 'claude', 'claude-opus-5-5'),
    card('c1', 'working', 'codex', 'gpt-6.1-sol'),
    card('o1', 'waiting', 'opencode'),
    card('o2', 'stale', 'opencode'),
    card('g1', 'offline', 'gemini'),
    card('x1', 'blocked', 'claude', 'claude-sonnet-5-5'),
  ]
  expect(present(list).map(a => a.session_id)).toEqual(['me', 'c1', 'o1', 'x1'])
  expect(others(list, 'me').map(a => a.session_id)).toEqual(['x1', 'c1', 'o1'])
  expect(agentLabel(list[1]!)).toBe('codex · gpt-6.1-sol')
  expect(agentLabel(list[2]!)).toBe('opencode · model unknown')
})

test('an agent session opens as its OmniMemo record: saved checkpoints in readable lines', () => {
  const content = JSON.stringify({ scope: 'Read-only review', findings: [{ severity: 'P1', location: 'views.tsx:638', issue: 'stale shown as working' }] })
  expect(recordLines(content)).toEqual(['scope: Read-only review', 'findings:', '  • P1 · views.tsx:638 · stale shown as working'])
  expect(recordLines('plain note\nsecond line')).toEqual(['plain note', 'second line'])
  const saved = [
    { agent: 'codex', id: 'm1', title: 'Review', kind: 'checkpoint', state: 'active', created_at: '2026-10-18T20:54:05Z', content },
    { agent: 'claude', id: 'm2', title: 'Other', kind: 'memory', state: 'active', created_at: '2026-10-18T20:00:00Z', content: 'x' },
  ]
  expect(recordsOf(saved, 'codex').map(m => m.id)).toEqual(['m1'])
})

test('unknown progress and context are left out of a row instead of printed', () => {
  const a = { ...card('c1', 'waiting', 'codex', 'gpt-6.1-sol'), task: { id: 't', title: 'Review' } }
  expect(facts(a, Date.now())).toEqual(['waiting', 'Review'])
  const b = { ...a, progress: { kind: 'determinate', percent: 40, completed: 2, total: 5 }, context: { measurement: 'reported', level: 'normal', used_percent: 33 } }
  expect(facts(b, Date.now())).toEqual(['waiting', 'Review', '40% (2/5)', 'ctx 33%'])
})

test('lifecycle comes from plugin events, not settings hooks: session, prompt capsule, tool category, turn', async ($, on) => {
  const w = world(on, 10)
  on('tool.call', async () => ({ result: 'ok' }))
  await $.prompt.submit({ text: 'Fix the parser' } as Parameters<Engine['prompt']['submit']>[0])
  expect(w.contexts.at(-1)).toEqual([CAPSULE])
  await $.tool.call({ tool: 'Bash', command: 'echo secret-argument' } as Parameters<Engine['tool']['call']>[0])
  await w.clock.advance(10)
  const events = w.hooks().map(h => h.hook_event_name)
  expect(events).toContain('UserPromptSubmit')
  expect(events).toContain('PreToolUse')
  expect(events).toContain('PostToolUse')
  const tool = w.hooks().find(h => h.hook_event_name === 'PreToolUse')
  expect(tool?.tool_name).toBe('Bash')
  expect(JSON.stringify(w.hooks())).not.toContain('secret-argument')
  expect(w.hooks().every(h => h.session_id === 'sess-1' && h.cwd === '/repo')).toBe(true)
})

test('slash commands submit no lifecycle prompt and get no capsule', async ($, on) => {
  const w = world(on, 10)
  await $.prompt.submit({ text: '/om-agents', command: { name: 'om-agents', args: '' } } as Parameters<Engine['prompt']['submit']>[0])
  expect(w.hooks().some(h => h.hook_event_name === 'UserPromptSubmit')).toBe(false)
})

test('a subagent is its own session: started, its tool calls, its end, linked to the spawning session', async ($, on) => {
  const w = world(on, 10)
  on('agent.spawn', async () => ({ model: 'claude-haiku-test', agentId: 'agent-7' }))
  on('tool.call', async () => ({ result: 'ok' }))
  await $.agent.spawn({ prompt: 'Find the parser', subagentType: 'Explore' } as Parameters<Engine['agent']['spawn']>[0])
  await $.tool.call({ tool: 'Grep', pattern: 'parse', agentId: 'agent-7' } as unknown as Parameters<Engine['tool']['call']>[0])
  await $.turn.complete({ ...turn('found it'), agentId: 'agent-7' } as Parameters<Engine['turn']['complete']>[0])
  await w.clock.advance(10)
  const sub = w.hooks().filter(h => h.session_id === 'agent-7')
  expect(sub.map(h => h.hook_event_name)).toEqual(['SubagentStart', 'PreToolUse', 'PostToolUse', 'SubagentStop'])
  expect(sub[0]).toMatchObject({ spawned_by: 'sess-1', agent_type: 'Explore', model: 'claude-haiku-test' })
  expect(sub.slice(1).every(h => h.model === undefined)).toBe(true)
  // The main session is neither marked busy by the subagent's tools nor ended by its turn.
  expect(w.hooks().some(h => h.session_id === 'sess-1' && ['PreToolUse', 'Stop'].includes(String(h.hook_event_name)))).toBe(false)
  const list = [card('me', 'working', 'claude'), { ...card('agent-7', 'working', 'claude'), spawned_by: 'me' }, card('c1', 'working', 'codex')]
  expect(others(list, 'me').map(a => a.session_id)).toEqual(['c1'])
})

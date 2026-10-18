import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

import { acknowledged, levelOf, parsePrepared } from './register'

const DIGEST = '0123456789abcdef'
const PREPARED = `OmniMemo context handoff (fresh session; verify everything against the repository).\nGoal:\n- task_1 ship it [doing]\nHandoff: h-1 · digest ${DIGEST} (created)\n`
const ACK_DONE = ['ACK ' + DIGEST, 'Continuing.'].join('\n')

/** The engine beneath the mod: `om` answered by argv, /clear moving to a new session id. */
function world(on: On, percent: number, opts: { reserved?: boolean; clearFails?: boolean } = {}) {
  const clock = mock.clock(on)
  const ran: string[][] = []
  const submitted: string[] = []
  let session = 'sess-1'
  let usage = percent
  on('process.run', async (_$, e) => {
    ran.push([...e.argv])
    const args = e.argv.join(' ')
    const stdout = args.includes('rollover prepare') ? PREPARED : args.includes('runtime sessions') ? '[]' : ''
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
    return { text: e.text }
  })
  const om = (part: string) => ran.find(a => a.join(' ').includes(part))?.join(' ')
  return { ran, submitted, clock, om, session: () => session }
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

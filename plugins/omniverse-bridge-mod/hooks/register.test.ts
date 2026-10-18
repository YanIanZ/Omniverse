import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On } from 'claude-code'

import { acknowledged, levelOf, parsePrepared } from './register'

const DIGEST = '0123456789abcdef'
const PREPARED = `OmniMemo context handoff (fresh session; verify everything against the repository).\nGoal:\n- task_1 ship it [doing]\nHandoff: h-1 · digest ${DIGEST} (created)\n`
const ACK_DONE = ['ACK ' + DIGEST, 'Continuing.'].join('\n')

/** The engine beneath the mod: `om` answered by argv, a session at the given context use. */
function world(on: On, percent: number) {
  const clock = mock.clock(on)
  const ran: string[][] = []
  const submitted: string[] = []
  let coreCompacted = 0
  on('process.run', async (_$, e) => {
    ran.push([...e.argv])
    const args = e.argv.join(' ')
    const stdout = args.includes('rollover prepare') ? PREPARED : args.includes('runtime sessions') ? '[]' : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('session.id', async () => ({ value: 'sess-1' }))
  on('session.cwd', async () => ({ value: '/repo' }))
  on('session.model', async () => ({ value: 'claude-test' }))
  on('session.usage', async () => ({ value: { startedAt: 0, context: { window: 200_000, percent, tokens: percent * 2000 }, rateLimits: [] } }))
  on('session.messages', async () => ({ value: [{ role: 'user' as const, text: 'Finish the release notes', toolUses: [] }] }))
  // Turns and commands end beneath the mod, as the engine would end them.
  on('turn.complete', async (_$, e) => ({ text: e.answer }))
  // The engine's /compact waits here until the test raises the compaction it would raise.
  let release = () => {}
  let asked = false
  on('command.run', async (_$, e) => {
    if (e.command === 'compact') {
      asked = true
      await new Promise<void>(resolve => (release = resolve))
    }
    return { text: '' }
  })
  on('session.compact', async () => {
    coreCompacted++
    return { messages: [{ role: 'user' as const, text: 'summary', toolUses: [] }] }
  })
  on('prompt.submit', async (_$, e) => {
    submitted.push(e.text)
    return { text: e.text }
  })
  /** Plays the engine's /compact once the mod asked for it: the compaction through the plugins. */
  async function compact($: Engine) {
    await clock.advance(200)
    expect(asked).toBe(true)
    await $.session.compact({ trigger: 'manual', instructions: 'omnimemo-rollover', messages: [] })
    release()
    await clock.settle()
  }
  return { ran, submitted, clock, compact, core: () => coreCompacted }
}

const turn = (answer: string) => ({ answer, durationMs: 1, isAborted: false, turnId: 't', reason: 'answer' as const })

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

test('/om-rollover saves first, answers the compaction with the capsule, asks for the ACK once', async ($, on) => {
  const w = world(on, 50)
  await $.command.run({ command: 'om-rollover', args: '' } as Parameters<Engine['command']['run']>[0])
  await w.compact($)
  expect(w.ran.find(a => a.includes('prepare'))?.join(' ')).toContain('rollover prepare --session sess-1')
  expect(w.core()).toBe(0) // the mod's capsule stood in for the engine's summary
  expect(w.submitted).toHaveLength(1)
  expect(w.submitted[0]).toContain('ACK ' + DIGEST)
})

test('auto mode hands off once at the threshold and records the acknowledgement', { options: { rollover: 'auto' } }, async ($, on) => {
  const w = world(on, 85)
  await $.turn.complete(turn('working'))
  await w.compact($)
  expect(w.ran.some(a => a.join(' ').includes('rollover prepare'))).toBe(true)
  expect(w.submitted).toHaveLength(1)
  await $.turn.complete(turn(ACK_DONE))
  await w.clock.advance(300)
  const report = w.ran.find(a => a.includes('report'))
  expect(report?.join(' ')).toContain('--outcome completed')
  expect(w.submitted).toHaveLength(1) // same level again: no second rollover
})

test('a wrong first line is recorded as failed', { options: { rollover: 'auto' } }, async ($, on) => {
  const w = world(on, 85)
  await $.turn.complete(turn('working'))
  await w.compact($)
  await $.turn.complete(turn('I read the handoff.'))
  await w.clock.advance(300)
  expect(w.ran.find(a => a.includes('report'))?.join(' ')).toContain('--outcome failed')
})

test('suggest mode (the default) never compacts by itself', async ($, on) => {
  const w = world(on, 85)
  await $.turn.complete(turn('working'))
  await w.clock.advance(300)
  expect(w.submitted).toHaveLength(0)
  expect(w.ran.some(a => a.includes('report'))).toBe(false)
  expect(w.ran.some(a => a.join(' ').includes('hook claude'))).toBe(true) // usage still reported
})

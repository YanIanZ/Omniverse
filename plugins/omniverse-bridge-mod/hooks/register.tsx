// Omniverse bridge mod: OmniMemo agent cards, reported context usage and opt-in rollover.
// Everything goes through the local `om` CLI (no server, no token). Telemetry is the host's
// own numbers; prompts and tool arguments are never sent. See docs/RUNTIME_EVENTS.md.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { AgentCard } from '../types'

const PANE = 'omniverse-agent-cards'
const agents = atom({ plugin: 'omniverse-bridge', key: 'agents' } as const, [] as AgentCard[])
const report = atom({ plugin: 'omniverse-bridge', key: 'report' } as const, 'No bridge reading yet')

/** A handoff in flight: compacting (our compaction answer pending), then awaiting the ACK. */
type Pending = { session: string; digest: string; capsule: string; lastRequest?: string; phase: 'compacting' | 'ack'; answered?: boolean }

/** The `/compact` instruction that marks the compaction this mod answers with the capsule. */
const MARKER = 'omnimemo-rollover'

// Options are read in register on each load; the rest starts over on a reload.
const config = { om: 'om', mode: 'suggest', rolloverAt: 80, prepareAt: 70 }
let pending: Pending | undefined
let lastLevel = 'unknown'
const rollovers: number[] = []

export function levelOf(percent: number, prepareAt: number, rolloverAt: number) {
  return percent >= 90 ? 'critical' : percent >= rolloverAt ? 'handoff' : percent >= prepareAt ? 'prepare' : 'normal'
}

/** Parses `om rollover prepare` output: the capsule, then `Handoff: <id> · digest <16 hex> (...)`. */
export function parsePrepared(stdout: string): { capsule: string; digest: string } | undefined {
  const lines = stdout.trimEnd().split('\n')
  const digest = lines.at(-1)?.match(/digest ([0-9a-f]{16})/)?.[1]
  return digest ? { capsule: lines.slice(0, -1).join('\n'), digest } : undefined
}

/** True when the reply's first line is exactly the acknowledgement token. */
export function acknowledged(answer: string, digest: string) {
  const first = answer.trimStart().split('\n')[0]?.trim().replace(/^`+|`+$/g, '')
  return first === 'ACK ' + digest
}

function run($: EngineInterface, args: string[], stdin?: string) {
  return $.process.run([config.om, ...args], { stdin, timeoutMs: 30_000 })
}

async function refresh($: EngineInterface, context?: number) {
  const ctx = context === undefined ? '' : ` · ctx ${Math.round(context)}%`
  try {
    const r = await run($, ['runtime', 'sessions'])
    if (r.exitCode !== 0) throw new Error('om exited ' + r.exitCode)
    const list = (JSON.parse(r.stdout) as AgentCard[]).slice(0, 32)
    await update($, agents, () => list)
    const live = list.filter(a => a.status !== 'offline')
    const count = (s: string) => live.filter(a => a.status === s).length
    await update($, report, () => (live.length ? `${live.length} agent(s) present` : 'No agents present'))
    $.ui.status(`OmniMemo · ${live.length} agents · ${count('working')} working · ${count('blocked')} blocked${ctx}`)
  } catch {
    await update($, agents, () => [])
    await update($, report, () => 'Bridge unavailable')
    $.ui.status('OmniMemo unavailable' + ctx)
  }
}

/** Checkpoint first, then the compaction answered with the capsule alone, then one ACK prompt. */
async function rollOver($: EngineInterface, session: string, why: string) {
  if (pending) return 'A rollover is already in progress.'
  const prepared = await run($, ['--agent', 'claude', 'rollover', 'prepare', '--session', session, '--provider', 'claude'])
  const parsed = prepared.exitCode === 0 ? parsePrepared(prepared.stdout) : undefined
  if (!parsed) return 'Rollover not started: om rollover prepare failed; nothing changed.'
  const lastUser = (await $.session.messages()).filter(m => m.role === 'user' && m.text.trim()).at(-1)
  pending = { session, ...parsed, lastRequest: lastUser?.text.slice(0, 1200), phase: 'compacting' }
  // The engine's own /compact raises the compaction, so this mod's session.compact hook answers it
  // (a plugin's direct $.session.compact passes over that plugin's own hook).
  await $.command.run({ command: 'compact', args: MARKER }).catch(() => undefined)
  if (!pending?.answered) {
    await run($, ['rollover', 'report', '--session', session, '--digest', parsed.digest, '--outcome', 'failed', '--reason', 'compaction not answered with the capsule'])
    pending = undefined
    return 'Rollover not applied: the compaction was not answered with the capsule. The checkpoint is saved.'
  }
  pending = { ...pending, phase: 'ack' }
  rollovers.push(Date.now())
  void $.prompt.submit({
    text: `OmniMemo rollover (${why}). First line of your reply must be exactly \`ACK ${parsed.digest}\`; then continue the work from the handoff above.`,
  })
  return `Context replaced by the verified capsule (digest ${parsed.digest}); waiting for the acknowledgement.`
}

/** After a main turn: settle an ACK, report usage, then prepare or hand off on a rising level. */
async function afterTurn($: EngineInterface, answer: string) {
  const session = await $.session.id()
  if (pending?.phase === 'ack' && pending.session === session) {
    const ok = acknowledged(answer, pending.digest)
    await run($, ['rollover', 'report', '--session', session, '--digest', pending.digest, '--outcome', ok ? 'completed' : 'failed', '--reason', ok ? 'acknowledged' : 'first line was not the ACK'])
    $.ui.toast(ok ? 'OmniMemo rollover acknowledged.' : 'OmniMemo rollover not acknowledged; the checkpoint is in OmniMemo for a manual handoff.')
    pending = undefined
  }
  const { context } = await $.session.usage()
  const percent = context.percent
  if (percent !== undefined) {
    await run($, ['hook', 'claude'], JSON.stringify({
      hook_event_name: 'context.usage', session_id: session, cwd: await $.session.cwd(),
      model: await $.session.model(), context_window: { used_percentage: percent, context_window_size: context.window },
    }))
  }
  await refresh($, percent)
  if (percent === undefined || config.mode === 'off' || pending) return
  const level = levelOf(percent, config.prepareAt, config.rolloverAt)
  const rising = level !== lastLevel
  lastLevel = level
  if (!rising) return
  if (level === 'prepare') {
    await run($, ['--agent', 'claude', 'rollover', 'prepare', '--session', session, '--provider', 'claude'])
    $.ui.toast(`Context ${Math.round(percent)}%: OmniMemo checkpoint saved.`)
  } else if (level === 'handoff' || level === 'critical') {
    const recent = rollovers.filter(t => Date.now() - t < 3_600_000)
    if (config.mode === 'auto' && recent.length < 3) {
      $.ui.toast(await rollOver($, session, `context ${Math.round(percent)}%`))
    } else {
      $.ui.toast(`Context ${Math.round(percent)}%: run /om-rollover for a fresh context from the OmniMemo capsule.`)
    }
  }
}

export const register: Register = (on, options) => {
  config.om = String(options.omPath || 'om')
  config.mode = String(options.rollover || 'suggest')
  config.rolloverAt = Number(options.rolloverAt ?? 80)
  config.prepareAt = Math.min(Number(options.prepareAt ?? 70), config.rolloverAt)

  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'om-agents', description: 'Show live OmniMemo agent cards' })
    await $.command.register({ name: 'om-rollover', description: 'Hand off to a fresh context from a verified OmniMemo capsule' })
    $.clock.after(300, () => void refresh($))
    $.clock.every(15_000, () => void refresh($))
    return next(e)
  })

  on('command.run', { command: 'om-agents' }, async $ => {
    await refresh($)
    await $.ui.open({ id: PANE, title: 'Omniverse · Agents', focus: true })
    return { text: 'Omniverse agent cards opened.' }
  })

  // The engine refuses a compaction under the command's own turn, so it runs just after.
  on('command.run', { command: 'om-rollover' }, async $ => {
    const session = await $.session.id()
    $.clock.after(100, () => void rollOver($, session, 'requested with /om-rollover').then(text => $.ui.toast(text)))
    return { text: 'OmniMemo rollover starting: checkpoint, then a fresh context from the capsule.' }
  })

  // Our own compaction answer: the conversation becomes the persisted capsule, nothing else.
  on('session.compact', async ($, e, next) => {
    if (e.agentId !== undefined || pending?.phase !== 'compacting' || e.instructions !== MARKER) return next(e)
    pending.answered = true
    const request = pending.lastRequest
      ? `\nLast request from the person (verbatim, cut to 1200 characters):\n${pending.lastRequest}\n`
      : ''
    return { messages: [{ role: 'user' as const, text: pending.capsule + request, toolUses: [] }] }
  }).catch(($, e, next) => next(e)) // On any failure the engine's own compaction stands.

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    // After the turn, so compaction and prompts run with the session idle.
    if (e.agentId === undefined) $.clock.after(200, () => void afterTurn($, e.answer))
    return result
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const list = await read($, agents)
    const line = await read($, report)
    return (
      <Box flexDirection="column">
        <Text dimColor>{line}</Text>
        {list.map(a => {
          const p = a.progress
          const filled = typeof p.percent === 'number' ? Math.round(p.percent / 10) : 0
          const bar =
            p.kind === 'determinate' && typeof p.percent === 'number'
              ? '█'.repeat(filled) + '░'.repeat(10 - filled) + ` ${p.percent}%` + (p.total ? ` · ${p.completed}/${p.total}` : '')
              : '░'.repeat(10) + ' progress unknown'
          const ctx =
            a.context.used_percent === undefined ? 'context unknown' : `context ${Math.round(a.context.used_percent)}% (${a.context.level})`
          return (
            <Box flexDirection="column" marginBottom={1}>
              <Text bold>
                {a.display_slug} · {a.status.toUpperCase()}
              </Text>
              <Text>{a.task?.title ?? 'No active task'}</Text>
              <Text dimColor>
                {bar} · {ctx}
              </Text>
            </Box>
          )
        })}
      </Box>
    )
  })
}

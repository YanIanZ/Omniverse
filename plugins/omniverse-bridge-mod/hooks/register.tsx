// Omniverse bridge mod: OmniMemo agent cards, reported context usage and opt-in rollover.
// Everything goes through the local `om` CLI (no server, no token). Telemetry is the host's
// own numbers; prompts and tool arguments are never sent. See docs/RUNTIME_EVENTS.md.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { AgentCard, AgentRecord } from '../types'

const PANE = 'omniverse-agent-cards'
const SESSION_PANE = 'omniverse-agent-session'
const agents = atom({ plugin: 'omniverse-bridge', key: 'agents' } as const, [] as AgentCard[])
const report = atom({ plugin: 'omniverse-bridge', key: 'report' } as const, 'No bridge reading yet')
const self = atom({ plugin: 'omniverse-bridge', key: 'self' } as const, '')
const focus = atom({ plugin: 'omniverse-bridge', key: 'focus' } as const, '')
const records = atom({ plugin: 'omniverse-bridge', key: 'records' } as const, [] as AgentRecord[])

/** Offline sessions and sessions with no recent signal (stale, model unavailable) are hidden; the count stays visible. */
export function present(list: AgentCard[]) {
  return list.filter(a => a.status !== 'offline' && a.status !== 'stale')
}

/** Other terminal agents for the band: present, not this session, busiest first. */
export function others(list: AgentCard[], session: string) {
  const order = ['blocked', 'working', 'waiting']
  return present(list)
    .filter(a => a.session_id !== session)
    .sort((a, b) => order.indexOf(a.status) - order.indexOf(b.status))
}

/** `codex · gpt-6.1-sol`: the client and its reported model, or "model unknown". */
export function agentLabel(a: AgentCard) {
  const client = a.client ?? a.display_slug.split('-')[0]
  const model = a.model && !a.model.includes('unavailable') ? a.model : 'model unknown'
  return `${client} · ${model}`
}

const clip = (text: string, n = 160) => (text.length > n ? text.slice(0, n - 1) + '…' : text)

/** Readable lines from a saved record: JSON checkpoints become `key: value` and bullet lines; text stays text. */
export function recordLines(content: string): string[] {
  let value: unknown
  try {
    value = JSON.parse(content)
  } catch {
    return content.split('\n').filter(l => l.trim()).slice(0, 6).map(l => clip(l))
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) return [clip(content)]
  const out: string[] = []
  for (const [key, v] of Object.entries(value as Record<string, unknown>)) {
    if (typeof v === 'string' || typeof v === 'number') out.push(clip(`${key}: ${v}`))
    else if (Array.isArray(v) && v.length) {
      out.push(`${key}:`)
      for (const item of v.slice(0, 6))
        out.push(clip('  • ' + (item && typeof item === 'object' ? Object.values(item).join(' · ') : String(item))))
    }
  }
  return out.slice(0, 24)
}

/** The OmniMemo records this agent saved, newest first (the agent label is provenance, not identity). */
export function recordsOf(list: { agent?: string; id: string; title: string; kind: string; state: string; created_at: string; content?: string }[], client: string) {
  return list
    .filter(m => m.agent === client)
    .slice(0, 5)
    .map(m => ({ id: m.id, title: m.title, kind: m.kind, state: m.state, created_at: m.created_at, lines: recordLines(m.content ?? '') }))
}

const mark = (status: string) => (status === 'working' ? '●' : status === 'blocked' ? '◆' : '○')
const tone = (status: string) => (status === 'working' ? 'success' : status === 'blocked' ? 'warning' : undefined)

/** What is known about an agent, in order; unknown values are left out rather than printed as "unknown". */
export function facts(a: AgentCard, now: number) {
  const out = [a.status]
  if (a.task) out.push(a.task.title)
  else if (a.tool_category) out.push(a.tool_category.replace('_', ' '))
  const p = a.progress
  if (p.kind === 'determinate' && typeof p.percent === 'number')
    out.push(`${p.percent}%` + (p.total ? ` (${p.completed}/${p.total})` : ''))
  if (a.context.used_percent !== undefined) out.push(`ctx ${Math.round(a.context.used_percent)}%`)
  if (a.last_seen) out.push(ago(a.last_seen, now))
  return out
}

export function ago(iso: string | undefined, now: number) {
  if (!iso) return ''
  const s = Math.max(0, Math.round((now - Date.parse(iso)) / 1000))
  return s < 60 ? `${s}s` : s < 3600 ? `${Math.round(s / 60)}m` : `${Math.round(s / 3600)}h`
}

/** A handoff in flight: the parent's checkpoint saved, then the fresh child awaiting its ACK. */
type Pending = { parent: string; child?: string; digest: string; capsule: string; lastRequest?: string }

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
    const all = JSON.parse(r.stdout) as AgentCard[]
    const live = present(all).slice(0, 32)
    await update($, agents, () => live)
    const session = await $.session.id()
    await update($, self, () => session)
    const count = (s: string) => live.filter(a => a.status === s).length
    const quiet = all.filter(a => a.status === 'stale').length
    const hidden = quiet ? ` · ${quiet} with no recent signal hidden` : ''
    await update($, report, () => (live.length ? `${live.length} agent(s) present${hidden}` : `No agents present${hidden}`))
    $.ui.status(`OmniMemo · ${live.length} agents · ${count('working')} working · ${count('blocked')} blocked${ctx}`)
  } catch {
    await update($, agents, () => [])
    await update($, report, () => 'Bridge unavailable')
    $.ui.status('OmniMemo unavailable' + ctx)
  }
}

/** Checkpoint, reserve the only child, /clear into a fresh session, deliver the capsule once. */
async function rollOver($: EngineInterface, parent: string, why: string) {
  if (pending) return 'A rollover is already in progress.'
  const prepared = await run($, ['--agent', 'claude', 'rollover', 'prepare', '--session', parent, '--provider', 'claude'])
  const parsed = prepared.exitCode === 0 ? parsePrepared(prepared.stdout) : undefined
  if (!parsed) return 'Rollover not started: om rollover prepare failed; nothing changed.'
  const reserved = await run($, ['rollover', 'begin', '--session', parent, '--provider', 'claude'])
  if (reserved.exitCode !== 0) return 'Rollover not started: this session already handed off once (one child per session).'
  const lastUser = (await $.session.messages()).filter(m => m.role === 'user' && m.text.trim()).at(-1)
  pending = { parent, ...parsed, lastRequest: lastUser?.text.slice(0, 1200) }
  const fail = async (reason: string) => {
    await run($, ['rollover', 'report', '--session', parent, '--digest', parsed.digest, '--outcome', 'failed', '--reason', reason])
    pending = undefined
    return `Rollover not applied (${reason}). This session is unchanged; the checkpoint is saved.`
  }
  // /clear ends this conversation; the process goes on under a new session id with an empty context.
  const cleared = await $.command.run({ command: 'clear' }).then(() => true, () => false)
  if (!cleared) return fail('/clear did not run')
  const child = await $.session.id()
  if (child === parent) return fail('no new session after /clear')
  await run($, ['rollover', 'link', '--session', parent, '--child', child, '--provider', 'claude'])
  pending = { ...pending, child }
  rollovers.push(Date.now())
  const request = pending.lastRequest
    ? `\nLast request from the person (verbatim, cut to 1200 characters):\n${pending.lastRequest}\n`
    : ''
  void $.prompt.submit({
    text: `${parsed.capsule}${request}\nOmniMemo rollover (${why}) from session ${parent}. First line of your reply must be exactly \`ACK ${parsed.digest}\`; then continue the work above.`,
  })
  return `Fresh session ${child} started from the verified capsule (digest ${parsed.digest}); waiting for the acknowledgement.`
}

/** After a main turn: settle an ACK, report usage, then prepare or hand off on a rising level. */
async function afterTurn($: EngineInterface, answer: string) {
  const session = await $.session.id()
  if (pending?.child && pending.child === session) {
    const ok = acknowledged(answer, pending.digest)
    await run($, ['rollover', 'report', '--session', pending.parent, '--child', session, '--digest', pending.digest, '--outcome', ok ? 'completed' : 'failed', '--reason', ok ? 'acknowledged' : 'first line was not the ACK'])
    $.ui.toast(
      ok
        ? 'OmniMemo rollover acknowledged: the task moved to this session.'
        : `OmniMemo rollover not acknowledged; the parent keeps the task (claude --resume ${pending.parent}).`,
    )
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

/** Opens one agent's OmniMemo record: its card plus what it saved. Never its private conversation. */
async function openAgent($: EngineInterface, card: AgentCard) {
  const client = card.client ?? card.display_slug.split('-')[0] ?? ''
  await update($, focus, () => card.session_id ?? card.display_slug)
  const r = await run($, ['memory', 'list', '--limit', '60'])
  const list = r.exitCode === 0 ? recordsOf(JSON.parse(r.stdout), client) : []
  await update($, records, () => list)
  await $.ui.open({ id: SESSION_PANE, title: agentLabel(card), focus: true })
}

export const register: Register = (on, options) => {
  config.om = String(options.omPath || 'om')
  config.mode = String(options.rollover || 'suggest')
  config.rolloverAt = Number(options.rolloverAt ?? 80)
  config.prepareAt = Math.min(Number(options.prepareAt ?? 70), config.rolloverAt)

  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'om-agents', description: 'Show live OmniMemo agent cards' })
    await $.command.register({ name: 'om-agent', description: 'Open another agent session from OmniMemo: /om-agent codex' })
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

  on('command.run', { command: 'om-agent' }, async ($, e) => {
    const want = e.args.trim()
    const list = others(await read($, agents), await read($, self))
    const card = list.find(a => a.session_id === want || a.client === want || agentLabel(a).startsWith(want)) ?? list[0]
    if (!card) return { text: 'No other agent is present in OmniMemo right now.' }
    await openAgent($, card)
    return { text: `Opened ${agentLabel(card)} from OmniMemo.` }
  })

  // /clear cannot run under the command's own turn, so the handoff starts just after it.
  on('command.run', { command: 'om-rollover' }, async $ => {
    const session = await $.session.id()
    $.clock.after(100, () => void rollOver($, session, 'requested with /om-rollover').then(text => $.ui.toast(text)))
    return { text: 'OmniMemo rollover starting: checkpoint, then a fresh session from the capsule.' }
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    // After the turn, so /clear and prompts run with the session idle.
    if (e.agentId === undefined) $.clock.after(200, () => void afterTurn($, e.answer))
    return result
  })

  // Other terminal agents (Codex, OpenCode, Gemini, other Claude sessions) as rows by the
  // prompt, the way Claude's own subagents list: client · model, state, task, last signal.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const rows = others(await read($, agents), await read($, self))
    if (!rows.length) return next(e)
    const { Box, Button, Text } = $.ui.resolve(e)
    const now = await $.clock.now()
    return (
      <Box flexDirection="column">
        {rows.slice(0, 6).map(a => (
          <Button key={a.session_id ?? a.display_slug} onPress={() => openAgent($, a)}>
            <Text wrap="truncate-end">
              <Text color={tone(a.status)}>{mark(a.status)} </Text>
              <Text bold>{agentLabel(a)}</Text>
              <Text dimColor>{' · ' + facts(a, now).join(' · ')}</Text>
            </Text>
          </Button>
        ))}
        {rows.length > 6 ? <Text dimColor>{rows.length - 6} more · /om-agents</Text> : null}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: SESSION_PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const id = await read($, focus)
    const card = (await read($, agents)).find(a => (a.session_id ?? a.display_slug) === id)
    const saved = await read($, records)
    const now = await $.clock.now()
    return (
      <Box flexDirection="column">
        {card ? (
          <Box flexDirection="column" marginBottom={1}>
            <Text bold>
              {agentLabel(card)} · {card.status.toUpperCase()}
            </Text>
            <Text>{card.task ? `Task: ${card.task.title}` : 'No active task'}</Text>
            <Text dimColor>
              {card.tool_category ? `last tool: ${card.tool_category} · ` : ''}
              {card.last_seen ? `last signal ${ago(card.last_seen, now)} ago` : 'last signal unknown'}
              {card.context.used_percent === undefined ? ' · context unknown' : ` · context ${Math.round(card.context.used_percent)}%`}
            </Text>
          </Box>
        ) : (
          <Text dimColor>This session is no longer present (offline or no recent signal).</Text>
        )}
        <Text dimColor>Saved to OmniMemo by this agent{saved.length ? '' : ': nothing yet'}</Text>
        {saved.map(m => (
          <Box key={m.id} flexDirection="column" marginTop={1}>
            <Text bold>
              {m.title} <Text dimColor>· {m.kind} · {m.state} · {ago(m.created_at, now)} ago</Text>
            </Text>
            {m.lines.map((line, i) => (
              <Text key={String(i)} wrap="wrap">
                {line}
              </Text>
            ))}
          </Box>
        ))}
        <Text dimColor>
          From OmniMemo: status, task and saved records only. Its private conversation stays in its own client.
        </Text>
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Button, Text } = $.ui.resolve(e)
    const list = await read($, agents)
    const line = await read($, report)
    const me = await read($, self)
    const now = await $.clock.now()
    return (
      <Box flexDirection="column">
        <Text dimColor>{line}</Text>
        {list.map(a => {
          const isMe = a.session_id === me
          const p = a.progress
          const bar =
            p.kind === 'determinate' && typeof p.percent === 'number'
              ? '█'.repeat(Math.round(p.percent / 10)) + '░'.repeat(10 - Math.round(p.percent / 10))
              : undefined
          const row = (
            <Box flexDirection="column" marginTop={1}>
              <Text wrap="truncate-end">
                <Text color={tone(a.status)}>{mark(a.status)} </Text>
                <Text bold>{agentLabel(a)}</Text>
                <Text dimColor>{isMe ? ' · this session' : ''}</Text>
              </Text>
              <Text wrap="truncate-end">
                {'  '}
                {a.task?.title ?? (a.tool_category ? `tool: ${a.tool_category.replace('_', ' ')}` : 'no active task')}
              </Text>
              <Text dimColor wrap="truncate-end">
                {'  '}
                {[a.status, bar ? `${bar} ${p.percent}%` : '', a.context.used_percent !== undefined ? `ctx ${Math.round(a.context.used_percent)}% ${a.context.level}` : '', a.last_seen ? ago(a.last_seen, now) + ' ago' : '']
                  .filter(Boolean)
                  .join(' · ')}
              </Text>
            </Box>
          )
          return isMe ? (
            <Box key={a.session_id ?? a.display_slug}>{row}</Box>
          ) : (
            <Button key={a.session_id ?? a.display_slug} onPress={() => openAgent($, a)}>
              {row}
            </Button>
          )
        })}
        {list.length > 1 ? <Text dimColor>{'\n'}Select another agent to open its OmniMemo record.</Text> : null}
      </Box>
    )
  })
}

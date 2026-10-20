// Omniverse bridge mod: OmniMemo presence, agent cards, reported context usage and opt-in rollover.
// Everything goes through the local `om` CLI (no server, no token). Telemetry is the host's
// own numbers; tool arguments are never sent. See docs/RUNTIME_EVENTS.md.
// Lifecycle (session, prompt, tool, turn) comes from the plugin's own engine events, so no
// Claude Code settings hooks are needed for OmniMemo.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, TurnUsage } from 'claude-code'

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

/** Other agents for the band: present, not this session, busiest first. Claude subagents are
 * left out (each Claude lists its own); a Codex or OpenCode run delegated from here stays in,
 * since Claude's list shows only the subagent waiting on it, not the run's progress. */
export function others(list: AgentCard[], session: string) {
  const order = ['blocked', 'working', 'waiting']
  return present(list)
    .filter(a => a.session_id !== session && !(a.spawned_by && (a.client ?? a.display_slug.split('-')[0]) === 'claude'))
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
  const out = [a.agent_type === 'delegated' ? `delegated · ${a.status}` : a.status]
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
type Pending = { parent: string; child?: string; digest: string; capsule: string; lastRequest?: string; startedAt: number }

/** A child that never finishes its first turn must not block every later rollover. */
const pendingLimitMs = 15 * 60_000

// Options are read in register on each load; the rest starts over on a reload.
const config = { om: 'om', mode: 'suggest', rolloverAt: 80, prepareAt: 70, windows: new Map<string, number>() }

/** `claude-sonnet-5-5=1000000, claude-haiku-5-5=200000`: windows the person states for models
 * other than the session's, which the host does not report. Bad entries are ignored. */
export function parseWindows(text: string) {
  const windows = new Map<string, number>()
  for (const entry of text.split(',')) {
    const [model, size] = entry.split('=').map(s => s.trim())
    const tokens = Number(size)
    if (model && Number.isInteger(tokens) && tokens > 0) windows.set(model, tokens)
  }
  return windows
}
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

function run($: EngineInterface, args: string[], stdin?: string, timeoutMs = 30_000) {
  return $.process.run([config.om, ...args], { stdin, timeoutMs })
}

/**
 * One lifecycle signal as `om hook claude` reads it, the payload a settings hook would have sent:
 * the event name, session id, working directory and model, plus the tool name or prompt where
 * that event carries one. Never tool arguments. Failures are ignored: presence never blocks Claude.
 */
async function lifecycle($: EngineInterface, event: string, extra: Record<string, unknown> = {}, timeoutMs = 5_000) {
  try {
    const payload = { hook_event_name: event, session_id: await $.session.id(), cwd: await $.session.cwd(), model: await $.session.model(), ...extra }
    const r = await run($, ['hook', 'claude'], JSON.stringify(payload), timeoutMs)
    return r.exitCode === 0 ? r.stdout.trim() : ''
  } catch {
    return ''
  }
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
    $.ui.status(`OmniMemo · ${live.length} ${live.length === 1 ? 'agent' : 'agents'} · ${count('working')} working · ${count('blocked')} blocked${ctx}`)
  } catch {
    await update($, agents, () => [])
    await update($, report, () => 'Bridge unavailable')
    $.ui.status('OmniMemo unavailable · run om doctor' + ctx)
  }
}

/** Checkpoint, reserve the only child, /clear into a fresh session, deliver the capsule once. */
async function rollOver($: EngineInterface, parent: string, why: string) {
  await expirePending($)
  if (pending) return 'A rollover is already in progress.'
  const prepared = await run($, ['--agent', 'claude', 'rollover', 'prepare', '--session', parent, '--provider', 'claude'])
  const parsed = prepared.exitCode === 0 ? parsePrepared(prepared.stdout) : undefined
  if (!parsed) return 'Rollover not started: om rollover prepare failed; nothing changed.'
  const reserved = await run($, ['rollover', 'begin', '--session', parent, '--provider', 'claude'])
  if (reserved.exitCode !== 0) return 'Rollover not started: this session already handed off once (one child per session).'
  const lastUser = (await $.session.messages()).filter(m => m.role === 'user' && m.text.trim()).at(-1)
  pending = { parent, ...parsed, lastRequest: lastUser?.text.slice(0, 1200), startedAt: Date.now() }
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
  const linked = await run($, ['rollover', 'link', '--session', parent, '--child', child, '--provider', 'claude'])
  if (linked.exitCode !== 0) return fail('the fresh session could not be linked')
  pending = { ...pending, child }
  rollovers.push(Date.now())
  const request = pending.lastRequest
    ? `\nLast request from the person (verbatim, cut to 1200 characters):\n${pending.lastRequest}\n`
    : ''
  void $.prompt.submit({
    text: `${parsed.capsule}${request}\nOmniMemo rollover (${why}) from session ${parent}. First line of your reply must be exactly \`ACK ${parsed.digest}\`; then resume your own task from the records above, verifying them against the repository.`,
  })
  return `Fresh session ${child} started from the verified capsule (digest ${parsed.digest}); waiting for the acknowledgement.`
}

/** Records an unanswered handoff as failed once it is older than the limit. */
async function expirePending($: EngineInterface) {
  if (!pending || Date.now() - pending.startedAt < pendingLimitMs) return
  const child = pending.child ? ['--child', pending.child] : []
  await run($, ['rollover', 'report', '--session', pending.parent, ...child, '--digest', pending.digest, '--outcome', 'failed', '--reason', 'no acknowledgement in time'])
  pending = undefined
}

/** After a main turn: settle an ACK, report usage, then prepare or hand off on a rising level. */
async function afterTurn($: EngineInterface, answer: string) {
  await expirePending($)
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

/** Subagents seen in this session: who spawned each, and which have ended. */
const parents = new Map<string, string>()
const ended = new Set<string>()

/** A subagent's event names it and its parent, so it is linked whichever event arrives first. */
async function subagent($: EngineInterface, agentId: string) {
  return { session_id: agentId, model: undefined, spawned_by: parents.get(agentId) ?? (await $.session.id()) }
}

/** Other CLIs as Claude subagent types: each hands one task to its CLI through `om` and reports
 * back. Read-only by default; offered only for a request that names that CLI. */
const WORKERS = [
  { name: 'codex', cli: 'Codex (OpenAI)', run: 'codex run', write: '--sandbox workspace-write' },
  { name: 'opencode', cli: 'OpenCode', run: 'opencode run', write: '--write' },
]

function workerPrompt(w: (typeof WORKERS)[number]) {
  return `You hand one task to ${w.cli}, another coding agent CLI, through OmniMemo, then report back.
1. Write the task as a self-contained brief to a new file in $TMPDIR (use Write): the goal, the files or area in scope, what done means, and constraints. Include only what the task needs: never secrets, credentials, or this conversation.
2. Run it with Bash, Bash timeout 600000: \`${config.om} --agent claude ${w.run} --prompt-file <file> --timeout 570 --spawned-by "$CLAUDE_CODE_SESSION_ID"\`
   A model named for the task goes in \`--model <id>\`, not in the brief. It is read-only by default. Add \`${w.write}\` only when the task you were given explicitly asks for file edits. A task too big for ten minutes: say so and suggest how to split it.
3. Reply with what it reported: its answer, the files it changed (\`git status --short\`), and any failure exactly as printed. Do not redo its work yourself. Never commit, push, or change git settings.
If the command is missing or fails to start, say so and stop.`
}

async function registerWorkers($: EngineInterface) {
  for (const w of WORKERS) {
    await $.agent.register({
      name: w.name,
      description: `Hands one self-contained task to the ${w.cli} CLI through OmniMemo and returns its answer. Use only when the user asks for ${w.name} (for example "run it with ${w.name}" or "${w.name} subagent"). Read-only unless the user asked for edits.`,
      prompt: workerPrompt(w),
      tools: ['Bash', 'Write', 'Read'],
      model: 'haiku',
    }).catch(() => undefined) // a host without agent types keeps the rest of the bridge
  }
}

/** Last context sample (tokens) sent per subagent, so a step that barely moved it spawns no `om`. */
const sampled = new Map<string, number>()

/** A subagent's context: its last request's tokens. Over the session's window when it runs the
 * session's model; on any other model the window is unknown, so tokens only, never a guessed percent. */
async function subagentContext($: EngineInterface, agentId: string, usage: TurnUsage) {
  try {
    const { context } = await $.session.usage()
    const base = (m: string) => m.replace(/\[.*\]$/, '')
    const window =
      (context.window && base(usage.model) === base(await $.session.model()) ? context.window : undefined)
      ?? config.windows.get(base(usage.model))
    const tokens = usage.input_tokens + usage.cache_read_input_tokens + usage.cache_creation_input_tokens + usage.output_tokens
    if (Math.abs((sampled.get(agentId) ?? -Infinity) - tokens) < (window ? window / 100 : 5_000)) return
    sampled.set(agentId, tokens)
    const sample = window
      ? { used_percentage: Math.min(100, Math.round((tokens / window) * 100)), context_window_size: window }
      : { used_tokens: tokens }
    await run($, ['hook', 'claude'], JSON.stringify({
      hook_event_name: 'context.usage', session_id: agentId, cwd: await $.session.cwd(), model: usage.model,
      context_window: sample,
    }))
  } catch {
    // Context is best effort: a failed sample leaves the card's context unknown.
  }
}

export const register: Register = (on, options) => {
  config.om = String(options.omPath || 'om')
  config.mode = String(options.rollover || 'suggest')
  config.rolloverAt = Number(options.rolloverAt ?? 80)
  config.prepareAt = Math.min(Number(options.prepareAt ?? 70), config.rolloverAt)
  config.windows = parseWindows(String(options.contextWindows ?? ''))

  on('session.start', async ($, e, next) => {
    void lifecycle($, 'SessionStart')
    await $.command.register({ name: 'om-agents', description: 'Show the other agents OmniMemo sees (Codex, OpenCode, other Claude sessions)' })
    await $.command.register({ name: 'om-agent', description: "Show another agent's OmniMemo card and saved records (not its chat): /om-agent codex" })
    await $.command.register({ name: 'om-rollover', description: 'Save a checkpoint and continue this work in a fresh, empty conversation' })
    $.clock.after(300, () => void refresh($))
    $.clock.every(15_000, () => void refresh($))
    const result = await next(e)
    void registerWorkers($) // agent types are accepted once the session has bound
    return result
  })

  on('command.run', { command: 'om-agents' }, async $ => {
    await refresh($)
    await $.ui.open({ id: PANE, title: 'Omniverse · Agents', focus: true })
    return { text: 'Omniverse agent cards opened.' }
  })

  on('command.run', { command: 'om-agent' }, async ($, e) => {
    const want = e.args.trim()
    const list = others(await read($, agents), await read($, self))
    const card = want
      ? list.find(a => a.session_id === want || a.client === want || agentLabel(a).startsWith(want))
      : list[0]
    if (!card) {
      if (!list.length) return { text: 'No other agent is present in OmniMemo right now.' }
      return { text: `No present agent matches "${want}". Present: ${list.map(agentLabel).join(', ')}.` }
    }
    await openAgent($, card)
    return { text: `Opened ${agentLabel(card)} from OmniMemo.` }
  })

  // /clear cannot run under the command's own turn, so the handoff starts just after it.
  on('command.run', { command: 'om-rollover' }, async $ => {
    const session = await $.session.id()
    $.clock.after(100, () => void rollOver($, session, 'requested with /om-rollover').then(text => $.ui.toast(text)))
    return { text: 'OmniMemo rollover starting: checkpoint, then a fresh session from the capsule.' }
  })

  // The project capsule rides with the prompt as context the model reads and the person never sees;
  // `om` returns it only when it changed since this session last received it.
  on('prompt.submit', async ($, e, next) => {
    if (e.command || e.isMeta) return next(e)
    const capsule = await lifecycle($, 'UserPromptSubmit', { prompt: e.text })
    return next(capsule ? { ...e, context: [...(e.context ?? []), capsule] } : e)
  }).catch(($, e, next) => next(e)) // fail open: the prompt always goes through

  // A subagent is its own OmniMemo session (its loop's agentId), linked to the loop that spawned it.
  // Its spawn can settle after its tool calls, or after it ended: then it only fills in the type.
  on('agent.spawn', async ($, e, next) => {
    const result = await next(e)
    if (result.agentId) {
      const parent = e.parentAgentId ?? (await $.session.id())
      parents.set(result.agentId, parent)
      void lifecycle($, ended.has(result.agentId) ? 'SubagentStop' : 'SubagentStart', {
        session_id: result.agentId, model: result.model, spawned_by: parent, agent_type: e.subagentType,
        // The call's few-word task label; `om` keeps it only where session titles are opted in.
        title: e.description,
      })
    }
    return result
  }).catch(($, e, next) => next(e)) // fail open: never refuses a spawn

  // Tool activity by category: `om` maps the tool name and reads nothing else of the call.
  // A subagent's call counts for the subagent, not for the main session.
  on('tool.call', async ($, e, next) => {
    const who = e.agentId ? await subagent($, e.agentId) : {}
    void lifecycle($, 'PreToolUse', { tool_name: e.tool, ...who })
    const result = await next(e)
    const failed = result.deny !== undefined || result.isError === true
    void lifecycle($, failed ? 'PostToolUseFailure' : 'PostToolUse', { tool_name: e.tool, ...who })
    return result
  }).catch(($, e, next) => next(e)) // fail open: never refuses or repeats a tool call

  // A subagent's requests carry its context use; the main session's comes from session.usage.
  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    if (e.agentId && result.usage) void subagentContext($, e.agentId, result.usage)
    return result
  })

  on('session.end', async ($, e, next) => {
    // The engine allows about 1.5 s for every session.end hook together.
    await lifecycle($, 'SessionEnd', { session_id: e.sessionId, reason: e.reason }, 1_200)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined) void lifecycle($, 'Stop')
    else {
      ended.add(e.agentId)
      void lifecycle($, 'SubagentStop', await subagent($, e.agentId))
    }
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

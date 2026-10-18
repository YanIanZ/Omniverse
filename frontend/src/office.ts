import type { Agent, Approval, LiveEvent, Task } from './api'

// The office is a fixed 1056 x 640 map; rooms and slots are in map pixels.
export const MAP = { w: 1056, h: 640 }

export type RoomId =
  | 'briefing'
  | 'handoffs'
  | 'approvals'
  | 'workspace'
  | 'review'
  | 'lounge'
  | 'pantry'
  | 'server'

export type Room = { id: RoomId; label: string; x: number; y: number; w: number; h: number; floor: string }

export const ROOMS: Room[] = [
  { id: 'briefing', label: 'Briefing', x: 16, y: 32, w: 248, h: 200, floor: 'carpet' },
  { id: 'handoffs', label: 'Handoffs', x: 280, y: 32, w: 300, h: 200, floor: 'plum' },
  { id: 'approvals', label: 'Approvals', x: 596, y: 32, w: 444, h: 200, floor: 'plum' },
  { id: 'workspace', label: 'Workspace', x: 16, y: 268, w: 540, h: 252, floor: 'wood' },
  { id: 'review', label: 'Review', x: 572, y: 268, w: 468, h: 252, floor: 'tech' },
  { id: 'lounge', label: 'Lounge', x: 16, y: 548, w: 360, h: 84, floor: 'warm' },
  { id: 'pantry', label: 'Pantry', x: 392, y: 548, w: 168, h: 84, floor: 'check' },
  { id: 'server', label: 'Server room', x: 576, y: 548, w: 464, h: 84, floor: 'grate' },
]

// Where a 36 x 48 agent sprite stands in each room (top-left corner), in fill order.
const SLOTS: Partial<Record<RoomId, [number, number][]>> = {
  briefing: [[68, 92], [128, 92], [188, 92], [68, 150], [128, 150], [188, 150]],
  handoffs: [[340, 92], [404, 92], [468, 92], [520, 92]],
  approvals: [[716, 70], [776, 70], [836, 70], [896, 70], [956, 70]],
  workspace: [[100, 296], [196, 296], [340, 296], [436, 296], [100, 416], [196, 416], [340, 416], [436, 416]],
  review: [[640, 362], [700, 362], [760, 362], [820, 362], [880, 362]],
  lounge: [[124, 572], [264, 572], [316, 572], [40, 572], [176, 572]],
}

export type Tone = 'green' | 'amber' | 'blue' | 'gray'

export type Plate = {
  count: number
  text: string
}

export type Placement = {
  key: string
  agent: Agent
  room: RoomId
  x: number
  y: number
  bubble: string
  tone: Tone
  state: string
  fresh: boolean
  task?: Task
  approval?: Approval
  /** When a room has two or more unknown agents, each of those placements carries
   * the shared room plate so the map can show one summary instead of stacked bubbles. */
  plate?: Plate
}

const short = (text: string, n = 26) => (text.length > n ? text.slice(0, n - 1) + '…' : text)

export function minutesAgo(iso: string, now = Date.now()) {
  return Math.max(0, Math.round((now - Date.parse(iso)) / 60000))
}

export function ago(iso: string, now = Date.now()) {
  const s = Math.max(0, Math.round((now - Date.parse(iso)) / 1000))
  if (s < 60) return `${s}s ago`
  if (s < 3600) return `${Math.round(s / 60)}m ago`
  return `${Math.round(s / 3600)}h ago`
}

/**
 * Every placement is derived from a verified record: a session signal, a task the
 * agent owns, an approval it requested, or a checkpoint event it committed.
 * Disconnected sessions leave the map; nothing is inferred beyond these rules.
 */
export function place(
  agents: Agent[],
  tasks: Task[],
  approvals: Approval[],
  events: LiveEvent[],
  now = Date.now(),
): { placed: Placement[]; overflow: Partial<Record<RoomId, number>> } {
  const present = agents.filter((a) => a.status !== 'disconnected')
  // A task or approval belongs to the most recently seen session of that provider.
  const latest = new Map<string, Agent>()
  for (const a of present) {
    const prev = latest.get(a.agent)
    if (!prev || prev.last_seen < a.last_seen) latest.set(a.agent, a)
  }
  const used: Partial<Record<RoomId, number>> = {}
  const overflow: Partial<Record<RoomId, number>> = {}
  const placed: Placement[] = []

  for (const agent of present) {
    const primary = latest.get(agent.agent) === agent
    const approval = primary
      ? approvals.find((p) => p.status === 'pending' && p.requested_by === agent.agent)
      : undefined
    const owned = primary ? tasks.filter((t) => t.owner === agent.agent) : []
    const reviewing = owned.find((t) => t.status === 'review')
    const doing = owned.find((t) => t.status === 'doing')
    const handoff = primary
      ? events.find(
          (e) =>
            e.type === 'memory.checkpoint.created' &&
            e.data.agent === agent.agent &&
            now - Date.parse(e.timestamp) < 180_000,
        )
      : undefined
    const seenSeconds = (now - Date.parse(agent.last_seen)) / 1000

    let room: RoomId
    let bubble: string
    let tone: Tone
    let state: string
    let task: Task | undefined
    if (approval) {
      room = 'approvals'
      bubble = 'Needs you: ' + short(approval.action, 20)
      tone = 'blue'
      state = 'waiting for approval'
      task = reviewing ?? doing
    } else if (reviewing) {
      room = 'review'
      bubble = short(reviewing.title)
      tone = 'amber'
      state = 'reviewing'
      task = reviewing
    } else if (doing) {
      room = 'workspace'
      bubble = short(doing.title)
      tone = 'green'
      state = 'working'
      task = doing
    } else if (agent.status === 'unknown') {
      room = 'lounge'
      // Short so crowded lounges stay legible; the panel and aria-label carry the full state.
      bubble = `? ${minutesAgo(agent.last_seen, now)}m`
      tone = 'gray'
      state = 'unknown'
    } else if (handoff) {
      room = 'handoffs'
      bubble = 'Handoff saved'
      tone = 'blue'
      state = 'handing off'
    } else if (agent.status === 'active') {
      room = 'workspace'
      bubble = 'Prompt received'
      tone = 'green'
      state = 'active, no task claimed'
    } else {
      room = 'briefing'
      bubble = 'Ready'
      tone = 'gray'
      state = 'ready'
    }

    const slots = SLOTS[room] ?? []
    const index = used[room] ?? 0
    used[room] = index + 1
    if (index >= slots.length) {
      overflow[room] = (overflow[room] ?? 0) + 1
      continue
    }
    const [x, y] = slots[index]
    placed.push({
      key: agent.agent + ':' + agent.session_id,
      agent,
      room,
      x,
      y,
      bubble,
      tone,
      state,
      fresh: seenSeconds < 60 && (room === 'workspace' || room === 'review'),
      task,
      approval,
    })
  }

  // Unknown agents get a shared room plate instead of per-agent bubbles so the
  // label is never covered, even when there is only one of them.
  const unknownByRoom = new Map<RoomId, Placement[]>()
  for (const p of placed) {
    if (p.agent.status !== 'unknown') continue
    unknownByRoom.set(p.room, [...(unknownByRoom.get(p.room) ?? []), p])
  }
  for (const [, list] of unknownByRoom) {
    if (list.length === 0) continue
    const oldest = list.reduce((a, b) => (a.agent.last_seen < b.agent.last_seen ? a : b))
    const text =
      list.length === 1
        ? `? ${minutesAgo(oldest.agent.last_seen, now)}m`
        : `${list.length} · no signal ${minutesAgo(oldest.agent.last_seen, now)}m`
    for (const p of list) p.plate = { count: list.length, text }
  }

  return { placed, overflow }
}

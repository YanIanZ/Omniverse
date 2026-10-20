import type { Agent, Approval, LiveEvent, Task } from './api'

// The office is a drawn floor plan on a fixed 840 x 790 sheet; rooms, doors and
// slots are in plan units. The strip below the building holds the legend and title block.
export const PLAN = { w: 840, h: 790 }

export type RoomId =
  | 'briefing'
  | 'handoffs'
  | 'approvals'
  | 'workspace'
  | 'review'
  | 'lounge'
  | 'pantry'
  | 'server'

type Corridor = 'north' | 'south'
type Door = { corridor: Corridor; x: number }

export type Room = { id: RoomId; label: string; x: number; y: number; w: number; h: number; doors: Door[] }

// Two corridors run east-west between the rows of rooms; the west hall joins them.
export const CORRIDOR: Record<Corridor, number> = { north: 206, south: 493 }
export const HALL_X = 34
export const BUILDING = { x: 16, y: 16, w: 808, h: 648 }

export const ROOMS: Room[] = [
  { id: 'briefing', label: 'Briefing', x: 16, y: 16, w: 244, h: 174, doors: [{ corridor: 'north', x: 138 }] },
  { id: 'handoffs', label: 'Handoffs', x: 260, y: 16, w: 240, h: 174, doors: [{ corridor: 'north', x: 380 }] },
  { id: 'approvals', label: 'Approvals', x: 500, y: 16, w: 324, h: 174, doors: [{ corridor: 'north', x: 712 }] },
  {
    id: 'workspace',
    label: 'Workspace',
    x: 52,
    y: 222,
    w: 384,
    h: 254,
    doors: [
      { corridor: 'north', x: 304 },
      { corridor: 'south', x: 304 },
    ],
  },
  {
    id: 'review',
    label: 'Review',
    x: 436,
    y: 222,
    w: 388,
    h: 254,
    doors: [
      { corridor: 'north', x: 690 },
      { corridor: 'south', x: 690 },
    ],
  },
  { id: 'lounge', label: 'Lounge', x: 16, y: 510, w: 504, h: 154, doors: [{ corridor: 'south', x: 412 }] },
  { id: 'pantry', label: 'Pantry', x: 520, y: 510, w: 110, h: 154, doors: [{ corridor: 'south', x: 575 }] },
  { id: 'server', label: 'Server room', x: 630, y: 510, w: 194, h: 154, doors: [{ corridor: 'south', x: 790 }] },
]

// Where an agent figure stands in each room (its feet), in fill order. Pantry and
// the server room are never a state, so nobody is placed there.
const SLOTS: Partial<Record<RoomId, [number, number][]>> = {
  briefing: [[88, 126], [188, 126]],
  handoffs: [[330, 126], [430, 126]],
  approvals: [[562, 126], [662, 126], [762, 126]],
  workspace: [[124, 318], [244, 318], [364, 318], [124, 426], [244, 426], [364, 426]],
  review: [[510, 318], [630, 318], [750, 318], [510, 426], [630, 426], [750, 426]],
  lounge: [[76, 602], [172, 602], [268, 602], [364, 602], [460, 602]],
}

/** Waypoints an agent walks from one room to another: through its door, along the
 * corridors (by the west hall when the rooms share none), and in through the other door. */
export function route(from: Room, to: Room, start: [number, number], end: [number, number]): [number, number][] {
  if (from.id === to.id) return [start, end]
  // Walk to the door's x inside the room, out through the threshold, then along the corridors.
  const out = (door: Door, at: [number, number]): [number, number][] => [[door.x, at[1]], [door.x, CORRIDOR[door.corridor]]]
  const shared = from.doors.find((d) => to.doors.some((e) => e.corridor === d.corridor))
  if (shared) {
    const target = to.doors.find((e) => e.corridor === shared.corridor)!
    return [start, ...out(shared, start), ...out(target, end).reverse(), end]
  }
  const a = from.doors[0]
  const b = to.doors[0]
  return [
    start,
    ...out(a, start),
    [HALL_X, CORRIDOR[a.corridor]],
    [HALL_X, CORRIDOR[b.corridor]],
    ...out(b, end).reverse(),
    end,
  ]
}

/** State colour families: amber waits on a human, flight is work in review or handoff,
 * working is a verified active signal, neutral is a quiet waiting session, unknown is stale. */
export type Tone = 'attention' | 'flight' | 'working' | 'neutral' | 'unknown'

export type Placement = {
  key: string
  agent: Agent
  room: RoomId
  x: number
  y: number
  /** Current signal printed under the figure, cut to the free width there; the panel and aria-label carry the full text. */
  signal: string
  tone: Tone
  state: string
  fresh: boolean
  task?: Task
  approval?: Approval
}

export function minutesAgo(iso: string, now = Date.now()) {
  return Math.max(0, Math.round((now - Date.parse(iso)) / 60000))
}

export function ago(iso: string, now = Date.now()) {
  const s = Math.max(0, Math.round((now - Date.parse(iso)) / 1000))
  if (s < 60) return `${s}s ago`
  if (s < 3600) return `${Math.round(s / 60)}m ago`
  return `${Math.round(s / 3600)}h ago`
}

/** In the office: a session reporting now. Offline and stale (silent) sessions leave the map at
 * once; they stay listed on the Agents page and return with their next signal. */
export function inOffice(a: Agent): boolean {
  return a.status !== 'offline' && a.status !== 'stale'
}

/**
 * Every placement is derived from a verified record: a session signal, a task the
 * agent owns, an approval it requested, or a checkpoint event it committed.
 * Offline and stale sessions leave the map; nothing is inferred beyond these rules.
 */
export function place(
  agents: Agent[],
  tasks: Task[],
  approvals: Approval[],
  events: LiveEvent[],
  now = Date.now(),
): { placed: Placement[]; overflow: Partial<Record<RoomId, number>> } {
  const present = agents.filter(inOffice)
  // A task or approval belongs to the most recently seen session of that provider.
  const latest = new Map<string, Agent>()
  // A subagent works for its parent session; tasks and approvals stay with the parent.
  for (const a of present.filter((x) => !x.spawned_by)) {
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
    let signal: string
    let tone: Tone
    let state: string
    let task: Task | undefined
    if (approval) {
      room = 'approvals'
      signal = 'Asks: ' + approval.action
      tone = 'attention'
      state = 'asks you'
      task = reviewing ?? doing
    } else if (agent.status === 'stale') {
      // No recent signal outranks task ownership: owning a task never proves current work.
      room = 'lounge'
      signal = 'No recent signal'
      tone = 'unknown'
      state = 'stale'
      task = reviewing ?? doing
    } else if (reviewing) {
      room = 'review'
      signal = reviewing.title
      tone = 'flight'
      state = 'reviewing'
      task = reviewing
    } else if (doing) {
      room = 'workspace'
      signal = doing.title
      tone = 'working'
      state = 'doing'
      task = doing
    } else if (agent.status === 'blocked') {
      room = 'approvals'
      signal = 'Blocked'
      tone = 'attention'
      state = 'blocked'
    } else if (handoff) {
      room = 'handoffs'
      signal = 'Handoff saved'
      tone = 'flight'
      state = 'handing off'
    } else if (agent.status === 'working') {
      room = 'workspace'
      signal = agent.tool_category ? 'Tool: ' + agent.tool_category.replace('_', ' ') : 'Prompt received'
      tone = 'working'
      state = 'working'
    } else {
      room = 'briefing'
      signal = 'Waiting for work'
      tone = 'neutral'
      state = 'waiting'
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
      signal,
      tone,
      state,
      fresh: seenSeconds < 60 && (room === 'workspace' || room === 'review'),
      task,
      approval,
    })
  }

  return { placed, overflow }
}

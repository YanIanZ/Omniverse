import { type KeyboardEvent, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react'
import { agentName, type Health } from './api'
import { FigureGlyph } from './Figure'
import { BUILDING, CORRIDOR, HALL_X, minutesAgo, PLAN, type Placement, ROOMS, type RoomId, route } from './office'
import './office.css'

// Furniture in plan symbols, drawn in construction lines under the agents. Decor only:
// nothing here reflects or implies agent activity.
type Shape = { x: number; y: number; w: number; h: number; round?: boolean }
const FURNITURE: Shape[] = [
  // Briefing: screen wall and a long table
  { x: 60, y: 22, w: 156, h: 4 },
  { x: 58, y: 70, w: 160, h: 14 },
  // Handoffs: pin board and a round table
  { x: 300, y: 22, w: 160, h: 4 },
  { x: 350, y: 64, w: 60, h: 24, round: true },
  // Approvals: the counter
  { x: 540, y: 72, w: 244, h: 12 },
  // Workspace: two desk rows behind the agents
  { x: 92, y: 274, w: 304, h: 10 },
  { x: 92, y: 382, w: 304, h: 10 },
  // Review: diff wall and review bench
  { x: 470, y: 228, w: 320, h: 4 },
  { x: 476, y: 274, w: 308, h: 10 },
  { x: 476, y: 382, w: 308, h: 10 },
  // Lounge: two sofas
  { x: 40, y: 562, w: 150, h: 10 },
  { x: 260, y: 562, w: 150, h: 10 },
  // Pantry: counter
  { x: 530, y: 630, w: 90, h: 14 },
]

const BAND = 7
const ROOM_GAP = 30

type Route = { id: number; key: string; points: [number, number][]; label: string; short: string }

const reducedMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches

/** Length of the signal-age dimension line on a log scale, so 1m, 10m and 1h read apart. */
const dimension = (minutes: number) => Math.min(88, 22 + 11 * Math.log2(1 + minutes))

const SIGNAL_CHAR = 5.6
const cut = (text: string, width: number) => {
  const n = Math.max(8, Math.floor(width / SIGNAL_CHAR))
  return text.length > n ? text.slice(0, n - 1) + '…' : text
}

/** Free width for the signal under each figure: centred when both sides are tight, otherwise
 * starting at the name plate and running toward the open side, up to a neighbour or the wall. */
function signalLayout(placed: Placement[]) {
  const out = new Map<string, { width: number; start: boolean }>()
  for (const p of placed) {
    const room = ROOMS.find((r) => r.id === p.room)!
    const row = placed.filter((o) => o !== p && o.room === p.room && o.y === p.y)
    const left = Math.min(p.x - room.x - 12, ...row.filter((o) => o.x < p.x).map((o) => (p.x - o.x) / 2))
    const right = Math.min(room.x + room.w - p.x - 12, ...row.filter((o) => o.x > p.x).map((o) => o.x - p.x - 46))
    const centred = 2 * Math.min(left, right)
    if (right + 38 > centred + 24) out.set(p.key, { width: Math.min(right + 38, 300), start: true })
    else out.set(p.key, { width: centred, start: false })
  }
  return out
}

const CALLOUT_CHAR = 6.9

/** Callout for a walked route: set on the longest corridor run, cut to fit it. */
function callout(r: Route) {
  let best = { x: r.points[0][0], y: r.points[0][1], len: 0 }
  r.points.slice(1).forEach((pt, i) => {
    const prev = r.points[i]
    if (pt[1] !== prev[1]) return
    const len = Math.abs(pt[0] - prev[0])
    if (len > best.len) best = { x: (pt[0] + prev[0]) / 2, y: pt[1], len }
  })
  const fit = Math.floor((best.len - 12) / CALLOUT_CHAR)
  const text = r.label.length > fit ? (fit > r.short.length ? r.label.slice(0, fit - 1) + '…' : r.short) : r.label
  return { x: best.x, y: best.y + 4, text }
}

type Props = {
  placed: Placement[]
  overflow: Partial<Record<RoomId, number>>
  health?: Health
  selected?: string
  now: number
  live: boolean
  onSelect: (key: string) => void
}

const plate = (name: string) => (name.length > 11 ? name.slice(0, 10) + '…' : name)

export function OfficeMap({ placed, overflow, health, selected, now, live, onSelect }: Props) {
  const nodes = useRef(new Map<string, SVGGElement>())
  const previous = useRef(new Map<string, { room: RoomId; x: number; y: number }>())
  const [routes, setRoutes] = useState<Route[]>([])

  // Signature move: when a committed event moves an agent to another room, it walks
  // there through the doors and corridors, leaving its route drawn for a moment.
  useLayoutEffect(() => {
    const fresh: Route[] = []
    for (const p of placed) {
      const before = previous.current.get(p.key)
      previous.current.set(p.key, { room: p.room, x: p.x, y: p.y })
      if (!before || before.room === p.room) continue
      const from = ROOMS.find((r) => r.id === before.room)!
      const to = ROOMS.find((r) => r.id === p.room)!
      const points = route(from, to, [before.x, before.y], [p.x, p.y])
      const short = `${agentName(p.agent)} → ${to.label}`
      fresh.push({ id: Date.now() + Math.random(), key: p.key, points, short, label: p.task ? `${short} · ${p.task.title}` : short })
      const node = nodes.current.get(p.key)
      if (!node || reducedMotion()) continue
      const lengths = points.slice(1).map((pt, i) => Math.hypot(pt[0] - points[i][0], pt[1] - points[i][1]))
      const total = lengths.reduce((a, b) => a + b, 0) || 1
      let run = 0
      const frames = points.map((pt, i) => {
        if (i > 0) run += lengths[i - 1]
        return { transform: `translate(${pt[0]}px, ${pt[1]}px)`, offset: run / total }
      })
      node.animate(frames, { duration: Math.min(2400, 600 + total * 2.2), easing: 'cubic-bezier(0.22, 1, 0.36, 1)' })
    }
    if (fresh.length) setRoutes((list) => [...list.filter((r) => !fresh.some((f) => f.key === r.key)), ...fresh])
  }, [placed])

  useEffect(() => {
    if (!routes.length) return
    const id = window.setTimeout(() => setRoutes([]), 6000)
    return () => window.clearTimeout(id)
  }, [routes])

  const count = useMemo(
    () => (room: RoomId) => placed.filter((p) => p.room === room).length + (overflow[room] ?? 0),
    [placed, overflow],
  )

  const occupancy = (id: RoomId) => {
    const n = count(id)
    if (id === 'pantry') return 'Break room'
    if (id === 'server') return 'Storage'
    if (n === 0) return 'Empty'
    const stale = placed.filter((p) => p.room === id && p.tone === 'unknown').length + (id === 'lounge' ? overflow.lounge ?? 0 : 0)
    if (id === 'approvals') {
      const asking = placed.filter((p) => p.room === id && p.approval).length
      return `${n} ${n === 1 ? 'agent' : 'agents'}${asking ? ` · ${asking} asking you` : ''}`
    }
    return `${n} ${n === 1 ? 'agent' : 'agents'}${stale && stale === n ? ' · no recent signal' : ''}`
  }

  const signals = useMemo(() => signalLayout(placed), [placed])
  const redis = health?.redis ?? 'unknown'
  const select = (key: string) => (e: KeyboardEvent) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault()
      onSelect(key)
    }
  }

  return (
    <svg
      className="plan"
      viewBox={`0 0 ${PLAN.w} ${PLAN.h}`}
      role="group"
      aria-label="Floor plan: each agent stands in the room of its verified state"
    >
      <defs>
        <pattern id="plan-hatch" width="4" height="4" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
          <rect width="4" height="4" className="hatch-ground" />
          <line x1="0" y1="0" x2="0" y2="4" className="hatch-line" />
        </pattern>
        <marker id="plan-arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="8" markerHeight="8" orient="auto">
          <path d="M0 1L9 5L0 9z" className="route-head" />
        </marker>
      </defs>

      {/* Building shell, corridors and the west hall */}
      <rect className="wall-outer" x={BUILDING.x} y={BUILDING.y} width={BUILDING.w} height={BUILDING.h} />
      <rect className="wall-inner" x={BUILDING.x} y={BUILDING.y} width={BUILDING.w} height={BUILDING.h} />
      {ROOMS.map((room) => (
        <g key={room.id} className={'room room-' + room.id}>
          <rect className="room-floor" x={room.x} y={room.y} width={room.w} height={room.h} />
          <rect className="wall-outer" x={room.x} y={room.y} width={room.w} height={room.h} />
          <rect className="wall-inner" x={room.x} y={room.y} width={room.w} height={room.h} />
          {room.doors.map((d) => {
            // The door sits in the wall that faces its corridor and swings into the room.
            const bottom = CORRIDOR[d.corridor] > room.y + room.h / 2
            const wallY = bottom ? room.y + room.h : room.y
            const dir = bottom ? -1 : 1
            const x0 = d.x - ROOM_GAP / 2
            return (
              <g key={d.corridor} className="door">
                <rect className="door-gap" x={x0} y={wallY - BAND / 2 - 1} width={ROOM_GAP} height={BAND + 2} />
                <path
                  className="door-swing"
                  d={`M${x0} ${wallY}v${dir * ROOM_GAP}M${x0} ${wallY + dir * ROOM_GAP}A${ROOM_GAP} ${ROOM_GAP} 0 0 ${dir > 0 ? 0 : 1} ${x0 + ROOM_GAP} ${wallY}`}
                />
              </g>
            )
          })}
          <text className={'room-name' + (room.id === 'approvals' && placed.some((p) => p.approval) ? ' is-asking' : '')} x={room.x + 16} y={room.y + 26}>
            {room.label.toUpperCase()}
          </text>
          <text className="room-occupancy" x={room.x + 16} y={room.y + 42}>
            {occupancy(room.id)}
          </text>
          {overflow[room.id] ? (
            <text className="room-more" x={room.x + room.w - 14} y={room.y + 26} textAnchor="end">
              +{overflow[room.id]} more · see Agents
            </text>
          ) : null}
        </g>
      ))}

      {FURNITURE.map((f, i) => (
        <rect key={i} className="furniture" x={f.x} y={f.y} width={f.w} height={f.h} rx={f.round ? f.h / 2 : 1} />
      ))}

      {/* Server room: storage health from the server's own report */}
      <g className="racks" transform="translate(652 566)">
        <rect className="furniture" width={150} height={66} />
        <path className="furniture" d="M0 33h150" />
        <circle cx={14} cy={17} r={4} className={health ? 'led led-ok' : 'led led-unknown'} />
        <text className="rack-text" x={26} y={21}>
          MongoDB {health ? 'ok' : 'unknown'}
        </text>
        <circle
          cx={14}
          cy={50}
          r={4}
          className={'led ' + (redis === 'connected' ? 'led-ok' : redis === 'unavailable' ? 'led-fault' : 'led-unknown')}
        />
        <text className={'rack-text' + (redis === 'connected' ? '' : ' is-quiet')} x={26} y={54}>
          Redis {redis}
        </text>
      </g>

      {routes.map((r) => {
        const c = callout(r)
        return (
          <g key={r.id} className="route-group">
            <polyline className="route" points={r.points.map((p) => p.join(',')).join(' ')} markerEnd="url(#plan-arrow)" />
            <rect
              className="route-callout-back"
              x={c.x - (c.text.length * CALLOUT_CHAR) / 2 - 6}
              y={c.y - 12}
              width={c.text.length * CALLOUT_CHAR + 12}
              height={17}
            />
            <text className="route-callout" x={c.x} y={c.y} textAnchor="middle">
              {c.text}
            </text>
          </g>
        )
      })}
      {/* Corridor labels are knocked out of the linework so a route never hides them. */}
      <text className="corridor-label" x={62} y={CORRIDOR.north + 3}>
        NORTH CORRIDOR
      </text>
      <text className="corridor-label" x={62} y={CORRIDOR.south + 3}>
        SOUTH CORRIDOR
      </text>
      <text className="corridor-label" transform={`translate(${HALL_X + 3} 350) rotate(-90)`}>
        WEST HALL
      </text>


      {placed.map((p) => {
        const minutes = minutesAgo(p.agent.last_seen, now)
        const length = dimension(minutes)
        const isSelected = selected === p.key
        return (
          <g
            key={p.key}
            ref={(node) => {
              if (node) nodes.current.set(p.key, node)
              else nodes.current.delete(p.key)
            }}
            className={`agent tone-${p.tone}${isSelected ? ' is-selected' : ''}${p.fresh && live ? ' is-fresh' : ''}`}
            style={{ transform: `translate(${p.x}px, ${p.y}px)` }}
            role="button"
            tabIndex={0}
            aria-pressed={isSelected}
            aria-label={`${agentName(p.agent)}${p.helpers ? ` with ${p.helpers} subagent${p.helpers === 1 ? '' : 's'}` : ''}, ${p.state}${p.task ? ': ' + p.task.title : ''}, in ${ROOMS.find((r) => r.id === p.room)?.label}, last signal ${minutes} minutes ago`}
            onClick={() => onSelect(p.key)}
            onKeyDown={select(p.key)}
          >
            <rect className="hit" x={-46} y={-32} width={92} height={92} />
            <circle className="focus-ring" cy={-12} r={22} />
            <circle className="select-ring" cy={-12} r={20} />
            <FigureGlyph agent={p.agent.agent} unknown={p.tone === 'unknown'} />
            <circle className="pip" cx={11} cy={-24} r={3.6} />
            {p.helpers > 0 && (
              <g className="helpers" aria-hidden="true">
                <rect x={-34} y={-36} width={22} height={14} rx={7} />
                <text x={-23} y={-25.5}>+{p.helpers}</text>
              </g>
            )}
            <rect className="plate" x={-38} y={5} width={76} height={18} />
            <text className="plate-name" y={18}>
              {/* A subagent's plate names its type; the figure already shows its client. */}
              {plate(p.agent.spawned_by ? '› ' + (p.agent.agent_type ?? 'subagent') : p.agent.agent)}
            </text>
            {/* Stale figures carry no per-agent line: the room tag already says there is no recent signal. */}
            {p.tone !== 'unknown' && (
              <text
                className="signal"
                x={signals.get(p.key)?.start ? -38 : 0}
                y={37}
                textAnchor={signals.get(p.key)?.start ? 'start' : 'middle'}
              >
                {cut(p.signal, signals.get(p.key)?.width ?? 100)}
              </text>
            )}
            <g className="dimension" transform="translate(0 47)">
              <path d={`M${-length / 2} -3v6M${length / 2} -3v6M${-length / 2} 0H-13M13 0H${length / 2}`} />
              <text y={3.5}>{minutes > 99 ? '99m+' : `${minutes}m`}</text>
            </g>
          </g>
        )
      })}

      {/* Legend and title block */}
      <g className="legend" transform="translate(16 698)">
        <text className="sheet-head" y={10}>
          LEGEND
        </text>
        {/* Every plan state, grouped by the mark it is drawn with (see PLAN_STATES in views.tsx). */}
        <circle className="key-working" cx={5} cy={28} r={4.5} />
        <text x={16} y={32}>
          doing, working
        </text>
        <circle className="key-attention" cx={122} cy={28} r={4.5} />
        <text x={133} y={32}>
          asks you, blocked
        </text>
        <circle className="key-flight" cx={256} cy={28} r={3.6} />
        <text x={267} y={32}>
          reviewing, handing off
        </text>
        <circle className="key-neutral" cx={5} cy={46} r={4.5} />
        <text x={16} y={50}>
          waiting
        </text>
        <circle className="key-fault" cx={122} cy={46} r={4.5} />
        <text x={133} y={50}>
          fault (server rack)
        </text>
        {[
          [1, '1m'],
          [10, '10m'],
          [60, '1h'],
        ].map(([m, label], i) => {
          const w = dimension(m as number)
          const x = [0, 52, 132][i]
          return (
            <g key={label} className="dimension" transform={`translate(${x + w / 2} 70)`}>
              <path d={`M${-w / 2} -3v6M${w / 2} -3v6M${-w / 2} 0H-12M12 0H${w / 2}`} />
              <text y={3.5}>{label}</text>
            </g>
          )
        })}
        <text x={238} y={74}>
          minutes since the last verified signal
        </text>
      </g>
      <g className="title-block" transform="translate(520 682)">
        <rect width={304} height={92} />
        <path d="M0 46h304M150 0v92M234 46v46" />
        <text className="tb-key" x={10} y={16}>
          PROJECT
        </text>
        <text className="tb-mono" x={10} y={35}>
          {health ? (health.project_name ?? health.project_id.slice(0, 12)).slice(0, 18) : 'unknown'}
        </text>
        <text className="tb-key" x={160} y={16}>
          DRAWING
        </text>
        <text className="tb-value" x={160} y={36}>
          OFFICE · LEVEL 1
        </text>
        <text className="tb-key" x={10} y={62}>
          SHEET
        </text>
        <text className="tb-value" x={10} y={82}>
          MISSION CONTROL
        </text>
        <text className="tb-key" x={160} y={62}>
          STATUS
        </text>
        <text className={'tb-mono ' + (live ? 'is-live' : 'is-off')} x={160} y={81}>
          {live ? 'live' : 'not live'}
        </text>
        <text className="tb-key" x={244} y={62}>
          REV
        </text>
        <text className="tb-rev" x={244} y={84}>
          {health?.revision ?? '…'}
        </text>
      </g>
    </svg>
  )
}

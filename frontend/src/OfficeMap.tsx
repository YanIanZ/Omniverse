import { type CSSProperties, useEffect, useMemo, useRef, useState } from 'react'
import type { Health } from './api'
import { MAP, type Placement, ROOMS, type Room, type RoomId } from './office'
import './office.css'
import { AgentSprite, Sprite } from './Sprite'
import { FURNITURE, type FurnitureId, LED } from './sprites'

type Block = { cls: string; x: number; y: number; w: number; h: number }

const BLOCKS: Block[] = [
  { cls: 'rug', x: 52, y: 92, w: 176, h: 104 },
  { cls: 'meeting-table', x: 316, y: 132, w: 228, h: 64 },
  { cls: 'meeting-table', x: 700, y: 108, w: 236, h: 72 },
  { cls: 'desk', x: 64, y: 330, w: 212, h: 30 },
  { cls: 'desk', x: 304, y: 330, w: 212, h: 30 },
  { cls: 'desk', x: 64, y: 450, w: 212, h: 30 },
  { cls: 'desk', x: 304, y: 450, w: 212, h: 30 },
  { cls: 'desk', x: 604, y: 398, w: 330, h: 30 },
  { cls: 'counter', x: 456, y: 584, w: 92, h: 36 },
  { cls: 'rug lounge-rug', x: 112, y: 600, w: 76, h: 26 },
]

// Scenery motion hooks: pixels of these map characters get a class; CSS animates them
// only without prefers-reduced-motion. None of this reflects or implies agent activity.
const SCREEN_CLASSES = { b: 'px-screen' }
const WINDOW_CLASSES = { s: 'px-star', y: 'px-lit' }
const CARET_CLASSES = { C: 'px-caret' }
const RACK_CLASSES = { A: 'px-led' }

type Item = { item: FurnitureId; x: number; y: number; classes?: Record<string, string> }

const DESKS = [
  [64, 300],
  [304, 300],
  [64, 420],
  [304, 420],
]

// Standalone furniture and wall decor, drawn under agents so it never hides a sprite,
// bubble or name tag.
const DECOR: Item[] = [
  // Briefing
  { item: 'projector', x: 96, y: 37 },
  { item: 'bookshelf', x: 24, y: 40 },
  { item: 'lamp', x: 238, y: 140 },
  // Handoffs
  { item: 'corkboard', x: 292, y: 37 },
  { item: 'cubbies', x: 464, y: 37 },
  // Approvals
  { item: 'window', x: 612, y: 37, classes: WINDOW_CLASSES },
  { item: 'window', x: 980, y: 37, classes: WINDOW_CLASSES },
  { item: 'cabinet', x: 616, y: 100 },
  { item: 'cabinet', x: 644, y: 100 },
  { item: 'bookshelf', x: 1000, y: 64 },
  // Workspace
  { item: 'kanban', x: 220, y: 274 },
  { item: 'bookshelf', x: 24, y: 372 },
  { item: 'cooler', x: 524, y: 278 },
  // Review
  { item: 'wallscreen', x: 600, y: 290, classes: CARET_CLASSES },
  { item: 'window', x: 958, y: 273, classes: WINDOW_CLASSES },
  { item: 'bookshelf', x: 952, y: 300 },
  { item: 'bookshelf', x: 986, y: 300 },
  { item: 'lamp', x: 952, y: 418 },
  // Lounge
  { item: 'window', x: 84, y: 553, classes: WINDOW_CLASSES },
  { item: 'window', x: 210, y: 553, classes: WINDOW_CLASSES },
  { item: 'vending', x: 344, y: 558 },
  // Pantry
  { item: 'fridge', x: 400, y: 558 },
  { item: 'cooler', x: 432, y: 572 },
  // Server room (neutral equipment only; health lives on the racks)
  { item: 'ups', x: 724, y: 566 },
  { item: 'extinguisher', x: 1014, y: 596 },
]

// Things that sit on tables and desks, drawn above the furniture.
const PROPS: Item[] = [
  ...DESKS.flatMap(([x, y], i): Item[] => [
    { item: 'monitor', x: x + 8, y: y + 2, classes: SCREEN_CLASSES },
    { item: 'monitor', x: x + 170, y: y + 2, classes: SCREEN_CLASSES },
    { item: 'keyboard', x: x + 11, y: y + 34 },
    { item: 'keyboard', x: x + 173, y: y + 34 },
    // Each desk keeps its own small clutter so the rows do not read as copies.
    ...([
      [
        { item: 'mug', x: x + 82, y: y + 34 },
        { item: 'folder', x: x + 106, y: y + 34 },
      ],
      [{ item: 'paper', x: x + 92, y: y + 31 }],
      [
        { item: 'folder', x: x + 84, y: y + 34 },
        { item: 'mug', x: x + 112, y: y + 35 },
      ],
      [{ item: 'mug', x: x + 104, y: y + 35 }],
    ] as Item[][])[i],
    { item: 'chair', x: x + 40, y: y + 70 },
    { item: 'chair', x: x + 134, y: y + 70 },
  ]),
  ...[612, 676, 740, 804, 868].map((x): Item => ({ item: 'monitor', x, y: 402, classes: SCREEN_CLASSES })),
  ...[646, 706, 766, 826, 886].map((x): Item => ({ item: 'chair', x, y: 440 })),
  // Handoffs table
  { item: 'laptop', x: 330, y: 150, classes: SCREEN_CLASSES },
  { item: 'mug', x: 388, y: 170 },
  { item: 'paper', x: 430, y: 150 },
  { item: 'folder', x: 470, y: 158 },
  { item: 'mug', x: 512, y: 150 },
  ...[350, 430, 500].map((x): Item => ({ item: 'chair', x, y: 200 })),
  // Approvals table: inbox, stamp, outbox
  { item: 'tray', x: 716, y: 128 },
  { item: 'stamp', x: 764, y: 126 },
  { item: 'paper', x: 800, y: 130 },
  { item: 'mug', x: 846, y: 150 },
  { item: 'tray', x: 880, y: 128 },
  ...[740, 820, 890].map((x): Item => ({ item: 'chair', x, y: 186 })),
  // Lounge and pantry
  { item: 'sofa', x: 48, y: 596 },
  { item: 'sofa', x: 196, y: 596 },
  { item: 'coffee', x: 470, y: 558 },
  { item: 'coffee', x: 506, y: 558 },
  { item: 'mug', x: 474, y: 592 },
  { item: 'mug', x: 510, y: 592 },
]

const PLANTS = [
  [30, 190],
  [536, 190],
  [30, 464],
  [1000, 190],
  [1000, 464],
]

type Glow = { x: number; y: number; w: number; h: number; tone: 'warm' | 'cool' }

const GLOWS: Glow[] = [
  { x: 40, y: 70, w: 210, h: 150, tone: 'warm' },
  { x: 196, y: 130, w: 100, h: 90, tone: 'warm' },
  { x: 312, y: 96, w: 240, h: 130, tone: 'warm' },
  { x: 680, y: 70, w: 280, h: 150, tone: 'warm' },
  ...DESKS.map(([x, y]): Glow => ({ x: x - 10, y: y - 10, w: 232, h: 120, tone: 'warm' })),
  ...DESKS.flatMap(([x, y]): Glow[] => [
    { x: x - 6, y: y + 24, w: 68, h: 40, tone: 'cool' },
    { x: x + 156, y: y + 24, w: 68, h: 40, tone: 'cool' },
  ]),
  { x: 590, y: 336, w: 320, h: 80, tone: 'cool' },
  { x: 912, y: 440, w: 100, h: 76, tone: 'warm' },
  { x: 30, y: 560, w: 330, h: 70, tone: 'warm' },
  { x: 400, y: 556, w: 150, h: 72, tone: 'warm' },
]

// Doorways cut into room walls: [x, y] of a 32px opening on a top or bottom wall.
const DOORS = [
  [200, 228],
  [420, 228],
  [960, 228],
  [440, 268],
  [480, 516],
  [980, 268],
  [980, 516],
  [300, 548],
  [480, 548],
  [980, 548],
]

type LedState = 'on' | 'off' | 'fault'

function rackPalette(state: LedState) {
  return { ...FURNITURE.rack.palette, L: LED[state], A: LED[state] }
}

function Clock() {
  const [now, setNow] = useState(() => new Date())
  useEffect(() => {
    const id = window.setInterval(() => setNow(new Date()), 30_000)
    return () => window.clearInterval(id)
  }, [])
  const minutes = now.getMinutes()
  const hours = (now.getHours() % 12) + minutes / 60
  return (
    <svg className="clock" width={27} height={27} viewBox="0 0 9 9" shapeRendering="crispEdges" aria-hidden="true">
      <Sprite map={FACE} palette={FACE_PALETTE} scale={1} className="clock-face" />
      <rect x={4} y={1.6} width={1} height={3.4} fill="#1a1423" transform={`rotate(${minutes * 6} 4.5 4.5)`} />
      <rect x={4} y={2.4} width={1} height={2.6} fill="#c4473c" transform={`rotate(${hours * 30} 4.5 4.5)`} />
      <rect x={4} y={4} width={1} height={1} fill="#1a1423" />
    </svg>
  )
}
const FACE = ['..OOOOO..', '.OFFtFFO.', 'OFFFFFFFO', 'OFFFFFFFO', 'OtFFFFFtO', 'OFFFFFFFO', 'OFFFFFFFO', '.OFFtFFO.', '..OOOOO..']
const FACE_PALETTE = { O: '#6a7388', F: '#e9e2d6', t: '#7c8494' }

function Plant({ x, y, i }: { x: number; y: number; i: number }) {
  return (
    <div className="decor plant" style={{ left: x, top: y, '--d': `${-i * 1.3}s` } as CSSProperties}>
      <Sprite map={FURNITURE.plantTop.map} palette={FURNITURE.plantTop.palette} className="plant-top" />
      <Sprite map={FURNITURE.plantPot.map} palette={FURNITURE.plantPot.palette} />
    </div>
  )
}

/**
 * Bubbles sit on two levels so neighbouring seats never collide: alternate agents in a
 * row lift theirs above the others. Widths are capped by the nearest bubble on the same
 * level (and, for the lower level, by the neighbouring lift stems), by the containing
 * room walls, and by a maximum on-screen width. Agents near a wall or the map edge
 * anchor their bubble toward the interior so the text never spills out. The hovered or
 * selected agent always shows its full text on top. Full text also stays in aria-label.
 */
const BUBBLE_SCREEN_MAX_PX = 220
const BUBBLE_PAD = 8
const WALL_ANCHOR = 60

type Anchor = 'left' | 'center' | 'right'

function bubbleLayout(placed: Placement[], scale: number) {
  const rows = new Map<string, Placement[]>()
  for (const p of placed) {
    const key = p.room + ':' + p.y
    rows.set(key, [...(rows.get(key) ?? []), p])
  }
  const out = new Map<string, { lift: boolean; max: number; anchor: Anchor }>()
  for (const row of rows.values()) {
    row.sort((a, b) => a.x - b.x)
    row.forEach((p, i) => {
      const lift = row.length > 1 && i % 2 === 1
      const gap = (j: number) => (row[j] ? Math.abs(row[j].x - p.x) : Infinity)
      let max = Math.min(gap(i - 2), gap(i + 2)) - 10
      if (!lift) max = Math.min(max, 2 * Math.min(gap(i - 1), gap(i + 1)) - 16)

      const room = ROOMS.find((r) => r.id === p.room)!
      const left = p.x - room.x
      const right = room.x + room.w - (p.x + 36)
      let anchor: Anchor = 'center'
      if (left < WALL_ANCHOR) anchor = 'left'
      else if (right < WALL_ANCHOR) anchor = 'right'

      if (anchor === 'left') {
        max = Math.min(max, right - BUBBLE_PAD)
      } else if (anchor === 'right') {
        max = Math.min(max, left - BUBBLE_PAD)
      } else {
        max = Math.min(max, 2 * Math.min(left, right) - BUBBLE_PAD * 2)
      }

      const screenMax = BUBBLE_SCREEN_MAX_PX / scale
      max = Math.max(72, Math.min(max, screenMax))
      out.set(p.key, { lift, max, anchor })
    })
  }
  return out
}

type Props = {
  placed: Placement[]
  overflow: Partial<Record<RoomId, number>>
  health?: Health
  selected?: string
  onSelect: (key: string) => void
}

export function OfficeMap({ placed, overflow, health, selected, onSelect }: Props) {
  const frame = useRef<HTMLDivElement>(null)
  const [scale, setScale] = useState(1)
  const [hot, setHot] = useState<string>()
  const [hint, setHint] = useState({ left: false, right: false })

  useEffect(() => {
    const el = frame.current
    if (!el) return
    const fit = () => setScale(Math.min(1.5, Math.max(0.6, el.clientWidth / MAP.w)))
    fit()
    const observer = new ResizeObserver(fit)
    observer.observe(el)
    return () => observer.disconnect()
  }, [])

  // Keep the important room in view when it (or the scale) changes.
  const importantRoom = useMemo<RoomId | undefined>(() => {
    const approval = placed.find((p) => p.approval)?.room
    if (approval) return approval
    return placed.find((p) => p.key === selected)?.room
  }, [placed, selected])

  useEffect(() => {
    const el = frame.current
    const roomId = importantRoom
    if (!el || !roomId) return
    const room = ROOMS.find((r) => r.id === roomId)
    if (!room) return
    const target = room.x * scale + (room.w * scale) / 2 - el.clientWidth / 2
    const max = el.scrollWidth - el.clientWidth
    el.scrollLeft = Math.max(0, Math.min(max, target))
  }, [importantRoom, scale])

  // Show edge fades and a scroll affordance whenever the map overflows the frame.
  useEffect(() => {
    const el = frame.current
    if (!el) return
    const update = () => {
      const left = el.scrollLeft > 1
      const right = el.scrollLeft + el.clientWidth < el.scrollWidth - 1
      setHint((h) => (h.left === left && h.right === right ? h : { left, right }))
    }
    update()
    el.addEventListener('scroll', update, { passive: true })
    const observer = new ResizeObserver(update)
    observer.observe(el)
    return () => {
      el.removeEventListener('scroll', update)
      observer.disconnect()
    }
  }, [scale])

  const layout = useMemo(() => bubbleLayout(placed, scale), [placed, scale])
  const count = useMemo(
    () => (room: RoomId) => placed.filter((p) => p.room === room).length + (overflow[room] ?? 0),
    [placed, overflow],
  )
  const occupiedRooms = useMemo(() => ROOMS.filter((r) => count(r.id) > 0), [count])
  const plates = useMemo(() => {
    const seen = new Set<RoomId>()
    const out: { room: RoomId; text: string }[] = []
    for (const p of placed) {
      if (p.plate && !seen.has(p.room)) {
        seen.add(p.room)
        out.push({ room: p.room, text: p.plate.text })
      }
    }
    return out
  }, [placed])

  const redis: LedState = health?.redis === 'connected' ? 'on' : health?.redis === 'unavailable' ? 'fault' : 'off'
  const mongo: LedState = health ? 'on' : 'off'
  const racks = [
    { x: 770, state: mongo },
    { x: 810, state: mongo },
    { x: 900, state: redis },
  ]

  const scrollToRoom = (room: Room) => {
    const el = frame.current
    if (!el) return
    const target = room.x * scale + (room.w * scale) / 2 - el.clientWidth / 2
    const max = el.scrollWidth - el.clientWidth
    el.scrollLeft = Math.max(0, Math.min(max, target))
  }

  return (
    <div className="map-wrap">
      <div
        className={`map-frame${hint.left ? ' is-scroll-left' : ''}${hint.right ? ' is-scroll-right' : ''}`}
        ref={frame}
      >
        {/* Below the legible minimum scale the map scrolls sideways instead of being clipped. */}
        <div
          className="map-size"
          style={{ width: MAP.w * scale, height: MAP.h * scale, '--map-scale': scale } as CSSProperties}
        >
          <div className="map" style={{ width: MAP.w, height: MAP.h, transform: `scale(${scale})` }}>
            <div className="hall" />
            {ROOMS.map((room) => (
              <div
                key={room.id}
                className={`room floor-${room.floor}${room.h < 120 ? ' room-short' : ''}`}
                style={{ left: room.x, top: room.y, width: room.w, height: room.h }}
              >
                <span className="wall" />
                <span className="room-label">
                  {room.label}
                  {count(room.id) > 0 && room.id !== 'server' && room.id !== 'pantry' ? ` · ${count(room.id)}` : ''}
                  {room.id === 'server' && health ? ` · MongoDB ok · Redis ${health.redis}` : ''}
                </span>
                {overflow[room.id] ? <span className="room-more">+{overflow[room.id]} more</span> : null}
              </div>
            ))}
            {DOORS.map(([x, y]) => (
              <div key={`door${x}-${y}`} className="door" style={{ left: x - 4, top: y }} />
            ))}
            {BLOCKS.map((b, i) => (
              <div key={i} className={`block ${b.cls}`} style={{ left: b.x, top: b.y, width: b.w, height: b.h }} />
            ))}
            {GLOWS.map((g, i) => (
              <div key={'glow' + i} className={`glow glow-${g.tone}`} style={{ left: g.x, top: g.y, width: g.w, height: g.h }} />
            ))}
            {racks.map((r) => (
              <div key={'ledglow' + r.x} className={`glow glow-led-${r.state}`} style={{ left: r.x - 25, top: 572, width: 80, height: 52 }} />
            ))}
            <div className="cable-tray" />
            {racks.map((r) => (
              <div key={'drop' + r.x} className="cable-drop" style={{ left: r.x + 14 }} />
            ))}
            {DECOR.map((p, i) => (
              <div key={'decor' + i} className={`decor decor-${p.item}`} style={{ left: p.x, top: p.y, '--d': `${-(i % 7) * 0.9}s` } as CSSProperties}>
                <Sprite map={FURNITURE[p.item].map} palette={FURNITURE[p.item].palette} classes={p.classes} />
              </div>
            ))}
            {PLANTS.map(([x, y], i) => (
              <Plant key={'plant' + i} x={x} y={y} i={i} />
            ))}
            <div className="decor clock-wrap" style={{ left: 230, top: 38 }}>
              <Clock />
            </div>
            <div className="decor fan" style={{ left: 596, top: 562 }}>
              <Sprite map={FURNITURE.fanA.map} palette={FURNITURE.fanA.palette} className="fan-a" />
              <Sprite map={FURNITURE.fanB.map} palette={FURNITURE.fanB.palette} className="fan-b" />
            </div>
            {racks.map((r, i) => (
              <div key={'rack' + i} className={`decor rack rack-${r.state}`} style={{ left: r.x, top: 556, '--d': `${-i * 0.45}s` } as CSSProperties}>
                <Sprite map={FURNITURE.rack.map} palette={rackPalette(r.state)} classes={RACK_CLASSES} />
              </div>
            ))}
            <span className="rack-tag" style={{ left: 770, width: 70 }}>
              MongoDB
            </span>
            <span className="rack-tag" style={{ left: 885, width: 60 }}>
              Redis
            </span>
            {PROPS.map((p, i) => (
              <div key={'prop' + i} className="prop" style={{ left: p.x, top: p.y, '--d': `${-((i * 0.53) % 4)}s` } as CSSProperties}>
                <Sprite map={FURNITURE[p.item].map} palette={FURNITURE[p.item].palette} classes={p.classes} />
              </div>
            ))}
            {placed.map((p) => (
              <button
                key={p.key}
                type="button"
                className={`agent tone-${p.tone}${p.agent.status === 'unknown' ? ' is-unknown' : ''}${selected === p.key ? ' is-selected' : ''}`}
                style={{ transform: `translate(${p.x}px, ${p.y}px)` }}
                onClick={() => onSelect(p.key)}
                onMouseEnter={() => setHot(p.key)}
                onMouseLeave={() => setHot(undefined)}
                onFocus={() => setHot(p.key)}
                onBlur={() => setHot(undefined)}
                aria-pressed={selected === p.key}
                aria-label={`${p.agent.agent}, ${p.state}${p.task ? ': ' + p.task.title : ''}, in ${p.room}`}
              >
                <AgentSprite agent={p.agent.agent} animate={p.fresh} />
              </button>
            ))}
            {/* One summary plate per room for crowds of unknown agents. */}
            <div className="room-plates" aria-hidden="true">
              {plates.map(({ room, text }) => {
                const r = ROOMS.find((x) => x.id === room)!
                return (
                  <div
                    key={room}
                    className="room-plate tone-gray"
                    style={{ left: r.x, top: r.y, width: r.w, height: r.h }}
                  >
                    <span className="room-plate-text">{text}</span>
                  </div>
                )
              })}
            </div>
            {/* Bubbles and name tags float above all furniture; the button above carries the accessible name. */}
            <div className="agent-tags" aria-hidden="true">
              {placed.map((p) => {
                const l = layout.get(p.key)
                const open = hot === p.key || selected === p.key
                return (
                  <div
                    key={p.key}
                    className={`agent-tag tone-${p.tone}${l?.lift ? ' lift' : ''}${open ? ' is-open' : ''}${p.plate ? ' is-plated' : ''} anchor-${l?.anchor ?? 'center'}`}
                    style={{ transform: `translate(${p.x}px, ${p.y}px)`, '--bw': `${l?.max ?? 260}px` } as CSSProperties}
                  >
                    <span
                      className="bubble"
                      onClick={() => onSelect(p.key)}
                      onMouseEnter={() => setHot(p.key)}
                      onMouseLeave={() => setHot(undefined)}
                    >
                      <span className="bubble-text">{p.bubble}</span>
                    </span>
                    <span className="nametag" onClick={() => onSelect(p.key)}>
                      {p.agent.agent}
                    </span>
                  </div>
                )
              })}
            </div>
          </div>
        </div>
      </div>
      {(hint.left || hint.right) && (
        <div className="map-hint" aria-hidden="true">
          <span>scroll for more rooms</span>
        </div>
      )}
      {occupiedRooms.length > 0 && (
        <div className="map-rooms" role="group" aria-label="Occupied rooms">
          {occupiedRooms.map((room) => (
            <button
              key={room.id}
              type="button"
              className="map-room"
              onClick={() => scrollToRoom(room)}
              title={`Scroll to ${room.label}`}
            >
              {room.label}
              <span className="map-room-count">{count(room.id)}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

export function Logo() {
  return <Sprite map={FURNITURE.logo.map} palette={FURNITURE.logo.palette} scale={3} />
}

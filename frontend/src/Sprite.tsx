import { useMemo } from 'react'
import { AGENT_FRAMES, agentPalette, type Palette, runs } from './sprites'

type SpriteProps = {
  map: string[]
  palette: Palette
  scale?: number
  className?: string
  /** Map character -> class on its pixels, for scenery-only CSS motion (screens, LEDs). */
  classes?: Record<string, string>
}

/** Pixel map as crisp SVG; decorative unless wrapped by a labelled control. */
export function Sprite({ map, palette, scale = 3, className, classes }: SpriteProps) {
  const rects = useMemo(() => runs(map, palette, classes), [map, palette, classes])
  const w = map[0].length
  const h = map.length
  return (
    <svg
      className={className}
      width={w * scale}
      height={h * scale}
      viewBox={`0 0 ${w} ${h}`}
      shapeRendering="crispEdges"
      aria-hidden="true"
      focusable="false"
    >
      {rects.map((r, i) => (
        <rect key={i} x={r.x} y={r.y} width={r.w} height={1} fill={r.fill} className={r.cls} />
      ))}
    </svg>
  )
}

/** Two stacked frames; CSS alternates them only for fresh signals and never under reduced motion. */
export function AgentSprite({ agent, scale = 3, animate = false }: { agent: string; scale?: number; animate?: boolean }) {
  const palette = useMemo(() => agentPalette(agent), [agent])
  return (
    <span className={'agent-sprite' + (animate ? ' animate' : '')}>
      <Sprite map={AGENT_FRAMES.a} palette={palette} scale={scale} className="frame-a" />
      <Sprite map={AGENT_FRAMES.b} palette={palette} scale={scale} className="frame-b" />
    </span>
  )
}

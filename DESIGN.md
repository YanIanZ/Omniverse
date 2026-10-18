---
name: OmniMemo Mission Control
description: A night office seen from above, where each agent's verified state is the room it stands in.
colors:
  ground: "#0d0f14"
  panel: "#12151c"
  raise: "#181c25"
  raise-hover: "#1e2330"
  rule: "#1f2430"
  rule-strong: "#2b3142"
  rule-hover: "#3d4560"
  ink: "#e6e9f0"
  muted: "#9aa3b8"
  glow: "#7fd4ff"
  glow-hover: "#a6e2ff"
  glow-ink: "#06212e"
  attention: "#ffcf5c"
  attention-hover: "#ffe08f"
  attention-ink: "#1f1500"
  ok: "#4fe07a"
  fault: "#ff6b5c"
  map-void: "#08090d"
  pixel-shadow: "#050608"
  room-wall: "#4a5266"
  tone-green-fill: "#163a22"
  tone-green-text: "#9ff0b3"
  tone-green-edge: "#2f5e3a"
  tone-amber-fill: "#3d2f0c"
  tone-amber-text: "#ffd98a"
  tone-amber-edge: "#6b5420"
  tone-blue-fill: "#0f2c42"
  tone-blue-text: "#a6dcff"
  tone-red-fill: "#3a1a18"
  tone-red-text: "#ffb3aa"
  tone-red-edge: "#6b2a26"
  tone-gray-fill: "#2a2f3c"
  tone-gray-text: "#c3c9d6"
  tone-gray-edge: "#4a5266"
typography:
  display:
    fontFamily: "'Pixelify Sans', ui-monospace, monospace"
    fontSize: "clamp(26px, 2.6vw, 34px)"
    fontWeight: 600
    letterSpacing: "0.01em"
  headline:
    fontFamily: "'Pixelify Sans', ui-monospace, monospace"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "0.01em"
  title:
    fontFamily: "'Pixelify Sans', ui-monospace, monospace"
    fontSize: "16px"
    fontWeight: 600
    letterSpacing: "0.01em"
  nav:
    fontFamily: "'Pixelify Sans', ui-monospace, monospace"
    fontSize: "17px"
    fontWeight: 400
  body:
    fontFamily: "-apple-system, 'SF Pro Text', 'Helvetica Neue', system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.55
    fontFeature: "tnum"
  body-dense:
    fontFamily: "-apple-system, 'SF Pro Text', 'Helvetica Neue', system-ui, sans-serif"
    fontSize: "13.5px"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "'Pixelify Sans', ui-monospace, monospace"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.2
  mono:
    fontFamily: "'JetBrains Mono', ui-monospace, monospace"
    fontSize: "12.5px"
    fontWeight: 400
  mono-map:
    fontFamily: "'JetBrains Mono', ui-monospace, monospace"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.3
rounded:
  none: "0px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  xxl: "48px"
components:
  button:
    backgroundColor: "{colors.raise}"
    textColor: "{colors.ink}"
    typography: "{typography.title}"
    rounded: "{rounded.none}"
    padding: "8px 16px"
    height: "44px"
  button-hover:
    backgroundColor: "{colors.raise-hover}"
  button-primary:
    backgroundColor: "{colors.glow}"
    textColor: "{colors.glow-ink}"
    typography: "{typography.title}"
    rounded: "{rounded.none}"
    padding: "8px 16px"
    height: "44px"
  button-primary-hover:
    backgroundColor: "{colors.glow-hover}"
  needs-you:
    backgroundColor: "{colors.attention}"
    textColor: "{colors.attention-ink}"
    rounded: "{rounded.none}"
    padding: "6px 12px"
  needs-you-hover:
    backgroundColor: "{colors.attention-hover}"
  input:
    backgroundColor: "{colors.ground}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.none}"
    padding: "8px 10px"
    height: "44px"
  nav-item:
    textColor: "{colors.muted}"
    typography: "{typography.nav}"
    rounded: "{rounded.none}"
    padding: "8px 12px"
    height: "44px"
  nav-item-hover:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.ink}"
  nav-item-active:
    backgroundColor: "{colors.raise}"
    textColor: "#ffffff"
  panel:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
    padding: "18px"
  card:
    backgroundColor: "{colors.raise}"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
    padding: "12px"
  pill-green:
    backgroundColor: "{colors.tone-green-fill}"
    textColor: "{colors.tone-green-text}"
    rounded: "{rounded.none}"
    padding: "1px 8px"
  pill-amber:
    backgroundColor: "{colors.tone-amber-fill}"
    textColor: "{colors.tone-amber-text}"
    rounded: "{rounded.none}"
    padding: "1px 8px"
  pill-blue:
    backgroundColor: "{colors.tone-blue-fill}"
    textColor: "{colors.tone-blue-text}"
    rounded: "{rounded.none}"
    padding: "1px 8px"
  pill-red:
    backgroundColor: "{colors.tone-red-fill}"
    textColor: "{colors.tone-red-text}"
    rounded: "{rounded.none}"
    padding: "1px 8px"
  pill-unknown:
    backgroundColor: "{colors.tone-gray-fill}"
    textColor: "{colors.tone-gray-text}"
    rounded: "{rounded.none}"
    padding: "1px 8px"
  count:
    backgroundColor: "{colors.rule-strong}"
    textColor: "{colors.ink}"
    typography: "{typography.mono}"
    rounded: "{rounded.none}"
    padding: "0 6px"
  count-attention:
    backgroundColor: "{colors.attention}"
    textColor: "{colors.attention-ink}"
  room-label:
    backgroundColor: "#1a1d26"
    textColor: "#d5dbe8"
    rounded: "{rounded.none}"
    padding: "1px 8px"
  nametag:
    backgroundColor: "#0b0d12dd"
    textColor: "#eef1f6"
    typography: "{typography.label}"
    rounded: "{rounded.none}"
    padding: "0 6px"
---

<!-- Review state at time of writing: the finish reviewer's last verdict was `fix` (five of seven findings resolved; open: map bubble containment, lounge plate placement, desktop map size, bottom tag clipping). A final batch addressed those and was checked only by the coordinator's own screenshots; it has not been re-reviewed. Nothing here is recorded as reviewer-approved. -->

# Design System: OmniMemo Mission Control

## Overview

**Creative North Star: "The Night Office"**

Mission Control is a lit office floor at night, seen from above. The pixel-art map is the status board: each agent is an original 12x16 sprite standing in the room its verified state belongs to, and when a committed event changes that state it walks there in stepped motion. Everything around the map (rail, header, Tasks, Agents, Approvals, Memory, Events) is the same building's back office: near-black panels, 2px slate rules, square corners, and the pixel face only where something is named.

Density is that of an operator console, not a marketing page. Text sits on dark ground at body 15px, ids and revisions drop to a small monospace, and colour is spent almost entirely on state: monitor-glow blue for focus and selection, amber for what needs a human, green for verified activity, red for faults, and dashed grey for anything unknown. The office carries the delight (floors, lamps, plants, blinking racks); the data views carry clarity and stay plain.

The world is drawn, not decorated. Walls are 4px, rules are 2px, shadows are pixel steps, motion is `steps()`, and nothing has a rounded corner.

**Key Characteristics:**
- Pixel-art night office as the primary view; data views share its palette and square geometry.
- Colour encodes verified state only; unknown is a visible, dashed, desaturated state.
- Three type voices with strict jobs: Pixelify Sans names things, system sans reads, JetBrains Mono identifies.
- Zero radius everywhere; 2px rules for UI, 4px walls for the map.
- All motion is stepped and disappears under reduced motion.

## Colors

A near-black slate ground lit by one cool monitor glow, with warm amber kept for the human's attention and a small state palette of green, blue, red and grey.

### Primary
- **Monitor Glow** (`glow`): focus rings on every control, the selected agent's pixel outline, links, the active filter edge, and the primary button. It is the "you are here" colour; `glow-hover` brightens it on hover and `glow-ink` is the text that sits on it.

### Secondary
- **Attention Amber** (`attention`): full strength only for what waits on the human: the Needs-you button, the Approvals count badge, the skip link; also room overflow counts on the map. `attention-ink` is its text colour, `attention-hover` its hover fill. The dark amber tone family (`tone-amber-*`) marks in-flight states (doing, review, pending) and approval rows.

### Tertiary
- **Verified Green** (`ok`): live connection LED, healthy rack LEDs and their light pools, and the green tone family (`tone-green-*`) for active, ready, approved and done.
- **Fault Red** (`fault`): offline connection, failed rack LED, and the red tone family (`tone-red-*`) for blocked, denied and disconnected.

### Neutral
- **Night Ground** (`ground`): page background and input wells.
- **Panel Slate** (`panel`): panels, board columns, tables, approval rows; also the corridor floor between rooms.
- **Raised Slate** (`raise`, hover `raise-hover`): cards, buttons, the active nav item, portraits, skeleton bars.
- **Slate Rule** (`rule`) and **Strong Rule** (`rule-strong`, hover `rule-hover`): every 2px border, divider and count badge.
- **Paper Ink** (`ink`) for primary text, **Dusk Grey** (`muted`) for labels, metadata and quiet text.
- **Map Void** (`map-void`): the dark frame behind the office map. **Pixel Shadow** (`pixel-shadow`): the near-black used for drop steps, bubble outlines and the bubble tail. **Room Wall** (`room-wall`): the 4px room wall and the dashed unknown edge (`tone-gray-edge`).

### State tones
Each state is a dark fill plus a light text of the same hue, with an optional mid-dark edge for bordered chips: green (active, ready, approved, done), amber (doing, review, pending), blue (todo), red (blocked, denied, disconnected), grey with a dashed edge (unknown, stale).

### Named Rules
**The Signal Colour Rule.** Hue on this surface means a verified state. Do not use green, amber, blue or red for decoration; the floors and furniture of the office use desaturated woods, carpets and slates so that state colour stays readable on top of them.

**The Solid Amber Rule.** A full-strength `attention` fill is reserved for what a human must act on. In-flight work uses the dark amber tone, never the solid fill.

## Typography

**Display Font:** Pixelify Sans (with ui-monospace, monospace), self-hosted via @fontsource, weights 400 and 600
**Body Font:** system sans (-apple-system, SF Pro Text, Helvetica Neue, system-ui)
**Label/Mono Font:** JetBrains Mono (with ui-monospace), self-hosted, weight 400

**Character:** Pixelify Sans is the office's signage: page titles, panel titles, navigation, room labels, agent names, buttons. The system sans does the reading, and JetBrains Mono is the machine's voice for ids, revisions, paths, counts and the quoted text in speech bubbles.

### Hierarchy
- **Display** (600, clamp(26px, 2.6vw, 34px)): the page title in the header. Sign-in uses 32px.
- **Headline** (600, 17-20px, 1.15): the selected agent's name, approval request titles (19px), memory titles (17px), empty-state titles (18px).
- **Title** (600, 15-16px): panel titles in muted colour, board column titles, button labels (16px).
- **Nav** (400, 17px; 15px under 900px): rail navigation.
- **Body** (400, 15px, 1.55, tabular numerals): all prose and table text; dense lists step to 13.5-14.5px. Running prose caps at 68-75ch.
- **Label** (400, 12-13px): room labels, control labels, nametags, tags, map hints, live chip.
- **Mono** (400, 12.5px; 11-11.5px on the map and priority chips): ids, revisions, paths, counts, `kbd`, bubble quotes.

### Named Rules
**The Three Voices Rule.** Pixel names, sans reads, mono identifies. Never set paragraphs in Pixelify Sans and never set ids in the sans.

**The Legible Map Rule.** Text inside the scaled map is sized by the inverse of the map scale, so its rendered size never drops below its 11-13px floor however small the map gets.

## Layout

A left rail (200-224px, 2px right rule) holds the brand, six destinations with counts, and a project/revision/live footer. The work area takes the rest with 24px top padding and `clamp(16px, 2.4vw, 32px)` side padding, sections spaced 16-20px apart. The header line carries the display title, the live chip and a one-line summary on the left; task stat chips and the Needs-you button align right.

The office view stacks the map frame, then the selected-agent panel, then latest events at 1280px and wider; below that the side panel wraps beside or under the map. The map is a fixed 1056x640 world scaled to fit the frame width between 0.6x and 1.5x; below the legible minimum it scrolls sideways with stepped edge fades and a dashed hint, and room jump buttons sit under it.

Tasks is a five-column board (min 200px per column, 12px gaps). Agents and Events use bordered tables and 2px-ruled lists. Under 900px the rail becomes a top bar with wrapping nav, its footer hides, the board becomes one column, and event rows fold into two lines.

Spacing runs on a 4px base: 4, 8, 12, 16, 24, 48, with 18px panel padding as the one off-step. Primary controls are 44px tall; dense in-card selects are 32px.

## Elevation & Depth

The UI chrome is flat: panels, cards and tables separate by tonal steps (`ground` to `panel` to `raise`) and 2px rules, never by shadow. Depth lives only inside the office map, and there it is drawn the way pixel art draws it: a hard 4px drop step of `pixel-shadow` under rooms and furniture, inset bands for wall faces and table tops, a stepped inset vignette inside each room, and banded radial light pools blended with `screen`. The only blurred light is emission: the live LED and the lamp, monitor and rack-LED pools.

### Shadow Vocabulary
- **Pixel drop** (`box-shadow: 0 4px 0 #050608`): rooms, desks and the meeting table on the map; 3px under speech bubbles, 2px under the cable tray.
- **Wall face** (`box-shadow: inset 0 -3px 0 #0e1117, inset 0 -5px 0 #2b3142, inset 0 2px 0 #262c3c`): the three-quarter top wall of each room.
- **Room vignette** (`box-shadow: inset 0 0 0 4px rgb(0 0 0 / 0.16), inset 0 0 0 8px rgb(0 0 0 / 0.1), inset 0 0 0 14px rgb(0 0 0 / 0.06)`): stepped darkening toward room walls.
- **Selection outline** (`filter: drop-shadow` x4 at 2px in `glow`): the pixel outline around the selected agent sprite.
- **LED emission** (`box-shadow: 0 0 8px 1px #4fe07a80`): the live LED only.

### Named Rules
**The Flat Chrome Rule.** Outside the map, nothing casts a shadow. Panels separate by tone and a 2px rule.

**The Pixel Step Rule.** Inside the map, shadows are whole-pixel offsets with no blur. Blur is reserved for light that a source emits.

## Shapes

Every corner is square (0px radius) in the UI and on the map. Borders are 2px solid slate for UI objects and 4px for map room walls, with doorways cut through the walls as 40px gaps edged in light grey. Board columns carry a 4px state-coloured top edge. Dashed borders mean provisional or absent: unknown pills and bubbles, the unknown-crowd room plate, a card being saved, empty states and the map scroll hint. Floors are pure CSS gradient tiles per room (wood, carpet, plum, tech grid, warm planks, checker, grate); sprites and props are inline SVG pixel maps rendered with `image-rendering: pixelated` at integer scales (agent base 12x16 shown at 1x, 2x, 3x or 4x).

## Components

### Buttons
Chunky square keys with pixel labels.
- **Shape:** square (0px), 2px `rule-strong` border, 44px minimum height.
- **Default:** `raise` fill, Pixelify Sans 16px, 8px 16px padding.
- **Primary:** `glow` fill and border with `glow-ink` text; hover brightens to `glow-hover`.
- **Hover / Focus / Active:** border to `rule-hover`, fill to `raise-hover`; focus is the global 2px `glow` outline at 2px offset; active presses down 1px. Disabled drops to 0.45 opacity.
- **Link button:** no border or padding, underlined, inherits text style.
- **Needs you:** solid `attention` block with `attention-ink` semibold text; the only amber-filled button.

### Chips
- **Status pill:** 12px semibold sans, 1px 8px, square, state tone fill plus text; unknown and stale add a 2px dashed `tone-gray-edge` outline inset by 2px.
- **Stat chip:** 2px bordered link in muted text with a mono count; doing and review chips tint their border.
- **Count badge:** mono 12px on `rule-strong`; the Approvals count turns `attention`.
- **Live chip:** pixel 13px with an 8px square LED: green steady when live, amber blinking (stepped, 1s) when connecting, red when offline.
- **Filter toggles:** pressed state takes a `glow` border on `#10202b`.

### Cards / Containers
- **Corner Style:** square (0px).
- **Background:** panels on `panel`, task cards and portraits on `raise`.
- **Shadow Strategy:** none (see Flat Chrome Rule).
- **Border:** 2px `rule` for panels and tables, 2px `rule-strong` for cards; approvals use the amber edge; cards in flight go dashed.
- **Internal Padding:** 18px panels, 12px cards and columns.

### Inputs / Fields
- **Style:** `ground` well, 2px `rule-strong` border, square, 44px tall, 8px 10px padding; placeholder `#7d869c`.
- **Select:** platform widget removed; a down-chevron drawn with two CSS gradients in `muted` (CSP-safe), brightening on hover.
- **Focus:** border turns `glow` with the outline flush (0 offset). Hover lifts the border to `rule-hover`. Disabled selects at 0.55 opacity.

### Navigation
Rail links in Pixelify Sans 17px, 44px tall, muted at rest. Hover fills `panel` and lifts to `ink`; the current page fills `raise` with a 2px `rule-strong` border and white text. Counts align right. Under 900px the rail becomes a wrapping top bar at 15px.

### Agent Sprite
Original 12x16 pixel characters drawn as inline SVG from a palette map: 1px dark outline, per-provider hair and coat colours (Claude terracotta, Codex white and teal, OpenCode charcoal and green, Gemini periwinkle), unknown providers get a stable hashed palette. Two frames alternate at a stepped 1.2s only when the agent is fresh. Unknown agents render at 0.5 opacity in greyscale. Selection is a 2px `glow` pixel outline; keyboard focus a 3px `glow` ring at 4px offset.

### Office Room
A floor-tiled box with a 4px `room-wall` border, a three-quarter wall face along the top, a pixel drop below, and a tab-shaped Pixelify label sitting on the wall with the room's occupant count. Agents walk between rooms with `transform 1.1s steps(9, end)`; reduced motion jumps.

### Speech Bubble and Nametag
Bubbles quote an agent's current signal in mono 11px on a light state-tone fill (green, amber, blue) with a 2px `pixel-shadow` outline, a 3px pixel drop and a square 4px tail; unknown bubbles are grey and dashed. Bubbles anchor toward the room interior so they do not cross walls, truncate to a width cap, and expand when opened. Nametags sit below the sprite in Pixelify 12px on translucent near-black. Crowds of unknown agents collapse into one dashed room plate.

## Do's and Don'ts

### Do:
- **Do** keep every corner square (0px) and every UI rule 2px; room walls are 4px.
- **Do** spend hue only on verified state, and render unknown as grey, dashed and desaturated rather than hiding it.
- **Do** set names, navigation, titles, labels and buttons in Pixelify Sans, prose in the system sans, and ids, revisions, paths and counts in JetBrains Mono.
- **Do** animate with `steps()` timing only, and remove all animation and transition under `prefers-reduced-motion: reduce`.
- **Do** draw sprites and props as original inline SVG pixel maps at integer scales with `image-rendering: pixelated`.
- **Do** bundle every font and asset locally; the page runs under CSP `default-src 'self'`.
- **Do** give every primary control a 44px target and the shared `glow` focus ring.

### Don't:
- **Don't** round corners anywhere, including pills, inputs and bubbles.
- **Don't** put shadows on UI chrome; elevation outside the map is tonal.
- **Don't** blur a shadow on the map; use whole-pixel drop steps, and keep blur for emitted light.
- **Don't** use smooth easing curves for movement; agents and scenery move in steps.
- **Don't** fill anything with full-strength `attention` amber unless it waits on a human.
- **Don't** copy third-party tilesets or characters; pixel art here is original.
- **Don't** load fonts, images or scripts from external origins.

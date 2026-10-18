---
name: OmniMemo Mission Control
description: A floor plan drawn at night, where each agent stands in the room its verified state belongs to.
colors:
  sheet: "#0b1a2e"
  floor: "#10243d"
  raise: "#163152"
  raise-hover: "#1b3a60"
  rule: "#1d3654"
  construction: "#4d6b8f"
  construction-text: "#7391b6"
  line: "#cfe3ff"
  ink: "#e3edf9"
  muted: "#9db2cf"
  placeholder: "#8197b6"
  focus: "#8fd0ff"
  ok: "#5ee08a"
  attention: "#ffc857"
  attention-hover: "#ffd77f"
  attention-ink: "#241900"
  fault: "#ff6b6b"
  unknown: "#8193ab"
  unknown-text: "#a9b8cc"
  tone-ok-fill: "#12351f"
  tone-ok-text: "#9ff0bb"
  tone-amber-fill: "#3a2c09"
  tone-amber-text: "#ffd98a"
  tone-line-fill: "#1a3557"
  tone-line-text: "#d4e6ff"
  tone-red-fill: "#3d1818"
  tone-red-text: "#ffb4b4"
  tone-gray-fill: "#1a2a3f"
typography:
  display:
    fontFamily: "'Barlow Condensed', 'Arial Narrow', sans-serif"
    fontSize: "clamp(26px, 2.2vw, 32px)"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "0.08em"
  headline:
    fontFamily: "'Barlow Condensed', 'Arial Narrow', sans-serif"
    fontSize: "19px"
    fontWeight: 600
    letterSpacing: "0.08em"
  title:
    fontFamily: "'Barlow Condensed', 'Arial Narrow', sans-serif"
    fontSize: "16px"
    fontWeight: 600
    letterSpacing: "0.1em"
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
    fontFeature: "tnum"
  body-table:
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', system-ui, sans-serif"
    fontSize: "13.5px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "'Barlow Condensed', 'Arial Narrow', sans-serif"
    fontSize: "12px"
    fontWeight: 600
    letterSpacing: "0.14em"
  control:
    fontFamily: "'Barlow Condensed', 'Arial Narrow', sans-serif"
    fontSize: "15px"
    fontWeight: 600
    letterSpacing: "0.08em"
  mono:
    fontFamily: "'JetBrains Mono', ui-monospace, monospace"
    fontSize: "12.5px"
    fontWeight: 500
  plan-room:
    fontFamily: "'Barlow Condensed', 'Arial Narrow', sans-serif"
    fontSize: "16px"
    fontWeight: 600
    letterSpacing: "0.12em"
  plan-plate:
    fontFamily: "'Barlow Condensed', 'Arial Narrow', sans-serif"
    fontSize: "13px"
    fontWeight: 600
    letterSpacing: "0.06em"
  plan-dimension:
    fontFamily: "'JetBrains Mono', ui-monospace, monospace"
    fontSize: "10.5px"
    fontWeight: 500
rounded:
  hair: "1px"
  sm: "2px"
  md: "3px"
  badge: "9px"
spacing:
  xxs: "2px"
  xs: "4px"
  sm: "8px"
  md: "12px"
  inset: "14px"
  lg: "16px"
  xl: "20px"
  xxl: "28px"
components:
  button:
    backgroundColor: "{colors.floor}"
    textColor: "{colors.ink}"
    typography: "{typography.control}"
    rounded: "{rounded.md}"
    padding: "6px 16px"
    height: "40px"
  button-hover:
    backgroundColor: "{colors.raise-hover}"
  button-primary:
    backgroundColor: "{colors.line}"
    textColor: "{colors.sheet}"
    typography: "{typography.control}"
    rounded: "{rounded.md}"
    padding: "6px 16px"
    height: "40px"
  button-primary-hover:
    backgroundColor: "#ffffff"
  button-needs-you:
    backgroundColor: "{colors.attention}"
    textColor: "{colors.attention-ink}"
    rounded: "{rounded.md}"
    padding: "4px 14px"
    height: "36px"
  button-needs-you-hover:
    backgroundColor: "{colors.attention-hover}"
  input:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "6px 10px"
    height: "40px"
  nav-item:
    textColor: "{colors.muted}"
    rounded: "{rounded.md}"
    padding: "6px 10px"
    height: "40px"
  nav-item-active:
    backgroundColor: "{colors.floor}"
    textColor: "{colors.line}"
  stat-chip:
    textColor: "{colors.muted}"
    rounded: "{rounded.md}"
    padding: "2px 10px"
    height: "32px"
  panel:
    backgroundColor: "{colors.floor}"
    rounded: "{rounded.md}"
    padding: "12px 14px"
  pill-ok:
    backgroundColor: "{colors.tone-ok-fill}"
    textColor: "{colors.tone-ok-text}"
    rounded: "{rounded.md}"
    padding: "1px 8px"
  pill-amber:
    backgroundColor: "{colors.tone-amber-fill}"
    textColor: "{colors.tone-amber-text}"
    rounded: "{rounded.md}"
    padding: "1px 8px"
  pill-line:
    backgroundColor: "{colors.tone-line-fill}"
    textColor: "{colors.tone-line-text}"
    rounded: "{rounded.md}"
    padding: "1px 8px"
  pill-red:
    backgroundColor: "{colors.tone-red-fill}"
    textColor: "{colors.tone-red-text}"
    rounded: "{rounded.md}"
    padding: "1px 8px"
  pill-unknown:
    backgroundColor: "{colors.tone-gray-fill}"
    textColor: "{colors.unknown-text}"
    rounded: "{rounded.md}"
    padding: "1px 8px"
  count:
    backgroundColor: "{colors.rule}"
    textColor: "{colors.ink}"
    rounded: "{rounded.badge}"
    padding: "0 6px"
  count-attention:
    backgroundColor: "{colors.attention}"
    textColor: "{colors.attention-ink}"
  tag:
    textColor: "{colors.muted}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "0 7px"
---

<!--
Scan-mode record of the shipped Night Floor Plan (2026-10-19), replacing the pixel-art "Night Office". Derived from frontend/src/styles.css, office.css, OfficeMap.tsx, office.ts, Figure.tsx and main.tsx, checked against the .impeccable/review screenshots.
Review state, recorded honestly: the finish reviewer ran two rounds. Round 2 resolved everything except the route callout overlapping its own dashed route; that was then fixed with a solid backing box (sheet fill, amber 1px edge) and NOT re-reviewed. A separate Codex correctness review raised three findings (stale outranked task ownership; routes did not pass through door thresholds; task conflict warnings were keyed by id). All three were fixed afterwards and NOT re-reviewed.
-->

# Design System: OmniMemo Mission Control

## Overview

**Creative North Star: "The Night Floor Plan"**

Mission Control is an architect's drawing set read at night. A prussian sheet carries pale, crisp linework. Rooms are drawn with double-line walls and quarter-arc door swings, and the sheet ends in a legend and a title block. Each agent is a small plan figure standing in the room that its verified state belongs to, so the plan itself is the status board. Everything around the plan (rail, header, schedule tables, event list) uses the same drawing grammar: hairline construction rules, condensed uppercase tags, and tabular figures.

Hue is reserved for meaning. The linework, panels and type are all one blue-grey family. Green, amber and red appear only where a verified state needs them. "Unknown" is never shown as a colour. It is drawn as a diagonal hatch with a dashed outline, so a missing signal looks like a gap in the drawing and not like a status. The one exception to the hue budget is agent identity: each provider's figure has its own fixed body and head colours and its own head silhouette, so you can recognise the provider even when its figure is hatched.

Density is that of an operator's second screen: compact rows, 13 to 14px reading text, and a plan held at the largest scale that stays legible. Motion is rare and meaningful. When a committed event moves an agent to another room, its figure walks through the doorways and leaves a short-lived amber dashed route behind.

**Key Characteristics:**
- Prussian sheet ground with pale linework. Panels are a single step lighter. There are no drop shadows.
- Hue is spent only on verified state (green working/verified, amber needs-a-human or in flight, red fault). Unknown is hatched and dashed.
- Barlow Condensed uppercase with wide tracking is the drawing's lettering. The system sans is used for reading text. JetBrains Mono is used for ids, revisions and minutes.
- Double-line walls, door arcs, dimension lines, a legend and a title block: real drafting devices, used functionally.
- Corners are crisp at 3px. Strokes are 1.5px construction lines and 1px rules.
- One signature motion: the walked amber route.

## Colors

A single cold blue family for ground, linework and type, plus three state hues and a hatch for "unknown".

### Primary
- **Drafting Line** (line): the pale ink of the drawing. Used for walls, room tags, headings, the title block, the selected name plate fill, and the primary button. It is the brightest non-state colour, and it marks structure and emphasis rather than action.

### Secondary
- **Signal Amber** (attention): needs a human, or in flight. Used for the Needs-you button, the attention count, the Approvals room tag when someone is asking, the asking agent's plate edge and signal text, the walked route, the approval card border, and the P1 priority. Text on amber is **Amber Ink** (attention-ink). **Amber Lift** (attention-hover) is the hover state only.

### Tertiary
- **Verified Green** (ok): working or verified. Used for the status pip, the context meter fill, the "live" state, healthy rack LEDs, and the legend key.
- **Fault Red** (fault): faults, offline status and P0 priority. Used for the rack LED for an unavailable service and the critical context meter.

### Neutral
- **Prussian Sheet** (sheet): page ground, the plan sheet, input wells, and the knock-out colour inside double walls and behind route callouts.
- **Plan Panel** (floor): room floors, panels, tables and default buttons.
- **Raised Panel** (raise) / **Raised Hover** (raise-hover): selected table rows, pressed filters and skeleton bars, plus the hover fill on buttons.
- **Rule** (rule): 1px dividers between rows, and the count badge ground.
- **Construction Line** (construction): 1.5px borders on panels, controls, the rail and the topbar; door swings and furniture on the plan.
- **Construction Text** (construction-text): corridor labels on the plan.
- **Ink** (ink): body text. **Muted** (muted): secondary text, table heads and fact keys. **Placeholder** (placeholder): input placeholders.
- **Focus Blue** (focus): the focus ring only.
- **Unknown Grey** (unknown) / **Unknown Text** (unknown-text): the stroke of the hatch and the dashed outline, and text on unknown pills and plates.

### Tones (pill fills)
Each state pill is a dark fill with light text in the same hue: tone-ok, tone-amber, tone-line (neutral/todo), tone-red. Unknown and stale pills layer the 45° hatch over tone-gray-fill, with an inset Unknown Grey edge and a dashed outline.

### Named Rules
**The Hue Is Evidence Rule.** Green, amber and red appear only when a verified state calls for them. Structure, emphasis and navigation use the blue-grey family. Provider figure colours are identity, not state, and they never tint UI chrome.

**The Hatched Unknown Rule.** Unknown or stale is never a colour. It is a diagonal hatch (45°, Unknown Grey) with a dashed edge, and it is applied in the same way to pills, figures, plates, legend keys and LEDs.

## Typography

**Display Font:** Barlow Condensed 600 (with Arial Narrow, sans-serif)
**Body Font:** system sans (-apple-system, SF Pro Text, Helvetica Neue, system-ui)
**Label/Mono Font:** JetBrains Mono 400/500 (with ui-monospace)

**Character:** Condensed, tracked capitals are the draughtsman's lettering for room tags, titles, navigation, buttons and table heads. The quiet system sans does all the reading, and the mono font sets every number that is an identifier or a measurement. The whole body uses tabular numerals.

### Hierarchy
- **Display** (600, clamp(26px, 2.2vw, 32px), line-height 1, 0.08em, uppercase): the one page title in the topbar.
- **Headline** (600, 19–20px): the selected agent's name, empty-state titles, and approval and memory titles. Approval and memory titles drop uppercase and use 0.02em tracking because they are sentences.
- **Title** (600, 16px, 0.1em, uppercase): panel heads, rail navigation, and the Needs-you button.
- **Body** (400, 14px/1.5, tabular-nums): the default. Tables and event rows use 13.5px, and dense tables use 13px. Running copy is capped at 72–75ch.
- **Label** (600, 12px, 0.14em, uppercase, condensed): table heads, fact keys, tags, and group heads at 14px.
- **Control** (600, 15px, 0.08em, uppercase, condensed): every button.
- **Mono** (500, 12.5–13px): ids, revisions, priorities, minutes, counts (11.5px) and the live chip.
- **Plan lettering**: room tag 600 16px at 0.12em; name plate 600 13px at 0.06em; corridor label 600 10px at 0.24em knocked out of the linework; signal line in sans at 11px; dimension figures in mono 500 at 10.5px; title-block revision 600 at 22px.

### Named Rules
**The Lettering Rule.** Condensed uppercase is lettering for things that name or label a place, a column or an action. Sentences are always set in the system sans, sentence case.

**The Measured Number Rule.** Any number that identifies or measures (revision, id, minutes, priority, count) is set in mono. Counts in prose stay in the sans.

## Layout

The shell is a 216px sticky left rail plus a fluid work area padded at clamp(16px, 2vw, 28px). A 72px topbar holds the title, live chip, presence summary, and the Todo/Doing/Review stat chips with the amber Needs-you button pushed to the right. A 1.5px construction rule closes the topbar.

The Office view is a two-column grid: the plan sheet is minmax(0, 1fr), and the right column is 320–372px, holding the agent schedule, the selected agent's details and the latest events, stacked with 16px gaps. The plan is a fixed 840×790 SVG in plan units, scaled as a whole to at most 100vh − 128px, with a minimum width of 620px. Rooms, slots, doors and corridors live in that coordinate space, never in CSS.

Rhythm: 16px between panels, 14px panel inset, 8px vertical padding in table rows (5px in dense tables and task rows), and 8–12px gaps inside rows.

Responsive:
- **≤1180px**: the right column drops below the plan as an auto-fit grid with 300px minimum columns.
- **≤900px**: the rail becomes a wrapping top bar, rail metadata hides, event rows fold into two lines, and approvals stack.
- **≤700px**: the plan keeps a 760px legible width and scrolls sideways, opened at the room that matters, with a scroll cue, a compact state key and a right-edge fade. Task rows fold into a title line over a priority/owner/status line.

## Elevation & Depth

The system is flat. Depth comes only from the tonal step from sheet to floor to raise and from drawn lines. No element casts a shadow. `box-shadow` appears only as an inset hairline, so it is a drawn line and not a lift.

### Shadow Vocabulary
- **Active rail item** (`box-shadow: inset 0 0 0 1.5px var(--construction)`): outlines the current page in the rail.
- **Selected row** (`box-shadow: inset 0 1px 0 var(--line), inset 0 -1px 0 var(--line)`): pale rules above and below a selected schedule row.
- **Asking / unknown pill edge** (`box-shadow: inset 0 0 0 1.5px var(--attention | --unknown)`): the pill outline for attention and hatched states.

### Named Rules
**The Drawn Depth Rule.** If something needs to stand forward, draw a line or step the tone. Never blur a shadow under it.

## Shapes

Corners are crisp: 3px on every panel, control, chip, pill, tag and kbd; 2px on skeleton bars; 1px on the context meter and plan furniture. The only round forms are functional: the count badge capsule (9px), LEDs, status pips and legend dots (50%), and the scrollbar thumb (6px).

Lines carry the form language. Panel and control borders are 1.5px construction lines, row dividers are 1px rule, and dashed borders mean empty or unknown. On the plan, walls are double lines (a 7-unit pale stroke with a 4-unit sheet stroke cut through it), doors are a 30-unit gap with a quarter-arc swing into the room, and the age of an agent's signal is shown as a dimension line under its figure. That line's length grows on a log scale with the minutes since the last signal, capped at 99m+.

Agent figures are a head over a shoulder arc, 24 plan units tall. Each provider has its own head silhouette: Claude round, Codex square, OpenCode hex, Gemini drop, Cursor triangle. Unknown providers get a stable fallback colour chosen from their name.

## Components

### Buttons
Condensed capitals on drawn edges. Firm, never glossy.
- **Shape:** crisp 3px corners, with a 1.5px construction border and a minimum height of 40px.
- **Default:** a Plan Panel fill with 6px 16px padding and Control lettering.
- **Hover / Focus:** a Raised Hover fill with the border lifting to Drafting Line over a 160ms ease-out transition. Pressing nudges the button down 1px. Focus is a 2px Focus Blue outline with a 2px offset. Disabled buttons drop to 45% opacity.
- **Primary:** a Drafting Line fill with Sheet text, turning white on hover.
- **Needs you:** an amber fill with Amber Ink text, 36px tall. This is the one amber call to action in the header.
- **Link button:** sans text with a construction-coloured underline at a 3px offset.

### Chips
- **Stat chip:** a 32px outlined chip with a condensed label and a mono figure. The Doing and Review chips use a darker green or amber edge.
- **Live chip:** a mono label with a 7px LED, drawn in currentColor. While connecting, the LED blinks at 1.2s.
- **Count badge:** a mono 11.5px capsule on Rule. It turns amber when a human is needed.
- **Tag:** a 1px construction outline with Label lettering.

### State Pills
- **Style:** 3px corners, 1px 8px padding, 600 12px/18px sans. Each pill is a dark fill with light text in one hue.
- **Mapping:** working, active, ready, done and approved are green; doing, review, blocked, pending, unverified and in flight are amber; todo, waiting and neutral are line-blue; denied, disconnected and offline are red; stale and unknown are hatched with a dashed outline. A pill for a human-attention state adds an inset 1.5px amber edge.

### Cards / Containers
- **Corner Style:** 3px.
- **Background:** Plan Panel on the Prussian Sheet.
- **Shadow Strategy:** none (see Elevation & Depth).
- **Border:** a 1.5px construction line. Approval cards use a 1.5px amber border. Empty states and the map's empty notice use a dashed border.
- **Internal Padding:** heads are 10px 14px with a closing construction rule, bodies are 12px 14px, and footers are 8px 14px 10px over a 1px rule.

### Inputs / Fields
- **Style:** a Prussian Sheet well with a 1.5px construction border, 3px corners and a 40px height. Selects have a drawn two-stroke chevron in Muted. Selects inside the task table sit transparent and borderless until hovered or focused.
- **Focus:** the border turns Focus Blue, along with the global 2px focus outline.
- **Disabled:** 55% opacity with the not-allowed cursor.

### Navigation
- **Rail:** the logo (a drawn room with a door swing and one occupant, all in Drafting Line) and the wordmark at 600 20px condensed, then nav items in 600 16px condensed capitals in Muted. On hover an item fills with Plan Panel and turns to Drafting Line. The current page uses the same fill plus an inset construction outline. Counts sit at the right edge. A footer block lists project, revision and live status, with green, amber or red marking connection state.
- **Mobile:** below 900px the rail becomes a wrapping top row and the footer block hides.

### Schedule Table
The shared tabular grammar used by the office schedule, Agents and Tasks.
- Condensed 12px tracked heads over a 1.5px construction rule, 1px rule dividers between rows, and a 3% Drafting Line hover tint.
- Numbers are right-aligned. Every agent cell pairs the agent's figure mark with its printed name.
- Stale and offline rows drop to Muted.
- Tasks group by status. Each group head is 14px condensed in the hue of that status, with a count. A conflict row is an amber tone band.

### Floor Plan (signature)
- **Rooms:** Plan Panel floors inside double-line walls. Each room has a tag (name plus live occupancy) at its top-left. The Approvals room tag turns amber when someone is asking.
- **Agent personal furniture:** a figure, a status pip (green solid, amber solid, amber ring for in flight, hatched dashed for unknown), a 76×18 name plate, a one-line signal, and the signal-age dimension line.
- **Selection:** the name plate fills with Drafting Line and gains a dotted ring. Focus adds a 2.5-unit Focus Blue ring.
- **Fresh signal:** the pip swells to 1.6× once every 2.4s.
- **Sheet furniture:** a legend (state keys plus 1m/10m/1h dimension samples) and a title block with project, drawing, sheet, status and a large revision number. The server room rack shows MongoDB and Redis health as LEDs.
- **Walked route:** a 2-unit amber dashed line (7 5) with an arrowhead, routed through door thresholds and along the corridors. The figure walks the route over min(2400ms, 600 + 2.2 × length) with cubic-bezier(0.22, 1, 0.36, 1). The line holds for 70% of 6s and then fades. A mono callout sits on a solid sheet box with an amber 1px edge on the longest corridor run, trimmed to fit. With reduced motion, the figure jumps and the route stays drawn for the same 6s.

## Do's and Don'ts

### Do:
- **Do** keep every colour on the CSS custom properties in `styles.css`. A new state reuses an existing tone pair; it never introduces a new hue.
- **Do** show unknown or stale with the 45° hatch and a dashed edge, everywhere it appears.
- **Do** set room tags, headings, navigation, buttons and table heads in Barlow Condensed 600 uppercase with 0.06–0.24em tracking; reading text in the system sans; and ids, revisions and minutes in JetBrains Mono.
- **Do** draw borders as 1.5px construction lines and row dividers as 1px rule, with 3px corners.
- **Do** place anything new on the plan in plan units inside the 840×790 sheet, and route movement through doorways.
- **Do** print the agent's name next to every figure mark. The mark is decorative.
- **Do** honour `prefers-reduced-motion`: figures jump and transitions stop, but state stays readable.

### Don't:
- **Don't** add drop shadows, glows or blur. Depth is a tonal step or a drawn line.
- **Don't** spend green, amber or red on decoration, navigation or emphasis that isn't state.
- **Don't** give unknown its own colour, or show it as a grey "status".
- **Don't** reintroduce the pixel world: no pixel fonts, sprites, stepped sprite animation, square-pixel walls or 0px corners.
- **Don't** set sentences in condensed capitals, or numbers that identify or measure in the sans.
- **Don't** number rooms or add decorative sequence numbers. A room tag carries its name and its live occupancy.

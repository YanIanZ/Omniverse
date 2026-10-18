---
version: 1
slug: "frontend-src-app-tsx"
primary_target: "frontend/src/App.tsx"
related_targets: []
---

# Mission Control (frontend/src)

Mode: Operate. Audience: open-source developers running several coding agents locally, both as an always-open second screen and as a quick check-in. Job: see at a glance what each agent is really doing, hand work between agents, answer approval requests. Owner asked for a total redesign (2026-10-19); kept: agent-as-place map, per-provider agent figures, dark theme. Pain points to fix: slow scanning, too dark/flat, heavy task board.

## Direction contract

THESIS: Mission Control is a drawn floor plan at night; each agent stands in the room its verified state belongs to, and the plan is the status board. Refuses both the status-pill table with a mascot and the cozy game office.

OWN-WORLD: Architect's drawing set on prussian ground #0b1a2e, plan panels #10243d, crisp pale linework #cfe3ff, dim construction lines #4d6b8f. State only: green #5ee08a working/verified, amber #ffc857 needs a human or in flight, red #ff6b6b fault, unknown = diagonal hatch in #8193ab with dashed outline. Barlow Condensed uppercase tracked for room tags, nav, titles; system sans reads; JetBrains Mono for ids, revisions, minutes. Double-line walls, quarter-arc door swings, title block, legend. 2-4px radii, no shadows.

STORY: The visitor reads who is where on the plan, sees name plate plus one-line signal under every figure, notices the amber route of an agent that just moved, selects an agent to read source, task and last signal, approves requests, and edits tasks in a compact schedule table.

FIRST VIEWPORT: Left rail (Office, Tasks, Agents, Approvals, Memory, Events, Needs-you count, project/revision/live footer). Header: title, live chip, presence summary, Todo/Doing/Review chips, amber Needs-you button. Work area: the floor plan at its largest legible size with room tags (name plus live occupancy; no room numbers, per the craft-floor rule that sequence numbers must carry information), title block and legend inside the sheet; right column: Agent schedule table, selected agent detail, latest events.

FORM: Night Floor Plan, candidate 4 of 7 on the ordered list (assigned by the roll). Raises: fixed personal furniture per agent (name plate + signal line); one drawing scale across states; signal age as a dimension line whose length is minutes since last signal; tasks and events in a strict tabular grid. seed:e9fc068376c21908

Signature move: on a committed event an agent's figure travels along an amber dashed route through the doorways to its new room; reduced motion jumps and keeps the route line briefly.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

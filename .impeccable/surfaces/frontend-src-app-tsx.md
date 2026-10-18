---
version: 1
slug: "frontend-src-app-tsx"
primary_target: "frontend/src/App.tsx"
related_targets: []
---

# Mission Control (frontend/src)

Mode: Operate (visual-first, per owner). Audience: open-source developers running several coding agents locally. Job: see at a glance what each agent is really doing, hand work between agents, answer approval requests.

## Direction contract

THESIS: Agent state is a place. Each verified signal moves an agent into a room of a pixel-art office, so the map itself is the status board. Refuses the category default of status pills in a table with a decorative mascot.

OWN-WORLD: Night office seen from above. Ground #0d0f14, panels #12151c, 2px slate rules #1f2430/#2b3142, monitor-glow #7fd4ff for focus and selection, attention amber #ffcf5c, verified green #4fe07a, unknown slate. Pixelify Sans for headings, navigation and room labels; system sans for body; JetBrains Mono only for ids, revisions and paths. Original 12x16 agent sprites per provider, 4px pixel walls, floors per room.

STORY: The visitor sees who is present, where each agent is, and what it is quoting; clicks an agent to read source, task and last signal; approves or denies requests; moves tasks on the board.

FIRST VIEWPORT: Left rail navigation (Office, Tasks, Agents, Approvals, Memory, Events) with a Needs-you count. Header with live state and task counts. The office map fills the work area at its largest legible scale; a right panel shows the selected agent and the latest events.

FORM: Owner-pinned world from the reference video and the Claude Design canvas "OmniMemo Pixel Office" (https://claude.ai/artifact/5RLoD3W6igdYgowyWVpv1r); concept-seed was rolled afterwards for the record (operate mode); the owner-pinned direction still governs over the assigned candidate. seed:7de75bf1c4f2fd23

Signature move: on a committed event an agent walks (stepped motion) to the room its new state belongs to; reduced motion jumps.

FINISH: unreviewed and undocumented is unfinished; the finish reviewer and documenter close the run.

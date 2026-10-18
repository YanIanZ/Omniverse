# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Open-source developers who install OmniMemo from the public repository on their own Mac and run several coding agents (Claude Code, Codex, OpenCode, Gemini CLI) against the same projects. They open Mission Control in a local browser to see which agents are present, what each is doing, and to hand work between them.

## Product Purpose

OmniMemo gives coding agents a shared, project-scoped memory and handoff layer (Swift core, MCP stdio, `om` CLI, MongoDB, optional Redis). Mission Control is the local web view of that layer: success is a developer trusting at a glance what their agents are really doing, without reading logs.

## Positioning

Status is shown only from verified signals (official host hooks, MCP first use, CLI calls, committed MongoDB events). Unknown presence is shown as unknown. No agent is launched or simulated to animate the view.

## Operating Context

Runs on loopback (`om office`, default 127.0.0.1:8787) next to terminals and IDEs where agents work. One Vapor server per data directory, React UI served as static files. Hosts integrate differently: Claude Code via SessionStart/UserPromptSubmit/SessionEnd hooks; Codex via hooks.json; OpenCode via plugins; others via MCP or manual `om` commands.

## Capabilities and Constraints

- Real data: agent sessions (ready/active/disconnected/unknown), tasks with revision-checked status (todo/doing/review/done/blocked), ordered events, memory search, storage health.
- Mission Control is visual-first: the office floor plan is the primary view; detailed data lives in other views.
- CSP `default-src 'self'`: no external fonts, scripts or images at runtime; assets must be bundled.
- No database credentials or raw prompts in the browser bundle or payloads.
- Approvals record human decisions only; they never trigger Git pushes.
- Open decisions: multi-user/LAN access, remote deployment.

## Brand Commitments

- Name: OmniMemo. Visual direction chosen by the owner (2026-10-19, replacing the earlier pixel-art office): "Night Floor Plan", an architect's drawing of the office at night where each agent stands in the room of its verified state. Kept from before: agent-as-place map, a distinct figure per provider, dark theme. All drawing is original.

## Evidence on Hand

Real test results in `docs/VALIDATION.md`. No users, testimonials, benchmarks or usage numbers exist; never fabricate them.

## Product Principles

1. Correct before pretty: every visual state maps to a verified signal.
2. Unknown is a first-class state, never hidden or guessed.
3. Local-first and private: nothing leaves the machine.
4. Delight lives in the office, clarity lives in the data views.

## Accessibility & Inclusion

Keyboard navigation, reduced-motion support, text alternatives for every sprite and status, WCAG AA contrast for text.

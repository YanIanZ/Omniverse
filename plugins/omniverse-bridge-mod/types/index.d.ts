/** One agent card as `om runtime sessions` prints it (fields this mod reads). */
export type AgentCard = {
  display_slug: string
  status: string
  client?: string
  model?: string
  session_id?: string
  last_seen?: string
  tool_category?: string
  task?: { id: string; title: string }
  progress: { kind: string; percent?: number; completed?: number; total?: number }
  context: { measurement: string; level: string; used_percent?: number }
  /** Set on a subagent: the session that spawned it, and its type. */
  spawned_by?: string
  agent_type?: string
}

/** One OmniMemo record an agent saved (`om memory list`), cut down to what the pane prints. */
export type AgentRecord = { id: string; title: string; kind: string; state: string; created_at: string; lines: string[] }

declare module 'claude-code' {
  interface PluginState {
    'omniverse-bridge': { agents: AgentCard[]; report: string; self: string; focus: string; records: AgentRecord[] }
  }
}

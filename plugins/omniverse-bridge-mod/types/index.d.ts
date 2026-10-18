/** One agent card as `om runtime sessions` prints it (fields this mod reads). */
export type AgentCard = {
  display_slug: string
  status: string
  task?: { id: string; title: string }
  progress: { kind: string; percent?: number; completed?: number; total?: number }
  context: { measurement: string; level: string; used_percent?: number }
}

declare module 'claude-code' {
  interface PluginState {
    'omniverse-bridge': { agents: AgentCard[]; report: string }
  }
}

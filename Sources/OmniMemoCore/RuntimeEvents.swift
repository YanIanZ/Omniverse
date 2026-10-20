import Foundation

/// Normalized runtime event from an adapter (hooks, plugin, managed app-server).
/// Contract: docs/RUNTIME_EVENTS.md. Telemetry carries categories, never prompts,
/// tool arguments, source text or secrets.
public struct RuntimeEventInput: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case eventID = "event_id"
    case source, provider, sequence, status, metadata
    case externalSessionID = "external_session_id"
    case workspaceID = "workspace_id"
    case eventType = "event_type"
    case occurredAt = "occurred_at"
    case receivedAt = "received_at"
    case modelID = "model_id"
    case taskID = "task_id"
    case milestoneID = "milestone_id"
    case sourceConfidence = "source_confidence"
  }
  public var schemaVersion: String
  public var eventID: String
  public var source: String
  public var provider: String
  public var externalSessionID: String
  public var workspaceID: String?
  public var eventType: String
  public var occurredAt: String
  public var receivedAt: String?
  public var sequence: Int?
  public var modelID: String?
  public var taskID: String?
  public var milestoneID: String?
  public var status: String?
  public var sourceConfidence: String
  public var metadata: [String: MetaValue]?

  public init(
    eventID: String = UUID().uuidString.lowercased(), source: String, provider: String,
    externalSessionID: String, eventType: String, occurredAt: String = nowISO(),
    modelID: String? = nil, taskID: String? = nil, milestoneID: String? = nil,
    sourceConfidence: String = "observed", metadata: [String: MetaValue]? = nil
  ) {
    schemaVersion = "1"
    self.eventID = eventID
    self.source = source
    self.provider = provider
    self.externalSessionID = externalSessionID
    self.eventType = eventType
    self.occurredAt = occurredAt
    self.modelID = modelID
    self.taskID = taskID
    self.milestoneID = milestoneID
    self.sourceConfidence = sourceConfidence
    self.metadata = metadata
  }

  public static let providers = ["claude", "codex", "opencode", "gemini"]
  public static let eventTypes = [
    "session.started", "session.resumed", "session.ended", "model.changed", "prompt.received",
    "tool.started", "tool.succeeded", "tool.failed", "turn.completed", "turn.failed",
    "task.assigned", "task.blocked", "milestone.verified", "approval.requested", "heartbeat",
  ]
  /// Metadata keys an adapter may send; anything else is rejected rather than stored.
  public static let metadataKeys: Set<String> = [
    "tool_category", "error_kind", "observability", "title", "client_version", "turn_id",
    "reason", "permission_mode", "spawned_by", "agent_type",
  ]
}

/// JSON scalar (string, number, bool, null), as the event schema allows in metadata.
public enum MetaValue: Codable, Sendable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case null
  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null }
    else if let b = try? c.decode(Bool.self) { self = .bool(b) }
    else if let n = try? c.decode(Double.self) { self = .number(n) }
    else { self = .string(try c.decode(String.self)) }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let s): try c.encode(s)
    case .number(let n): try c.encode(n)
    case .bool(let b): try c.encode(b)
    case .null: try c.encodeNil()
    }
  }
  public var text: String? {
    switch self {
    case .string(let s): return s
    case .number(let n): return String(n)
    case .bool(let b): return String(b)
    case .null: return nil
    }
  }
}

public struct IngestResult: Codable, Sendable {
  public var accepted: Bool
  public var duplicate: Bool
  public var cursor: Int?
  public var status: String?
}

/// Verified-progress milestone. Progress is the verified share of total weight.
public struct Milestone: Codable, Sendable, Equatable {
  enum CodingKeys: String, CodingKey {
    case id, title, weight, verified, evidence
    case verifiedAt = "verified_at"
  }
  public var id: String
  public var title: String
  public var weight: Int
  public var verified: Bool
  public var evidence: String?
  public var verifiedAt: String?
}

public struct Progress: Codable, Sendable, Equatable {
  /// `determinate` only with defined milestones; otherwise `indeterminate` with no number.
  public var kind: String
  public var percent: Int?
  public var completed: Int?
  public var total: Int?
  public static func of(_ milestones: [Milestone]?) -> Progress {
    guard let milestones, !milestones.isEmpty else { return Progress(kind: "indeterminate") }
    let total = milestones.reduce(0) { $0 + max(1, $1.weight) }
    let done = milestones.filter(\.verified).reduce(0) { $0 + max(1, $1.weight) }
    return Progress(
      kind: "determinate", percent: Int((Double(done) * 100 / Double(total)).rounded(.down)),
      completed: milestones.filter(\.verified).count, total: milestones.count)
  }
}

public enum RuntimeMapping {
  /// Reduces a host tool name to a category; arguments are never inspected.
  /// Every value `toolCategory` can return: the only tool detail a session ever stores.
  public static let toolCategories: Set<String> = [
    "mcp", "file_edit", "file_read", "search", "shell", "web", "subagent", "question", "skill",
    "planning", "other", "unknown",
  ]

  public static func toolCategory(_ name: String?) -> String {
    let n = (name ?? "").lowercased()
    if n.hasPrefix("mcp__") || n.hasPrefix("mcp.") { return "mcp" }
    switch n {
    case "edit", "write", "multiedit", "notebookedit", "apply_patch", "patch", "write_file",
      "replace", "edit_file", "str_replace":
      return "file_edit"
    case "read", "read_file", "notebookread", "view", "read_many_files": return "file_read"
    case "glob", "grep", "ls", "list", "search", "search_file_content", "codesearch", "find":
      return "search"
    case "bash", "shell", "exec_command", "run_shell_command", "local_shell", "terminal", "execute":
      return "shell"
    case "webfetch", "websearch", "web_fetch", "google_web_search", "fetch": return "web"
    case "task", "agent", "subagent": return "subagent"
    case "question", "askuserquestion", "ask_user": return "question"
    case "skill": return "skill"
    case "todowrite", "todoread", "update_plan", "write_todos": return "planning"
    default: return n.isEmpty ? "unknown" : "other"
    }
  }

  /// Office status a runtime event proves; nil means the event does not change status.
  public static func status(for eventType: String) -> String? {
    switch eventType {
    case "session.started", "session.resumed", "turn.completed", "turn.failed": return "waiting"
    case "prompt.received", "tool.started", "tool.succeeded", "tool.failed": return "working"
    case "approval.requested", "task.blocked": return "blocked"
    case "session.ended": return "offline"
    default: return nil
    }
  }

  /// Codex app-server thread item type -> tool category; nil for items that are not tool calls.
  public static func codexItemCategory(_ type: String) -> String? {
    switch type {
    case "commandExecution": return "shell"
    case "fileChange": return "file_edit"
    case "mcpToolCall": return "mcp"
    case "webSearch": return "web"
    case "collabAgentToolCall", "subAgentActivity": return "subagent"
    case "dynamicToolCall", "imageView", "imageGeneration": return "other"
    default: return nil
    }
  }

  /// Context occupancy from Codex `thread/tokenUsage/updated`: the last request's input tokens
  /// over the model window. Totals are lifetime usage and are never used for this.
  public static func codexContextPercent(lastInputTokens: Int, window: Int?) -> Double? {
    guard let window, window > 0, lastInputTokens >= 0 else { return nil }
    return min(100, Double(lastInputTokens) * 100 / Double(window))
  }

  /// Statuses written by `om wake` before runtime events existed.
  public static func legacy(_ status: String) -> String {
    switch status {
    case "ready": return "waiting"
    case "active": return "working"
    case "disconnected": return "offline"
    default: return status
    }
  }
}

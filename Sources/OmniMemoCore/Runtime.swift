import Foundation
import MongoKitten

/// One observed agent session. Status comes only from real hook, plugin, MCP or managed
/// app-server signals: waiting, working, blocked, offline; `stale` is derived from silence.
public struct AgentSession: Codable, Sendable {
  enum CodingKeys: String, CodingKey, CaseIterable {
    case agent, status, source, model, observability, title
    case sessionID = "session_id"
    case firstSeen = "first_seen"
    case lastSeen = "last_seen"
    case runtimeID = "runtime_id"
    case lastEvent = "last_event"
    case lastEventAt = "last_event_at"
    case toolCategory = "tool_category"
    case eventCount = "event_count"
    case lastSequence = "last_sequence"
    case taskID = "task_id"
    case contextUsedPercent = "context_used_percent"
    case contextWindowTokens = "context_window_tokens"
    case contextObservedAt = "context_observed_at"
    case parentSessionID = "parent_session_id"
    case childSessionID = "child_session_id"
    case rolloverState = "rollover_state"
    case revision
  }
  public var agent: String
  public var sessionID: String
  public var status: String
  public var source: String
  public var firstSeen: String
  public var lastSeen: String
  /// Internal identity; the client or model name is never the identity.
  public var runtimeID: String? = nil
  /// Only as reported by adapter metadata.
  public var model: String? = nil
  /// `managed` (OmniMemo owns the process) or `passive` (hooks/plugins only).
  public var observability: String? = nil
  public var lastEvent: String? = nil
  public var lastEventAt: String? = nil
  public var toolCategory: String? = nil
  /// Short task title, stored only with user consent.
  public var title: String? = nil
  public var eventCount: Int? = nil
  public var lastSequence: Int? = nil
  public var taskID: String? = nil
  /// Active context-window occupancy as the host reported it (never lifetime tokens).
  public var contextUsedPercent: Double? = nil
  public var contextWindowTokens: Int? = nil
  public var contextObservedAt: String? = nil
  /// Fresh-session lineage; `rolloverState` follows the v2.4 state machine on the parent.
  public var parentSessionID: String? = nil
  public var childSessionID: String? = nil
  public var rolloverState: String? = nil
  /// Write counter for compare-and-set saves; nil on sessions stored before it existed.
  public var revision: Int? = nil
}

public struct TaskRecord: Codable, Sendable, Equatable {
  enum CodingKeys: String, CodingKey {
    case id, title, status, revision, owner, priority, milestones
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
  public var id: String
  public var title: String
  public var status: String
  public var revision: Int
  public var owner: String?
  /// P0 (urgent) ... P3; older records without a priority read as P2.
  public var priority: String?
  public var createdAt: String
  public var updatedAt: String
  /// Verified-progress plan; empty or absent means progress is indeterminate.
  public var milestones: [Milestone]? = nil
  public static let statuses = ["todo", "doing", "review", "done", "blocked"]
  public static let priorities = ["P0", "P1", "P2", "P3"]
}

/// A request for a human decision. Recording a decision never performs the action.
public struct ApprovalRecord: Codable, Sendable, Equatable {
  enum CodingKeys: String, CodingKey {
    case id, action, reason, status, revision
    case requestedBy = "requested_by"
    case createdAt = "created_at"
    case decidedAt = "decided_at"
  }
  public var id: String
  public var action: String
  public var reason: String
  public var requestedBy: String
  public var status: String
  public var revision: Int
  public var createdAt: String
  public var decidedAt: String?
}

/// Versioned WebSocket/REST event envelope; committed to MongoDB before any broadcast.
public struct RuntimeEvent: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case v, type, revision, timestamp, data
    case eventID = "event_id"
    case projectID = "project_id"
    case entityID = "entity_id"
  }
  public var v = 1
  public var eventID: String
  public var projectID: String
  public var type: String
  public var entityID: String
  public var revision: Int
  public var timestamp: String
  public var data: [String: String]
}

extension MemoryStore {
  /// A session without a signal for this long is shown as `unknown`, never `idle`.
  public static let presenceTimeout: TimeInterval = 600
  private static let eventHistory = 1000

  /// Maps a host-reported client name (MCP clientInfo, hook argument) to a stable provider label.
  public static func provider(_ raw: String) -> String {
    let name = raw.lowercased()
    for known in ["claude", "codex", "opencode", "gemini", "cursor", "copilot"] where name.contains(known) {
      return known
    }
    let cleaned = name.replacingOccurrences(of: "[^a-z0-9._-]", with: "-", options: .regularExpression)
    return cleaned.isEmpty ? "agent" : String(cleaned.prefix(32))
  }

  public func ensureRuntimeIndexes() async throws {
    if runtimeIndexesReady { return }
    do {
      try await backend.prepareRuntime(project: binding.id)
      runtimeIndexesReady = true
    } catch { throw Self.safeError(error) }
  }

  static func label(_ value: String, _ name: String) throws -> String {
    guard (1...128).contains(value.utf8.count),
      value.range(of: "^[A-Za-z0-9._:-]+$", options: .regularExpression) != nil
    else { throw MemoError.invalid("invalid \(name)") }
    // MongoDB keys sessions as project:agent:session; a colon in the agent would let
    // agent "a:b" + session "c" and agent "a" + session "b:c" share one document.
    if name == "agent", value.contains(":") { throw MemoError.invalid("invalid agent") }
    return value
  }

  /// Revision-checked read-modify-write of one session, retried when another writer (a hook in
  /// another process, the status line, a heartbeat) saved in between. `change` receives the stored
  /// session or nil and returns the state to save; it must not have side effects.
  @discardableResult
  func updateSession(
    agent: String, session: String, _ change: (AgentSession?) throws -> AgentSession
  ) async throws -> AgentSession {
    for attempt in 0..<12 {
      // Random backoff spreads writers that collided, so each retry has a fair chance to win.
      if attempt > 0 { try await Task.sleep(nanoseconds: UInt64.random(in: 1...20) * 1_000_000) }
      let current = try await backend.session(project: binding.id, agent: agent, session: session)
      var next = try change(current)
      next.revision = current?.revision
      if try await backend.save(session: next, project: binding.id) {
        next.revision = (current?.revision ?? 0) + 1
        return next
      }
    }
    throw MemoError.revisionConflict
  }

  // MARK: Events

  @discardableResult
  func emit(_ type: String, entity: String, data: [String: String]) async throws -> RuntimeEvent {
    let event = try await backend.appendEvent(
      project: binding.id, type: type, entity: entity, data: data, keep: Self.eventHistory)
    await RedisSignal.publish(projectID: binding.id, url: redisURL)
    return event
  }

  public func events(after revision: Int, limit: Int = 200) async throws -> [RuntimeEvent] {
    try validate()
    guard revision >= 0, (1...500).contains(limit) else { throw MemoError.invalid("bad range") }
    do { return try await backend.events(project: binding.id, after: revision, limit: limit) } catch {
      throw Self.safeError(error)
    }
  }

  public func latestRevision() async throws -> Int {
    try validate()
    do { return try await backend.latestRevision(project: binding.id) } catch {
      throw Self.safeError(error)
    }
  }

  // MARK: Sessions

  /// Idempotent session signal from a supported host hook or `om wake`.
  /// Emits `agent.status.changed` only when the session is new or its status changes.
  public func wake(agent: String, session: String, status: String = "ready", source: String)
    async throws -> AgentSession
  {
    try validate()
    let agent = try Self.label(agent, "agent")
    let session = try Self.label(session, "session")
    let status = RuntimeMapping.legacy(status)
    guard ["waiting", "working", "blocked", "offline"].contains(status) else {
      throw MemoError.invalid("invalid status")
    }
    let source = try Self.label(source, "source")
    let now = nowISO()
    do {
      let (previous, firstSeen) = try await backend.upsertSession(
        project: binding.id, agent: agent, session: session, status: status, source: source, now: now)
      if previous != status {
        do {
          try await emit(
            "agent.status.changed", entity: agent + ":" + session,
            data: ["agent": agent, "status": status, "source": source])
        } catch {
          // Otherwise the change is stored unannounced and the next wake sees nothing to report.
          if let previous {
            _ = try? await backend.upsertSession(
              project: binding.id, agent: agent, session: session, status: previous, source: source, now: now)
          }
          throw error
        }
      }
      return AgentSession(
        agent: agent, sessionID: session, status: status, source: source,
        firstSeen: firstSeen ?? now, lastSeen: now)
    } catch { throw Self.safeError(error) }
  }

  /// Bounded project capsule for a session's prompt. Returns nil when the capsule
  /// is unchanged since it was last delivered to this session (no repeated tokens).
  public func promptContext(
    agent: String, session: String, maxTokens: Int = 600, source: String = "cli"
  ) async throws -> Data? {
    _ = try await wake(agent: agent, session: session, status: "working", source: source)
    let capsule = try await context(task: "", maxTokens: maxTokens)
    // An empty project adds no prompt tokens.
    guard let envelope = try? JSONDecoder().decode(ContextEnvelope.self, from: capsule),
      !envelope.result.isEmpty
    else { return nil }
    do {
      return try await backend.replaceContextDigest(
        project: binding.id, agent: agent, session: session, digest: digest(capsule)) ? capsule : nil
    } catch { throw Self.safeError(error) }
  }

  public func agents(limit: Int = 50) async throws -> [AgentSession] {
    try validate()
    let format = ISO8601DateFormatter()
    let passive = format.string(from: Date().addingTimeInterval(-Self.presenceTimeout))
    let managed = format.string(from: Date().addingTimeInterval(-Self.managedStaleAfter))
    do {
      return Self.withoutMCPShadows(try await backend.sessions(project: binding.id, limit: limit)).map {
        var s = $0
        s.status = RuntimeMapping.legacy(s.status)
        // Silence never becomes offline or done: it is stale, shown with its last-seen time.
        let cutoff = s.observability == "managed" ? managed : passive
        if s.status != "offline" && s.lastSeen < cutoff { s.status = "stale" }
        return s
      }
    } catch { throw Self.safeError(error) }
  }

  /// A CLI with lifecycle hooks also starts the MCP server, which records its own presence
  /// session. Both are the same agent, so the MCP one is hidden while a hook-reported session of
  /// that client overlaps it in time; MCP-only hosts (IDEs) keep their card.
  static func withoutMCPShadows(_ sessions: [AgentSession]) -> [AgentSession] {
    let format = ISO8601DateFormatter()
    let slack: TimeInterval = 120
    func span(_ s: AgentSession) -> (Date, Date)? {
      guard let first = format.date(from: s.firstSeen), let last = format.date(from: s.lastSeen) else { return nil }
      return (first.addingTimeInterval(-slack), last.addingTimeInterval(slack))
    }
    let hooked = sessions.filter { $0.source != "mcp" }.compactMap { s in span(s).map { (s.agent, $0) } }
    return sessions.filter { s in
      guard s.source == "mcp", let (first, last) = span(s) else { return true }
      return !hooked.contains { $0.0 == s.agent && $0.1.0 <= last && first <= $0.1.1 }
    }
  }

  // MARK: Tasks

  public func listTasks(limit: Int = 200) async throws -> [TaskRecord] {
    try validate()
    do { return try await backend.tasks(project: binding.id, limit: limit) } catch {
      throw Self.safeError(error)
    }
  }

  /// Idempotent when `idempotencyKey` is reused with the same title.
  public func createTask(
    title: String, idempotencyKey: String? = nil, priority: String = "P2", agent: String = "cli"
  ) async throws -> TaskRecord {
    try validate()
    try await ensureRuntimeIndexes()
    guard TaskRecord.priorities.contains(priority) else { throw MemoError.invalid("priority") }
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...240).contains(title.utf8.count) else { throw MemoError.invalid("title length") }
    try SecretFilter.check(title)
    let id =
      try idempotencyKey.map { "task_" + digest(try Self.label($0, "idempotency key")).prefix(16) }
      ?? "task_" + UUID().uuidString.lowercased().prefix(16)
    let now = nowISO()
    let task = TaskRecord(
      id: String(id), title: title, status: "todo", revision: 1, owner: nil, priority: priority,
      createdAt: now, updatedAt: now)
    do {
      guard try await backend.insert(task: task, project: binding.id) else {
        guard let existing = try await backend.task(project: binding.id, id: task.id) else {
          throw MemoError.database("write rejected")
        }
        guard existing.title == title else { throw MemoError.conflict }
        return existing
      }
      try await emit(
        "task.updated", entity: task.id, data: ["status": task.status, "revision": "1", "agent": agent])
      return task
    } catch { throw Self.safeError(error) }
  }

  /// Compare-and-set update: succeeds only if `expectedRevision` is still current.
  public func updateTask(
    id: String, expectedRevision: Int, status: String?, owner: String?, priority: String? = nil,
    agent: String = "cli"
  ) async throws -> TaskRecord {
    try validate()
    let id = try Self.label(id, "task id")
    if let status, !TaskRecord.statuses.contains(status) {
      throw MemoError.invalid("invalid task status")
    }
    if let owner { _ = try Self.label(owner, "owner") }
    if let priority, !TaskRecord.priorities.contains(priority) {
      throw MemoError.invalid("priority")
    }
    do {
      let before = try await backend.task(project: binding.id, id: id)
      guard
        let task = try await backend.updateTask(
          project: binding.id, id: id, expectedRevision: expectedRevision,
          change: TaskChange(status: status, owner: owner, priority: priority, updatedAt: nowISO()))
      else { throw before == nil ? MemoError.notFound : MemoError.revisionConflict }
      try await emit(
        "task.updated", entity: task.id,
        data: ["status": task.status, "revision": String(task.revision), "agent": agent])
      if before?.status != task.status, ["review", "done", "blocked"].contains(task.status) {
        await autoSaveTransition(
          kind: "task", key: "auto-task:\(task.id):\(task.revision)",
          title: "Task \(task.status): \(task.title)",
          content: "\(task.title) moved to \(task.status) by \(agent) (revision \(task.revision), owner \(task.owner ?? "unassigned")).",
          agent: agent)
      }
      return task
    } catch { throw Self.safeError(error) }
  }

  // MARK: Approvals

  public func listApprovals(limit: Int = 100) async throws -> [ApprovalRecord] {
    try validate()
    do { return try await backend.approvals(project: binding.id, limit: limit) } catch {
      throw Self.safeError(error)
    }
  }

  /// An agent asks a human to decide. The record is advisory: it never runs the action.
  public func requestApproval(action: String, reason: String, agent: String) async throws
    -> ApprovalRecord
  {
    try validate()
    let action = action.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...160).contains(action.utf8.count), reason.utf8.count <= 1000 else {
      throw MemoError.invalid("action or reason length")
    }
    try SecretFilter.check(action + "\n" + reason)
    let agent = try Self.label(agent, "agent")
    try await ensureRuntimeIndexes()
    let record = ApprovalRecord(
      id: "apr_" + UUID().uuidString.lowercased().prefix(16), action: action, reason: reason,
      requestedBy: agent, status: "pending", revision: 1, createdAt: nowISO(), decidedAt: nil)
    do {
      try await backend.insert(approval: record, project: binding.id)
      try await emit(
        "approval.requested", entity: record.id, data: ["agent": agent, "status": "pending"])
      await autoSaveTransition(
        kind: "decision", key: "auto-approval:\(record.id):pending",
        title: "Approval requested: \(action)",
        content: "\(agent) asked a human to approve: \(action).\(reason.isEmpty ? "" : " Reason: " + reason)",
        agent: agent)
      return record
    } catch { throw Self.safeError(error) }
  }

  /// Records a human decision once; a second decision on the same request conflicts.
  public func decideApproval(id: String, decision: String) async throws -> ApprovalRecord {
    try validate()
    let id = try Self.label(id, "approval id")
    guard ["approved", "denied"].contains(decision) else { throw MemoError.invalid("decision") }
    do {
      guard
        let record = try await backend.decideApproval(
          project: binding.id, id: id, decision: decision, at: nowISO())
      else {
        throw try await backend.approval(project: binding.id, id: id) == nil
          ? MemoError.notFound : MemoError.revisionConflict
      }
      try await emit(
        "approval.decided", entity: record.id, data: ["agent": record.requestedBy, "status": decision])
      await autoSaveTransition(
        kind: "decision", key: "auto-approval:\(record.id):\(decision)",
        title: "Approval \(decision): \(record.action)",
        content: "A human \(decision) \(record.requestedBy)'s request: \(record.action). Recording it ran nothing.",
        agent: "mission-control")
      return record
    } catch { throw Self.safeError(error) }
  }

  // MARK: Auto-save (opt-in, FR-15)

  /// Best effort: an automatic memory never makes the triggering operation fail.
  private func autoSaveTransition(kind: String, key: String, title: String, content: String, agent: String) async {
    guard autoSave.transitions else { return }
    _ = try? await save(
      SaveInput(
        kind: kind, title: String(title.prefix(240)), content: content, tags: ["auto", "transition"],
        idempotencyKey: key), agent: agent)
  }

  /// Short, secret-checked summary of a user prompt; never the full text. Prompt memories
  /// are searchable but excluded from context capsules, so they add no prompt tokens.
  @discardableResult
  public func autoPromptSummary(agent: String, session: String, prompt: String) async -> SaveResult? {
    guard autoSave.prompts else { return nil }
    let collapsed = prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard !collapsed.isEmpty else { return nil }
    let summary = collapsed.count > 160 ? String(collapsed.prefix(159)) + "…" : collapsed
    guard (try? SecretFilter.check(prompt)) != nil else { return nil }  // skip, never store secrets
    return try? await save(
      SaveInput(
        kind: "prompt", title: "Prompt (\(agent)): " + String(summary.prefix(60)), content: summary,
        tags: ["auto", "prompt", agent],
        idempotencyKey: "auto-prompt:\(session):" + digest(summary).prefix(16)), agent: agent)
  }

  /// Session-end checkpoint from verifiable state only: branch/commit (recorded by save),
  /// changed files from `git status`, and the tasks this agent owns. No conversation content.
  @discardableResult
  public func autoCheckpoint(agent: String, session: String, reason: String) async -> SaveResult? {
    guard autoSave.checkpoints else { return nil }
    let changed = binding.changedFiles()
    let evidence = changed.filter { (try? binding.evidence($0)) != nil }.prefix(8)
    let owned = ((try? await listTasks()) ?? []).filter {
      $0.owner == agent && ["doing", "review", "blocked"].contains($0.status)
    }
    var done = ["Session ended (\(reason))"]
    if !changed.isEmpty {
      let names = changed.prefix(12).joined(separator: ", ")
      done.append("Changed \(changed.count) file(s): " + names + (changed.count > 12 ? ", …" : ""))
    }
    let input = CheckpointInput(
      title: "Auto checkpoint: \(agent) session \(session.prefix(8))", done: done,
      next: owned.map { "\($0.status == "review" ? "Review" : "Continue"): \($0.title)" },
      blocked: owned.filter { $0.status == "blocked" }.map(\.title), tests: [],
      changedFiles: Array(evidence),
      idempotencyKey: "auto-ckpt:\(agent):\(session):\(binding.head.prefix(12)):"
        + digest(changed.joined(separator: "\n")).prefix(12))
    return try? await checkpoint(input, agent: agent)
  }
}

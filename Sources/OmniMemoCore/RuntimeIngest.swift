import Foundation

/// One agent card as the UI and the Claude Code mod read it.
public struct RuntimeAgentView: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case client, model, status, observability, source, task, progress, context
    case runtimeID = "runtime_id"
    case displaySlug = "display_slug"
    case sessionID = "session_id"
    case lastSeen = "last_seen"
    case lastEvent = "last_event"
    case toolCategory = "tool_category"
    case eventCount = "event_count"
  }
  public struct TaskRef: Codable, Sendable {
    public var id: String
    public var title: String
  }
  public var runtimeID: String?
  public var displaySlug: String
  public var client: String
  public var model: String?
  public var sessionID: String
  public var status: String
  public var observability: String
  public var source: String
  public var lastSeen: String
  public var lastEvent: String?
  public var toolCategory: String?
  public var eventCount: Int
  public var task: TaskRef?
  public var progress: Progress
  /// Separate from task progress: what the host reported about its context window.
  public var context: ContextUsage
}

extension MemoryStore {
  /// Managed sessions heartbeat, so a short silence is meaningful; passive hooks are sparse.
  public static let managedStaleAfter: TimeInterval = 45

  private static let iso = ISO8601DateFormatter()
  private static let isoFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  /// How far ahead of this machine's clock an adapter's `occurred_at` may be.
  static let clockSkew: TimeInterval = 300

  static func date(_ text: String) -> Date? { iso.date(from: text) ?? isoFraction.date(from: text) }

  /// Validates, deduplicates, applies and broadcasts one adapter event. The durable store is
  /// written before any broadcast; a duplicate changes nothing.
  public func ingest(_ e: RuntimeEventInput) async throws -> IngestResult {
    try validate()
    guard ["1", "2.3"].contains(e.schemaVersion) else { throw MemoError.invalid("schema_version") }
    guard RuntimeEventInput.providers.contains(e.provider) else { throw MemoError.invalid("provider") }
    guard RuntimeEventInput.eventTypes.contains(e.eventType) else { throw MemoError.invalid("event_type") }
    guard ["observed", "reported", "inferred"].contains(e.sourceConfidence) else {
      throw MemoError.invalid("source_confidence")
    }
    guard UUID(uuidString: e.eventID) != nil else { throw MemoError.invalid("event_id must be a UUID") }
    let source = try Self.label(e.source, "source")
    let external = try Self.label(e.externalSessionID, "external_session_id")
    if let workspace = e.workspaceID, workspace != binding.id, workspace != "local" { throw MemoError.denied }
    // A future time would rank every later real event as older and freeze the card.
    guard let occurred = Self.date(e.occurredAt), occurred < Date().addingTimeInterval(Self.clockSkew) else {
      throw MemoError.invalid("occurred_at")
    }
    if let task = e.taskID { _ = try Self.label(task, "task_id") }
    if let milestone = e.milestoneID { _ = try Self.label(milestone, "milestone_id") }
    if let model = e.modelID {
      guard (1...80).contains(model.utf8.count) else { throw MemoError.invalid("model_id") }
    }
    if e.eventType == "milestone.verified", e.taskID == nil || e.milestoneID == nil {
      throw MemoError.invalid("milestone.verified needs task_id and milestone_id")
    }
    var metadata: [String: String] = [:]
    for (key, value) in e.metadata ?? [:] {
      guard RuntimeEventInput.metadataKeys.contains(key) else { throw MemoError.invalid("metadata key " + key) }
      if let text = value.text { metadata[key] = String(text.prefix(120)) }
    }
    guard metadata.count <= 12 else { throw MemoError.invalid("metadata size") }
    // Categories only: a raw tool name or argument text is reduced to its category.
    if let category = metadata["tool_category"], !RuntimeMapping.toolCategories.contains(category) {
      metadata["tool_category"] = RuntimeMapping.toolCategory(category)
    }
    try SecretFilter.check(metadata.values.joined(separator: "\n") + (e.modelID ?? ""))

    let now = nowISO()
    let key = e.provider + "|" + external + "|" + e.eventID.lowercased()
    do {
      guard try await backend.claimRuntimeEvent(project: binding.id, key: key, at: now)
      else { return IngestResult(accepted: false, duplicate: true, cursor: nil, status: nil) }
    } catch { throw Self.safeError(error) }
    var saved = false
    do {
      var before = "waiting"
      let session = try await updateSession(agent: e.provider, session: external) { stored in
        var session =
          stored
          ?? AgentSession(
            agent: e.provider, sessionID: external, status: "waiting", source: source, firstSeen: now,
            lastSeen: now)
        before = session.status
        session.runtimeID = session.runtimeID ?? UUID().uuidString.lowercased()
        session.lastSeen = now
        session.source = source
        session.eventCount = (session.eventCount ?? 0) + 1
        if let mode = metadata["observability"], ["managed", "passive"].contains(mode) {
          session.observability = mode
        } else if session.observability == nil {
          session.observability = "passive"
        }
        // Older or reordered events are recorded but never move the state backwards.
        let older =
          (e.sequence != nil && session.lastSequence != nil && e.sequence! < session.lastSequence!)
          || (session.lastEventAt.flatMap(Self.date).map { occurred < $0 } ?? false)
        if !older {
          if let model = e.modelID { session.model = model }
          if let status = RuntimeMapping.status(for: e.eventType) { session.status = status }
          session.lastEvent = e.eventType
          session.lastEventAt = Self.iso.string(from: occurred)
          if let sequence = e.sequence { session.lastSequence = sequence }
          switch e.eventType {
          case "tool.started", "tool.succeeded", "tool.failed":
            session.toolCategory = metadata["tool_category"] ?? "unknown"
          case "turn.completed", "turn.failed", "session.started", "session.resumed", "session.ended":
            session.toolCategory = nil
          default: break
          }
          if e.eventType == "task.assigned", let task = e.taskID { session.taskID = task }
          if let title = metadata["title"], autoSave.titles {
            session.title = String(title.split(whereSeparator: \.isNewline).first ?? "").prefix(80).description
          }
        }
        return session
      }
      saved = true

      if e.eventType == "milestone.verified", let task = e.taskID, let milestone = e.milestoneID {
        _ = try? await setMilestone(
          taskID: task, milestoneID: milestone, verified: true,
          evidence: "runtime event \(e.eventID) from \(source)", agent: e.provider)
      }
      let event = try await emit(
        before != session.status ? "agent.status.changed" : "runtime.activity",
        entity: e.provider + ":" + external,
        data: [
          "agent": e.provider, "status": session.status, "event_type": e.eventType,
          "tool_category": session.toolCategory ?? "", "model": session.model ?? "",
          "source": source, "confidence": e.sourceConfidence,
        ])
      return IngestResult(accepted: true, duplicate: false, cursor: event.revision, status: session.status)
    } catch {
      // Not applied, so not seen: the adapter's retry must not be dropped as a duplicate.
      if !saved { try? await backend.releaseRuntimeEvent(project: binding.id, key: key) }
      throw Self.safeError(error)
    }
  }

  /// Agent cards: stale silence derived here, labels only from reported models.
  public func runtimeAgents(limit: Int = 50) async throws -> [RuntimeAgentView] {
    let sessions = try await agents(limit: limit)
    let tasks = (try? await listTasks()) ?? []
    var views = sessions.map { s -> RuntimeAgentView in
      let model = s.model.map { $0.lowercased().replacingOccurrences(of: "[^a-z0-9._-]+", with: "-", options: .regularExpression) }
      let task =
        tasks.first { $0.id == s.taskID }
        ?? tasks.filter { $0.owner == s.agent && ["doing", "review", "blocked"].contains($0.status) }
          .max { $0.updatedAt < $1.updatedAt }
      return RuntimeAgentView(
        // `client-model`, without repeating a client name the model id already carries.
        runtimeID: s.runtimeID,
        displaySlug: model.map { $0.hasPrefix(s.agent + "-") ? $0 : s.agent + "-" + $0 } ?? s.agent + "-model-unavailable",
        client: s.agent,
        model: s.model, sessionID: s.sessionID, status: s.status, observability: s.observability ?? "passive",
        source: s.source, lastSeen: s.lastSeen, lastEvent: s.lastEvent, toolCategory: s.toolCategory,
        eventCount: s.eventCount ?? 0,
        task: task.map { .init(id: $0.id, title: $0.title) } ?? s.title.map { .init(id: "", title: $0) },
        progress: Progress.of(task?.milestones), context: ContextUsage.of(s))
    }
    // Same client-model twice: add a short session suffix instead of merging identities.
    let counts = Dictionary(grouping: views, by: \.displaySlug).mapValues(\.count)
    for i in views.indices where (counts[views[i].displaySlug] ?? 0) > 1 {
      views[i].displaySlug += " · " + views[i].sessionID.suffix(4)
    }
    return views
  }

  // MARK: Milestones

  /// Adds a milestone to a task's plan (equal weight by default).
  public func addMilestone(taskID: String, title: String, weight: Int = 1, agent: String) async throws
    -> TaskRecord
  {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...160).contains(title.utf8.count), (1...100).contains(weight) else {
      throw MemoError.invalid("milestone title or weight")
    }
    try SecretFilter.check(title)
    return try await mutateTask(taskID, agent: agent) { task in
      var plan = task.milestones ?? []
      guard plan.count < 50 else { throw MemoError.invalid("too many milestones") }
      plan.append(
        Milestone(
          id: "ms_" + UUID().uuidString.lowercased().prefix(8), title: title, weight: weight,
          verified: false, evidence: nil, verifiedAt: nil))
      return plan
    }
  }

  /// Marks a milestone verified (evidence required) or reverts it; every change is a task event.
  public func setMilestone(
    taskID: String, milestoneID: String, verified: Bool, evidence: String, agent: String
  ) async throws -> TaskRecord {
    let evidence = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...240).contains(evidence.utf8.count) else { throw MemoError.invalid("evidence is required") }
    try SecretFilter.check(evidence)
    return try await mutateTask(taskID, agent: agent) { task in
      var plan = task.milestones ?? []
      guard let index = plan.firstIndex(where: { $0.id == milestoneID }) else { throw MemoError.notFound }
      plan[index].verified = verified
      plan[index].evidence = evidence
      plan[index].verifiedAt = verified ? nowISO() : nil
      return plan
    }
  }

  /// Revision-checked read-modify-write of a task's milestones, retried on concurrent edits.
  private func mutateTask(
    _ id: String, agent: String, _ change: (TaskRecord) throws -> [Milestone]
  ) async throws -> TaskRecord {
    try validate()
    let id = try Self.label(id, "task id")
    for _ in 0..<3 {
      guard let task = try await backend.task(project: binding.id, id: id) else { throw MemoError.notFound }
      let plan = try change(task)
      if let updated = try await backend.updateTask(
        project: binding.id, id: id, expectedRevision: task.revision,
        change: TaskChange(milestones: plan, updatedAt: nowISO()))
      {
        let progress = Progress.of(updated.milestones)
        try await emit(
          "task.updated", entity: updated.id,
          data: [
            "status": updated.status, "revision": String(updated.revision), "agent": agent,
            "progress": progress.percent.map(String.init) ?? "indeterminate",
          ])
        return updated
      }
    }
    throw MemoError.revisionConflict
  }
}

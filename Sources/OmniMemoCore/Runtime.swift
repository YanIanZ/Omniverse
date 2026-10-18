import Foundation
import MongoKitten

/// One observed agent session. Status comes only from real hook/CLI signals.
public struct AgentSession: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case agent, status, source
    case sessionID = "session_id"
    case firstSeen = "first_seen"
    case lastSeen = "last_seen"
  }
  public var agent: String
  public var sessionID: String
  public var status: String
  public var source: String
  public var firstSeen: String
  public var lastSeen: String
}

public struct TaskRecord: Codable, Sendable, Equatable {
  enum CodingKeys: String, CodingKey {
    case id, title, status, revision, owner
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
  public var id: String
  public var title: String
  public var status: String
  public var revision: Int
  public var owner: String?
  public var createdAt: String
  public var updatedAt: String
  public static let statuses = ["todo", "doing", "review", "done", "blocked"]
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

extension MongoStore {
  /// A session without a signal for this long is shown as `unknown`, never `idle`.
  public static let presenceTimeout: TimeInterval = 600
  private static let eventHistory = 1000

  private var sessions: MongoCollection { db["omnimem_sessions"] }
  private var tasks: MongoCollection { db["omnimem_tasks"] }
  private var events: MongoCollection { db["omnimem_events"] }

  public func ensureRuntimeIndexes() async throws {
    do {
      var task = CreateIndexes.Index(named: "project_task", keys: ["project_id": 1, "id": 1])
      task.unique = true
      var event = CreateIndexes.Index(named: "project_seq", keys: ["project_id": 1, "revision": 1])
      event.unique = true
      try await tasks.createIndexes([task])
      try await events.createIndexes([event])
      try await sessions.createIndexes([
        CreateIndexes.Index(named: "project_seen", keys: ["project_id": 1, "last_seen": -1])
      ])
    } catch { throw Self.safeError(error) }
  }

  static func label(_ value: String, _ name: String) throws -> String {
    guard (1...128).contains(value.utf8.count),
      value.range(of: "^[A-Za-z0-9._:-]+$", options: .regularExpression) != nil
    else { throw MemoError.invalid("invalid \(name)") }
    return value
  }

  // MARK: Events

  @discardableResult
  func emit(_ type: String, entity: String, data: [String: String]) async throws -> RuntimeEvent {
    let counter = try await db["omnimem_counters"].findOneAndUpsert(
      where: ["_id": "events:" + binding.id],
      replacement: ["$inc": ["seq": 1]], returnValue: .modified
    ).execute()
    guard let seq = counter.value?["seq"] as? Int ?? (counter.value?["seq"] as? Int32).map(Int.init)
    else { throw MemoError.database("event sequence unavailable") }
    let event = RuntimeEvent(
      eventID: "evt_" + UUID().uuidString.lowercased(), projectID: binding.id, type: type,
      entityID: entity, revision: seq, timestamp: nowISO(), data: data)
    var doc = try BSONEncoder().encode(event)
    doc["_id"] = event.eventID
    _ = try await events.insert(doc)
    _ = try? await events.deleteAll(where: [
      "project_id": binding.id, "revision": ["$lte": seq - Self.eventHistory],
    ])
    await RedisSignal.publish(projectID: binding.id)
    return event
  }

  public func events(after revision: Int, limit: Int = 200) async throws -> [RuntimeEvent] {
    try validate()
    guard revision >= 0, (1...500).contains(limit) else { throw MemoError.invalid("bad range") }
    do {
      return try await events.find(["project_id": binding.id, "revision": ["$gt": revision]])
        .sort(["revision": 1]).limit(limit).decode(RuntimeEvent.self).drain()
    } catch { throw Self.safeError(error) }
  }

  public func latestRevision() async throws -> Int {
    try validate()
    do {
      let last = try await events.find(["project_id": binding.id]).sort(["revision": -1]).limit(1)
        .decode(RuntimeEvent.self).drain()
      return last.first?.revision ?? 0
    } catch { throw Self.safeError(error) }
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
    guard ["ready", "active", "disconnected"].contains(status) else {
      throw MemoError.invalid("invalid status")
    }
    let source = try Self.label(source, "source")
    let now = nowISO()
    do {
      let reply = try await sessions.findOneAndUpsert(
        where: ["_id": binding.id + ":" + agent + ":" + session],
        replacement: [
          "$set": [
            "project_id": binding.id, "agent": agent, "session_id": session, "status": status,
            "source": source, "last_seen": now,
          ] as Document,
          "$setOnInsert": ["first_seen": now] as Document,
        ], returnValue: .original
      ).execute()
      let previous = reply.value?["status"] as? String
      if previous != status {
        try await emit(
          "agent.status.changed", entity: agent + ":" + session,
          data: ["agent": agent, "status": status, "source": source])
      }
      return AgentSession(
        agent: agent, sessionID: session, status: status, source: source,
        firstSeen: reply.value?["first_seen"] as? String ?? now, lastSeen: now)
    } catch { throw Self.safeError(error) }
  }

  /// Bounded project capsule for a session's prompt. Returns nil when the capsule
  /// is unchanged since it was last delivered to this session (no repeated tokens).
  public func promptContext(
    agent: String, session: String, maxTokens: Int = 600, source: String = "cli"
  ) async throws -> Data? {
    _ = try await wake(agent: agent, session: session, status: "active", source: source)
    let capsule = try await context(task: "", maxTokens: maxTokens)
    // An empty project adds no prompt tokens.
    guard let envelope = try? JSONDecoder().decode(ContextEnvelope.self, from: capsule),
      !envelope.result.isEmpty
    else { return nil }
    let stamp = digest(capsule)
    do {
      let reply = try await sessions.findOneAndUpdate(
        where: [
          "_id": binding.id + ":" + agent + ":" + session, "context_digest": ["$ne": stamp],
        ], to: ["$set": ["context_digest": stamp]]
      ).execute()
      return reply.value == nil ? nil : capsule
    } catch { throw Self.safeError(error) }
  }

  public func agents(limit: Int = 50) async throws -> [AgentSession] {
    try validate()
    let cutoff = ISO8601DateFormatter().string(
      from: Date().addingTimeInterval(-Self.presenceTimeout))
    do {
      let found = try await sessions.find(["project_id": binding.id])
        .sort(["last_seen": -1]).limit(limit).decode(AgentSession.self).drain()
      return found.map {
        var s = $0
        if s.status != "disconnected" && s.lastSeen < cutoff { s.status = "unknown" }
        return s
      }
    } catch { throw Self.safeError(error) }
  }

  // MARK: Tasks

  public func listTasks(limit: Int = 200) async throws -> [TaskRecord] {
    try validate()
    do {
      return try await tasks.find(["project_id": binding.id]).sort(["created_at": 1]).limit(limit)
        .decode(TaskRecord.self).drain()
    } catch { throw Self.safeError(error) }
  }

  /// Idempotent when `idempotencyKey` is reused with the same title.
  public func createTask(title: String, idempotencyKey: String? = nil, agent: String = "cli")
    async throws -> TaskRecord
  {
    try validate()
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...240).contains(title.utf8.count) else { throw MemoError.invalid("title length") }
    try SecretFilter.check(title)
    let id =
      try idempotencyKey.map { "task_" + digest(try Self.label($0, "idempotency key")).prefix(16) }
      ?? "task_" + UUID().uuidString.lowercased().prefix(16)
    let now = nowISO()
    let task = TaskRecord(
      id: String(id), title: title, status: "todo", revision: 1, owner: nil, createdAt: now,
      updatedAt: now)
    do {
      var doc = try BSONEncoder().encode(task)
      doc["project_id"] = binding.id
      let result = try await tasks.insert(doc)
      if !(result.writeErrors ?? []).isEmpty {
        guard
          let existing = try await tasks.findOne(
            ["project_id": binding.id, "id": task.id], as: TaskRecord.self)
        else { throw MemoError.database("write rejected") }
        guard existing.title == title else { throw MemoError.conflict }
        return existing
      }
      try await emit(
        "task.updated", entity: task.id,
        data: ["status": task.status, "revision": "1", "agent": agent])
      return task
    } catch { throw Self.safeError(error) }
  }

  /// Compare-and-set update: succeeds only if `expectedRevision` is still current.
  public func updateTask(
    id: String, expectedRevision: Int, status: String?, owner: String?, agent: String = "cli"
  ) async throws -> TaskRecord {
    try validate()
    let id = try Self.label(id, "task id")
    if let status, !TaskRecord.statuses.contains(status) {
      throw MemoError.invalid("invalid task status")
    }
    if let owner { _ = try Self.label(owner, "owner") }
    var set: Document = ["updated_at": nowISO()]
    if let status { set["status"] = status }
    if let owner { set["owner"] = owner }
    do {
      let reply = try await tasks.findOneAndUpdate(
        where: ["project_id": binding.id, "id": id, "revision": expectedRevision],
        to: ["$set": set, "$inc": ["revision": 1]], returnValue: .modified
      ).execute()
      guard let value = reply.value else {
        let exists = try await tasks.findOne(["project_id": binding.id, "id": id]) != nil
        throw exists ? MemoError.revisionConflict : MemoError.notFound
      }
      let task = try BSONDecoder().decode(TaskRecord.self, from: value)
      try await emit(
        "task.updated", entity: task.id,
        data: ["status": task.status, "revision": String(task.revision), "agent": agent])
      return task
    } catch { throw Self.safeError(error) }
  }
}

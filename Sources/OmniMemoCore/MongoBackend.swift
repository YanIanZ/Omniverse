import Foundation
import Logging
import MongoKitten

/// `mongodb` / `hybrid` profile: MongoDB is the system of record.
final class MongoBackend: StoreBackend, @unchecked Sendable {
  let db: MongoDatabase
  private var records: MongoCollection { db["omnimem_records"] }
  private var sessions: MongoCollection { db["omnimem_sessions"] }
  private var tasks: MongoCollection { db["omnimem_tasks"] }
  private var events: MongoCollection { db["omnimem_events"] }
  private var approvals: MongoCollection { db["omnimem_approvals"] }

  private struct Metadata: Codable {
    enum CodingKeys: String, CodingKey {
      case schemaVersion = "schema_version"
      case storeID = "store_id"
    }
    var schemaVersion: Int
    var storeID: String
  }

  private init(db: MongoDatabase) { self.db = db }

  private static func connect(_ uri: String) async throws -> MongoDatabase {
    // The URI is configuration, never a value accepted from an MCP tool call.
    guard uri.hasPrefix("mongodb://"), uri.utf8.count <= 4096 else {
      throw MemoError.invalid("expected mongodb:// URI")
    }
    var logger = Logger(
      label: "omnimem.mongo", factory: { StreamLogHandler.standardError(label: $0) })
    logger.logLevel = .critical
    do { return try await MongoDatabase.connect(to: uri, logger: logger) } catch {
      throw MemoError.storageUnavailable
    }
  }

  /// Creates (or adopts) the store metadata and memory indexes; returns the store id.
  static func initialize(address: String) async throws -> (MongoBackend, String) {
    let db = try await connect(address)
    do {
      var meta = try await db["omnimem_meta"].findOne(["_id": "store"], as: Metadata.self)
      if meta == nil {
        var doc = try BSONEncoder().encode(
          Metadata(schemaVersion: 1, storeID: UUID().uuidString.lowercased()))
        doc["_id"] = "store"
        _ = try await db["omnimem_meta"].insert(doc)
        meta = try await db["omnimem_meta"].findOne(["_id": "store"], as: Metadata.self)
      }
      guard let meta, meta.schemaVersion == 1 else {
        throw MemoError.invalid("unsupported schema version")
      }
      var unique = CreateIndexes.Index(named: "dedup", keys: ["project_id": 1, "dedup_key": 1])
      unique.unique = true
      var uniqueID = CreateIndexes.Index(named: "memo_id", keys: ["id": 1])
      uniqueID.unique = true
      var text = CreateIndexes.Index(
        named: "scoped_text",
        keys: ["project_id": 1, "title": "text", "content": "text", "tags": "text"])
      text.defaultLanguage = "none"
      text.languageOverride = "_language"
      let recent = CreateIndexes.Index(
        named: "project_recent", keys: ["project_id": 1, "created_at": -1])
      try await db["omnimem_records"].createIndexes([unique, uniqueID, text, recent])
      return (MongoBackend(db: db), meta.storeID)
    } catch {
      await (db.pool as? MongoCluster)?.disconnect()
      throw error
    }
  }

  static func open(address: String, storeID: String) async throws -> MongoBackend {
    let db = try await connect(address)
    do {
      guard let meta = try await db["omnimem_meta"].findOne(["_id": "store"], as: Metadata.self),
        meta.schemaVersion == 1, meta.storeID == storeID
      else { throw MemoError.storageUnavailable }
      return MongoBackend(db: db)
    } catch {
      await (db.pool as? MongoCluster)?.disconnect()
      throw error
    }
  }

  func close() async { await (db.pool as? MongoCluster)?.disconnect() }

  // MARK: Records

  func record(project: String, dedupKey: String) async throws -> MemoryRecord? {
    try await records.findOne(["project_id": project, "dedup_key": dedupKey], as: MemoryRecord.self)
  }

  func insert(record: MemoryRecord) async throws -> Bool {
    let result = try await records.insertEncoded(record)
    return (result.writeErrors ?? []).isEmpty
  }

  func record(project: String, id: String) async throws -> MemoryRecord? {
    try await records.findOne(["project_id": project, "id": id], as: MemoryRecord.self)
  }

  func search(project: String, query: String, limit: Int) async throws -> [MemoryRecord] {
    let text: Document = ["project_id": project, "$text": ["$search": query, "$language": "none"]]
    var matches = try await records.find(text).sort(["score": ["$meta": "textScore"]])
      .limit(limit).decode(MemoryRecord.self).drain()
    if matches.count < limit {
      let regex: Document = ["$regex": NSRegularExpression.escapedPattern(for: query), "$options": "i"]
      let fallback: Document = [
        "project_id": project,
        "$or": [["title": regex] as Document, ["content": regex] as Document, ["tags": regex] as Document],
      ]
      let extra = try await records.find(fallback).sort(["created_at": -1]).limit(limit)
        .decode(MemoryRecord.self).drain()
      let ids = Set(matches.map(\.id))
      matches += extra.filter { !ids.contains($0.id) }
    }
    return Array(matches.prefix(limit))
  }

  func recent(project: String, limit: Int) async throws -> [MemoryRecord] {
    try await records.find(["project_id": project]).sort(["created_at": -1]).limit(limit)
      .decode(MemoryRecord.self).drain()
  }

  func deleteRecord(project: String, id: String) async throws -> Bool {
    try await records.deleteOne(where: ["project_id": project, "id": id]).deletes == 1
  }

  func countRecords(project: String) async throws -> Int {
    try await records.count(["project_id": project])
  }

  // MARK: Runtime

  func prepareRuntime(project: String) async throws {
    try await mergeDuplicateTasks(project: project)
    var task = CreateIndexes.Index(named: "project_task", keys: ["project_id": 1, "id": 1])
    task.unique = true
    var event = CreateIndexes.Index(named: "project_seq", keys: ["project_id": 1, "revision": 1])
    event.unique = true
    var approval = CreateIndexes.Index(named: "project_approval", keys: ["project_id": 1, "id": 1])
    approval.unique = true
    try await approvals.createIndexes([approval])
    try await tasks.createIndexes([task])
    try await events.createIndexes([event])
    try await sessions.createIndexes([
      CreateIndexes.Index(named: "project_seen", keys: ["project_id": 1, "last_seen": -1])
    ])
  }

  /// A task id is its identity. Copies written concurrently before the unique index existed
  /// are merged into the most advanced revision; the removal is reported on stderr.
  private func mergeDuplicateTasks(project: String) async throws {
    var keep: [String: (Primitive, Int)] = [:]
    var drop: [Primitive] = []
    for doc in try await tasks.find(["project_id": project]).drain() {
      guard let objectID = doc["_id"], let task = try? BSONDecoder().decode(TaskRecord.self, from: doc)
      else { continue }
      if let (current, best) = keep[task.id] {
        if task.revision > best {
          drop.append(current)
          keep[task.id] = (objectID, task.revision)
        } else {
          drop.append(objectID)
        }
      } else {
        keep[task.id] = (objectID, task.revision)
      }
    }
    for objectID in drop { _ = try await tasks.deleteOne(where: ["_id": objectID]) }
    if !drop.isEmpty {
      FileHandle.standardError.write(
        Data("omnimem: merged \(drop.count) duplicate task copies (kept the highest revision)\n".utf8))
    }
  }

  func appendEvent(
    project: String, type: String, entity: String, data: [String: String], keep: Int
  ) async throws -> RuntimeEvent {
    let counter = try await db["omnimem_counters"].findOneAndUpsert(
      where: ["_id": "events:" + project], replacement: ["$inc": ["seq": 1]], returnValue: .modified
    ).execute()
    guard let seq = counter.value?["seq"] as? Int ?? (counter.value?["seq"] as? Int32).map(Int.init)
    else { throw MemoError.database("event sequence unavailable") }
    let event = RuntimeEvent(
      eventID: "evt_" + UUID().uuidString.lowercased(), projectID: project, type: type,
      entityID: entity, revision: seq, timestamp: nowISO(), data: data)
    var doc = try BSONEncoder().encode(event)
    doc["_id"] = event.eventID
    _ = try await events.insert(doc)
    _ = try? await events.deleteAll(where: ["project_id": project, "revision": ["$lte": seq - keep]])
    return event
  }

  func events(project: String, after revision: Int, limit: Int) async throws -> [RuntimeEvent] {
    try await events.find(["project_id": project, "revision": ["$gt": revision]])
      .sort(["revision": 1]).limit(limit).decode(RuntimeEvent.self).drain()
  }

  func latestRevision(project: String) async throws -> Int {
    try await events.find(["project_id": project]).sort(["revision": -1]).limit(1)
      .decode(RuntimeEvent.self).drain().first?.revision ?? 0
  }

  func upsertSession(
    project: String, agent: String, session: String, status: String, source: String, now: String
  ) async throws -> (previous: String?, firstSeen: String?) {
    let reply = try await sessions.findOneAndUpsert(
      where: ["_id": project + ":" + agent + ":" + session],
      replacement: [
        "$set": [
          "project_id": project, "agent": agent, "session_id": session, "status": status,
          "source": source, "last_seen": now,
        ] as Document,
        "$setOnInsert": ["first_seen": now] as Document,
      ], returnValue: .original
    ).execute()
    return (reply.value?["status"] as? String, reply.value?["first_seen"] as? String)
  }

  func replaceContextDigest(project: String, agent: String, session: String, digest: String)
    async throws -> Bool
  {
    let reply = try await sessions.findOneAndUpdate(
      where: ["_id": project + ":" + agent + ":" + session, "context_digest": ["$ne": digest]],
      to: ["$set": ["context_digest": digest]]
    ).execute()
    return reply.value != nil
  }

  func sessions(project: String, limit: Int) async throws -> [AgentSession] {
    try await sessions.find(["project_id": project]).sort(["last_seen": -1]).limit(limit)
      .decode(AgentSession.self).drain()
  }

  func tasks(project: String, limit: Int) async throws -> [TaskRecord] {
    try await tasks.find(["project_id": project]).sort(["created_at": 1]).limit(limit)
      .decode(TaskRecord.self).drain()
  }

  func insert(task: TaskRecord, project: String) async throws -> Bool {
    var doc = try BSONEncoder().encode(task)
    doc["project_id"] = project
    return (try await tasks.insert(doc).writeErrors ?? []).isEmpty
  }

  func task(project: String, id: String) async throws -> TaskRecord? {
    try await tasks.findOne(["project_id": project, "id": id], as: TaskRecord.self)
  }

  func updateTask(project: String, id: String, expectedRevision: Int, change: TaskChange)
    async throws -> TaskRecord?
  {
    var set: Document = ["updated_at": change.updatedAt]
    if let status = change.status { set["status"] = status }
    if let owner = change.owner { set["owner"] = owner }
    if let priority = change.priority { set["priority"] = priority }
    let reply = try await tasks.findOneAndUpdate(
      where: ["project_id": project, "id": id, "revision": expectedRevision],
      to: ["$set": set, "$inc": ["revision": 1]], returnValue: .modified
    ).execute()
    return try reply.value.map { try BSONDecoder().decode(TaskRecord.self, from: $0) }
  }

  func approvals(project: String, limit: Int) async throws -> [ApprovalRecord] {
    try await approvals.find(["project_id": project]).sort(["created_at": -1]).limit(limit)
      .decode(ApprovalRecord.self).drain()
  }

  func insert(approval: ApprovalRecord, project: String) async throws {
    var doc = try BSONEncoder().encode(approval)
    doc["project_id"] = project
    _ = try await approvals.insert(doc)
  }

  func approval(project: String, id: String) async throws -> ApprovalRecord? {
    try await approvals.findOne(["project_id": project, "id": id], as: ApprovalRecord.self)
  }

  func decideApproval(project: String, id: String, decision: String, at: String) async throws
    -> ApprovalRecord?
  {
    let reply = try await approvals.findOneAndUpdate(
      where: ["project_id": project, "id": id, "status": "pending"],
      to: ["$set": ["status": decision, "decided_at": at], "$inc": ["revision": 1]],
      returnValue: .modified
    ).execute()
    return try reply.value.map { try BSONDecoder().decode(ApprovalRecord.self, from: $0) }
  }
}

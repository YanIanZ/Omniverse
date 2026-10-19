import Foundation

/// Storage primitives behind `MemoryStore`. Validation, secret filtering, evidence, dedup
/// policy, capsules and events stay in `MemoryStore`; a backend only persists and queries.
/// Every call is scoped by `project` so no backend can return another project's rows.
protocol StoreBackend: Sendable {
  func close() async

  // Memory records
  func record(project: String, dedupKey: String) async throws -> MemoryRecord?
  /// Returns false when a record with the same project + dedup key already exists.
  func insert(record: MemoryRecord) async throws -> Bool
  func record(project: String, id: String) async throws -> MemoryRecord?
  /// Full-text matches first, then case-insensitive substring matches, at most `limit`.
  func search(project: String, query: String, limit: Int) async throws -> [MemoryRecord]
  func recent(project: String, limit: Int) async throws -> [MemoryRecord]
  func deleteRecord(project: String, id: String) async throws -> Bool
  func countRecords(project: String) async throws -> Int

  // Runtime: events, sessions, tasks, approvals
  func prepareRuntime(project: String) async throws
  func appendEvent(
    project: String, type: String, entity: String, data: [String: String], keep: Int
  ) async throws -> RuntimeEvent
  func events(project: String, after revision: Int, limit: Int) async throws -> [RuntimeEvent]
  func latestRevision(project: String) async throws -> Int
  /// Upserts the session and returns its previous status and first-seen time, if any.
  func upsertSession(
    project: String, agent: String, session: String, status: String, source: String, now: String
  ) async throws -> (previous: String?, firstSeen: String?)
  /// Stores `digest` unless it is already current; true when it changed.
  func replaceContextDigest(project: String, agent: String, session: String, digest: String)
    async throws -> Bool
  func sessions(project: String, limit: Int) async throws -> [AgentSession]
  func session(project: String, agent: String, session: String) async throws -> AgentSession?
  /// Upserts the whole session state (runtime fields included) if its stored revision still
  /// equals `session.revision` (nil = 0), storing revision + 1. False when another writer won.
  func save(session: AgentSession, project: String) async throws -> Bool
  /// Claims a runtime event key once; false for a duplicate within the retention window.
  func claimRuntimeEvent(project: String, key: String, at: String) async throws -> Bool
  /// Forgets a claim whose event could not be applied, so a retry is not a duplicate.
  func releaseRuntimeEvent(project: String, key: String) async throws
  func tasks(project: String, limit: Int) async throws -> [TaskRecord]
  /// Returns false when the task id already exists in the project.
  func insert(task: TaskRecord, project: String) async throws -> Bool
  func task(project: String, id: String) async throws -> TaskRecord?
  /// Compare-and-set on `expectedRevision`; nil when the revision is stale or the id unknown.
  func updateTask(project: String, id: String, expectedRevision: Int, change: TaskChange)
    async throws -> TaskRecord?
  func approvals(project: String, limit: Int) async throws -> [ApprovalRecord]
  func insert(approval: ApprovalRecord, project: String) async throws
  func approval(project: String, id: String) async throws -> ApprovalRecord?
  /// Decides a pending request once; nil when it is not pending or unknown.
  func decideApproval(project: String, id: String, decision: String, at: String) async throws
    -> ApprovalRecord?
}

struct TaskChange: Sendable {
  var status: String?
  var owner: String?
  var priority: String?
  var milestones: [Milestone]? = nil
  var updatedAt: String
}

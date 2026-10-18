import Foundation
import SQLite3

/// `sqlite` profile (PRD §11, §100): one embedded `db/memory.sqlite` with FTS5, WAL and
/// `BEGIN IMMEDIATE` write transactions so several agent processes can share it safely.
actor SQLiteBackend: StoreBackend {
  /// Opened with SQLITE_OPEN_FULLMUTEX; used only by this actor and by the static
  /// initializers before the actor is published, so unchecked access is sound.
  private nonisolated(unsafe) let handle: OpaquePointer
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  private static let schema = """
    CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS records(
      id TEXT PRIMARY KEY, project_id TEXT NOT NULL, dedup_key TEXT NOT NULL,
      created_at TEXT NOT NULL, body TEXT NOT NULL, UNIQUE(project_id, dedup_key));
    CREATE INDEX IF NOT EXISTS records_recent ON records(project_id, created_at);
    CREATE VIRTUAL TABLE IF NOT EXISTS records_fts USING fts5(
      id UNINDEXED, project_id UNINDEXED, title, content, tags,
      tokenize = 'unicode61 remove_diacritics 2');
    CREATE TABLE IF NOT EXISTS sessions(
      project_id TEXT NOT NULL, agent TEXT NOT NULL, session_id TEXT NOT NULL,
      status TEXT NOT NULL, source TEXT NOT NULL, first_seen TEXT NOT NULL,
      last_seen TEXT NOT NULL, context_digest TEXT, PRIMARY KEY(project_id, agent, session_id));
    CREATE TABLE IF NOT EXISTS events(
      project_id TEXT NOT NULL, revision INTEGER NOT NULL, body TEXT NOT NULL,
      PRIMARY KEY(project_id, revision));
    CREATE TABLE IF NOT EXISTS tasks(
      project_id TEXT NOT NULL, id TEXT NOT NULL, created_at TEXT NOT NULL, body TEXT NOT NULL,
      PRIMARY KEY(project_id, id));
    CREATE TABLE IF NOT EXISTS approvals(
      project_id TEXT NOT NULL, id TEXT NOT NULL, created_at TEXT NOT NULL, body TEXT NOT NULL,
      PRIMARY KEY(project_id, id));
    """

  enum Value {
    case text(String)
    case int(Int)
    case null
  }

  static func file(_ root: URL) -> URL { root.appendingPathComponent("db/memory.sqlite") }

  private init(handle: OpaquePointer) { self.handle = handle }

  private static func connect(_ url: URL, create: Bool) throws -> OpaquePointer {
    var handle: OpaquePointer?
    let flags =
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | (create ? SQLITE_OPEN_CREATE : 0)
    guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
      sqlite3_close(handle)
      throw MemoError.storageUnavailable
    }
    sqlite3_busy_timeout(handle, 5000)
    return handle
  }

  /// Creates the database, schema and store id. Never called by `open`.
  static func initialize(root: URL) throws -> (SQLiteBackend, String) {
    try privateDirectory(root.appendingPathComponent("db"))
    let handle = try connect(file(root), create: true)
    let backend = SQLiteBackend(handle: handle)
    do {
      try backend.execSync("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
      try backend.execSync(schema)
      try backend.runSync(
        "INSERT OR IGNORE INTO meta(key, value) VALUES ('store_id', ?), ('schema_version', '1')",
        [.text(UUID().uuidString.lowercased())])
      guard let id = try backend.scalarSync("SELECT value FROM meta WHERE key = 'store_id'") else {
        throw MemoError.storageUnavailable
      }
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file(root).path)
      return (backend, id)
    } catch {
      sqlite3_close(handle)
      throw error
    }
  }

  /// Opens an existing database only: a missing file is `storage_unavailable`, never a new one.
  static func open(root: URL, storeID: String) throws -> SQLiteBackend {
    guard FileManager.default.fileExists(atPath: file(root).path) else {
      throw MemoError.storageUnavailable
    }
    let handle = try connect(file(root), create: false)
    let backend = SQLiteBackend(handle: handle)
    do {
      try backend.execSync(schema)  // additive migrations only
      guard try backend.scalarSync("SELECT value FROM meta WHERE key = 'store_id'") == storeID
      else { throw MemoError.storageUnavailable }
      return backend
    } catch {
      sqlite3_close(handle)
      throw error
    }
  }

  func close() async { sqlite3_close(handle) }

  // MARK: Statement helpers (actor-isolated; the *Sync forms are used before publication)

  private nonisolated func failure() -> MemoError {
    let code = sqlite3_extended_errcode(handle)
    if code == SQLITE_BUSY || code == SQLITE_LOCKED { return .database("database is busy; retry") }
    return .database("sqlite error \(code)")
  }

  private nonisolated func execSync(_ sql: String) throws {
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
  }

  private nonisolated func prepare(_ sql: String, _ params: [Value]) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw failure()
    }
    for (index, value) in params.enumerated() {
      let position = Int32(index + 1)
      switch value {
      case .text(let text): sqlite3_bind_text(statement, position, text, -1, Self.transient)
      case .int(let number): sqlite3_bind_int64(statement, position, sqlite3_int64(number))
      case .null: sqlite3_bind_null(statement, position)
      }
    }
    return statement
  }

  @discardableResult
  private nonisolated func runSync(_ sql: String, _ params: [Value] = []) throws -> Int {
    let statement = try prepare(sql, params)
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    return Int(sqlite3_changes(handle))
  }

  private nonisolated func rowsSync(_ sql: String, _ params: [Value] = []) throws -> [[String?]] {
    let statement = try prepare(sql, params)
    defer { sqlite3_finalize(statement) }
    var rows: [[String?]] = []
    while true {
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { break }
      guard step == SQLITE_ROW else { throw failure() }
      rows.append(
        (0..<sqlite3_column_count(statement)).map { column in
          sqlite3_column_text(statement, column).map { String(cString: $0) }
        })
    }
    return rows
  }

  private nonisolated func scalarSync(_ sql: String, _ params: [Value] = []) throws -> String? {
    try rowsSync(sql, params).first?.first ?? nil
  }

  /// `BEGIN IMMEDIATE` takes the write lock up front, so read-check-write is atomic across processes.
  private func write<T>(_ body: () throws -> T) throws -> T {
    try execSync("BEGIN IMMEDIATE")
    do {
      let result = try body()
      try execSync("COMMIT")
      return result
    } catch {
      try? execSync("ROLLBACK")
      throw error
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, _ rows: [[String?]]) throws -> [T] {
    try rows.compactMap { $0.first ?? nil }.map {
      try JSONDecoder().decode(T.self, from: Data($0.utf8))
    }
  }

  private func json<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try encodeJSON(value), as: UTF8.self)
  }

  // MARK: Records

  func record(project: String, dedupKey: String) async throws -> MemoryRecord? {
    try decode(
      MemoryRecord.self,
      rowsSync(
        "SELECT body FROM records WHERE project_id = ? AND dedup_key = ?",
        [.text(project), .text(dedupKey)])
    ).first
  }

  func insert(record: MemoryRecord) async throws -> Bool {
    let body = try json(record)
    return try write {
      let inserted = try runSync(
        "INSERT OR IGNORE INTO records(id, project_id, dedup_key, created_at, body) VALUES (?, ?, ?, ?, ?)",
        [.text(record.id), .text(record.projectID), .text(record.dedupKey), .text(record.createdAt), .text(body)])
      guard inserted == 1 else { return false }
      try runSync(
        "INSERT INTO records_fts(id, project_id, title, content, tags) VALUES (?, ?, ?, ?, ?)",
        [.text(record.id), .text(record.projectID), .text(record.title), .text(record.content),
         .text(record.tags.joined(separator: " "))])
      return true
    }
  }

  func record(project: String, id: String) async throws -> MemoryRecord? {
    try decode(
      MemoryRecord.self,
      rowsSync("SELECT body FROM records WHERE project_id = ? AND id = ?", [.text(project), .text(id)])
    ).first
  }

  /// FTS5 phrase-per-token query (implicit AND), ranked by BM25, then substring matches.
  func search(project: String, query: String, limit: Int) async throws -> [MemoryRecord] {
    let tokens = query.components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }.prefix(16)
    var ids: [String] = []
    if !tokens.isEmpty {
      let match = tokens.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        .joined(separator: " ")
      ids = try rowsSync(
        "SELECT id FROM records_fts WHERE records_fts MATCH ? AND project_id = ? ORDER BY bm25(records_fts) LIMIT ?",
        [.text(match), .text(project), .int(limit)]
      ).compactMap { $0.first ?? nil }
    }
    if ids.count < limit {
      let pattern = "%" + query.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
      let extra = try rowsSync(
        """
        SELECT f.id FROM records_fts f JOIN records r ON r.id = f.id
        WHERE f.project_id = ?1
          AND (f.title LIKE ?2 ESCAPE '\\' OR f.content LIKE ?2 ESCAPE '\\' OR f.tags LIKE ?2 ESCAPE '\\')
        ORDER BY r.created_at DESC LIMIT ?3
        """,
        [.text(project), .text(pattern), .int(limit)]
      ).compactMap { $0.first ?? nil }
      ids += extra.filter { !ids.contains($0) }
    }
    var found: [MemoryRecord] = []
    for id in ids.prefix(limit) {
      if let record = try await record(project: project, id: id) { found.append(record) }
    }
    return found
  }

  func recent(project: String, limit: Int) async throws -> [MemoryRecord] {
    try decode(
      MemoryRecord.self,
      rowsSync(
        "SELECT body FROM records WHERE project_id = ? ORDER BY created_at DESC, rowid DESC LIMIT ?",
        [.text(project), .int(limit)]))
  }

  func deleteRecord(project: String, id: String) async throws -> Bool {
    try write {
      try runSync("DELETE FROM records_fts WHERE id = ? AND project_id = ?", [.text(id), .text(project)])
      return try runSync("DELETE FROM records WHERE project_id = ? AND id = ?", [.text(project), .text(id)]) == 1
    }
  }

  func countRecords(project: String) async throws -> Int {
    Int(try scalarSync("SELECT COUNT(*) FROM records WHERE project_id = ?", [.text(project)]) ?? "0") ?? 0
  }

  // MARK: Runtime

  func prepareRuntime(project: String) async throws {}  // primary keys enforce identity

  func appendEvent(
    project: String, type: String, entity: String, data: [String: String], keep: Int
  ) async throws -> RuntimeEvent {
    try write {
      let last = Int(try scalarSync(
        "SELECT COALESCE(MAX(revision), 0) FROM events WHERE project_id = ?", [.text(project)]) ?? "0") ?? 0
      let event = RuntimeEvent(
        eventID: "evt_" + UUID().uuidString.lowercased(), projectID: project, type: type,
        entityID: entity, revision: last + 1, timestamp: nowISO(), data: data)
      try runSync(
        "INSERT INTO events(project_id, revision, body) VALUES (?, ?, ?)",
        [.text(project), .int(event.revision), .text(try json(event))])
      try runSync(
        "DELETE FROM events WHERE project_id = ? AND revision <= ?",
        [.text(project), .int(event.revision - keep)])
      return event
    }
  }

  func events(project: String, after revision: Int, limit: Int) async throws -> [RuntimeEvent] {
    try decode(
      RuntimeEvent.self,
      rowsSync(
        "SELECT body FROM events WHERE project_id = ? AND revision > ? ORDER BY revision LIMIT ?",
        [.text(project), .int(revision), .int(limit)]))
  }

  func latestRevision(project: String) async throws -> Int {
    Int(try scalarSync(
      "SELECT COALESCE(MAX(revision), 0) FROM events WHERE project_id = ?", [.text(project)]) ?? "0") ?? 0
  }

  func upsertSession(
    project: String, agent: String, session: String, status: String, source: String, now: String
  ) async throws -> (previous: String?, firstSeen: String?) {
    try write {
      let row = try rowsSync(
        "SELECT status, first_seen FROM sessions WHERE project_id = ? AND agent = ? AND session_id = ?",
        [.text(project), .text(agent), .text(session)]
      ).first
      if row == nil {
        try runSync(
          "INSERT INTO sessions(project_id, agent, session_id, status, source, first_seen, last_seen) VALUES (?, ?, ?, ?, ?, ?, ?)",
          [.text(project), .text(agent), .text(session), .text(status), .text(source), .text(now), .text(now)])
      } else {
        try runSync(
          "UPDATE sessions SET status = ?, source = ?, last_seen = ? WHERE project_id = ? AND agent = ? AND session_id = ?",
          [.text(status), .text(source), .text(now), .text(project), .text(agent), .text(session)])
      }
      return (row?[0] ?? nil, row?[1] ?? nil)
    }
  }

  func replaceContextDigest(project: String, agent: String, session: String, digest: String)
    async throws -> Bool
  {
    try write {
      try runSync(
        "UPDATE sessions SET context_digest = ? WHERE project_id = ? AND agent = ? AND session_id = ? AND context_digest IS NOT ?",
        [.text(digest), .text(project), .text(agent), .text(session), .text(digest)]) == 1
    }
  }

  func sessions(project: String, limit: Int) async throws -> [AgentSession] {
    try rowsSync(
      "SELECT agent, session_id, status, source, first_seen, last_seen FROM sessions WHERE project_id = ? ORDER BY last_seen DESC LIMIT ?",
      [.text(project), .int(limit)]
    ).map {
      AgentSession(
        agent: $0[0] ?? "", sessionID: $0[1] ?? "", status: $0[2] ?? "unknown",
        source: $0[3] ?? "", firstSeen: $0[4] ?? "", lastSeen: $0[5] ?? "")
    }
  }

  func tasks(project: String, limit: Int) async throws -> [TaskRecord] {
    try decode(
      TaskRecord.self,
      rowsSync(
        "SELECT body FROM tasks WHERE project_id = ? ORDER BY created_at, rowid LIMIT ?",
        [.text(project), .int(limit)]))
  }

  func insert(task: TaskRecord, project: String) async throws -> Bool {
    let body = try json(task)
    return try write {
      try runSync(
        "INSERT OR IGNORE INTO tasks(project_id, id, created_at, body) VALUES (?, ?, ?, ?)",
        [.text(project), .text(task.id), .text(task.createdAt), .text(body)]) == 1
    }
  }

  func task(project: String, id: String) async throws -> TaskRecord? {
    try decode(
      TaskRecord.self,
      rowsSync("SELECT body FROM tasks WHERE project_id = ? AND id = ?", [.text(project), .text(id)])
    ).first
  }

  func updateTask(project: String, id: String, expectedRevision: Int, change: TaskChange)
    async throws -> TaskRecord?
  {
    try write {
      guard
        var task = try decode(
          TaskRecord.self,
          rowsSync("SELECT body FROM tasks WHERE project_id = ? AND id = ?", [.text(project), .text(id)])
        ).first, task.revision == expectedRevision
      else { return nil }
      if let status = change.status { task.status = status }
      if let owner = change.owner { task.owner = owner }
      if let priority = change.priority { task.priority = priority }
      task.updatedAt = change.updatedAt
      task.revision += 1
      try runSync(
        "UPDATE tasks SET body = ? WHERE project_id = ? AND id = ?",
        [.text(try json(task)), .text(project), .text(id)])
      return task
    }
  }

  func approvals(project: String, limit: Int) async throws -> [ApprovalRecord] {
    try decode(
      ApprovalRecord.self,
      rowsSync(
        "SELECT body FROM approvals WHERE project_id = ? ORDER BY created_at DESC, rowid DESC LIMIT ?",
        [.text(project), .int(limit)]))
  }

  func insert(approval: ApprovalRecord, project: String) async throws {
    let body = try json(approval)
    try write {
      _ = try runSync(
        "INSERT INTO approvals(project_id, id, created_at, body) VALUES (?, ?, ?, ?)",
        [.text(project), .text(approval.id), .text(approval.createdAt), .text(body)])
    }
  }

  func approval(project: String, id: String) async throws -> ApprovalRecord? {
    try decode(
      ApprovalRecord.self,
      rowsSync("SELECT body FROM approvals WHERE project_id = ? AND id = ?", [.text(project), .text(id)])
    ).first
  }

  func decideApproval(project: String, id: String, decision: String, at: String) async throws
    -> ApprovalRecord?
  {
    try write {
      guard
        var record = try decode(
          ApprovalRecord.self,
          rowsSync("SELECT body FROM approvals WHERE project_id = ? AND id = ?", [.text(project), .text(id)])
        ).first, record.status == "pending"
      else { return nil }
      record.status = decision
      record.decidedAt = at
      record.revision += 1
      try runSync(
        "UPDATE approvals SET body = ? WHERE project_id = ? AND id = ?",
        [.text(try json(record)), .text(project), .text(id)])
      return record
    }
  }
}

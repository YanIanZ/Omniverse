import Foundation
import Logging
import MongoKitten

public actor MongoStore {
  public nonisolated let binding: ProjectBinding
  public let dataRoot: URL
  public let config: StoreConfig
  public let cache: DiskCache
  let db: MongoDatabase
  private struct Metadata: Codable {
    enum CodingKeys: String, CodingKey {
      case schemaVersion = "schema_version"
      case storeID = "store_id"
    }

    var schemaVersion: Int
    var storeID: String
  }
  private init(binding: ProjectBinding, root: URL, config: StoreConfig, db: MongoDatabase) {
    self.binding = binding
    self.dataRoot = root
    self.config = config
    self.db = db
    cache = DiskCache(
      directory: root.appendingPathComponent("cache/retrieval"), maxBytes: config.cacheMaxBytes,
      ttl: TimeInterval(config.cacheTTLSeconds))
  }
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
  public static func initialize(
    dataDir: String, project: String, uri: String? = nil, cacheMaxBytes: Int = 32 * 1024 * 1024
  ) async throws -> MongoStore {
    let root = canonical(dataDir)
    let binding = try ProjectBinding(path: project)
    let file = root.appendingPathComponent("meta.json")
    if FileManager.default.fileExists(atPath: file.path) {
      return try await open(dataDir: dataDir, project: project)
    }
    guard (0...2048 * 1024 * 1024).contains(cacheMaxBytes) else {
      throw MemoError.invalid("cache quota out of range")
    }
    // Same precedence as open(): the environment wins, so init and later reads use one database.
    let address =
      ProcessInfo.processInfo.environment["OMNIMEM_MONGO_URI"] ?? uri
      ?? "mongodb://127.0.0.1:27017/omnimemo"
    // Credentials only come from the process environment, never the on-disk pointer.
    let credentialed =
      address.range(of: "mongodb://[^/@]+:[^/@]+@", options: .regularExpression) != nil
    if credentialed && ProcessInfo.processInfo.environment["OMNIMEM_MONGO_URI"] != address {
      throw MemoError.invalid("supply credentialed URI via OMNIMEM_MONGO_URI")
    }
    let db = try await connect(address)
    do {
      var meta = try await db["omnimem_meta"].findOne(["_id": "store"], as: Metadata.self)
      if meta == nil {
        let candidate = Metadata(schemaVersion: 1, storeID: UUID().uuidString.lowercased())
        var doc = try BSONEncoder().encode(candidate)
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
      let storedURI =
        credentialed
        ? address.replacingOccurrences(
          of: "(?<=mongodb://)[^/@]*@", with: "", options: .regularExpression) : address
      let config = StoreConfig(
        schemaVersion: 1, storeID: meta.storeID, mongoURI: storedURI,
        cacheMaxBytes: cacheMaxBytes, cacheTTLSeconds: 86400)
      try privateDirectory(root)
      try protectedWrite(try encodeJSON(config, pretty: true), to: file)
      return MongoStore(binding: binding, root: root, config: config, db: db)
    } catch {
      await (db.pool as? MongoCluster)?.disconnect()
      throw safeError(error)
    }
  }
  public static func open(dataDir: String, project: String) async throws -> MongoStore {
    let root = canonical(dataDir)
    let file = root.appendingPathComponent("meta.json")
    guard let data = try? Data(contentsOf: file), data.count < 16384,
      let config = try? JSONDecoder().decode(StoreConfig.self, from: data)
    else { throw MemoError.storageUnavailable }
    guard config.schemaVersion == 1 else { throw MemoError.invalid("unsupported schema version") }
    guard (0...2048 * 1024 * 1024).contains(config.cacheMaxBytes), config.cacheTTLSeconds >= 0
    else { throw MemoError.invalid("invalid storage config") }
    let binding = try ProjectBinding(path: project)
    let db = try await connect(
      ProcessInfo.processInfo.environment["OMNIMEM_MONGO_URI"] ?? config.mongoURI)
    do {
      guard let meta = try await db["omnimem_meta"].findOne(["_id": "store"], as: Metadata.self),
        meta.schemaVersion == 1, meta.storeID == config.storeID
      else { throw MemoError.storageUnavailable }
      return MongoStore(binding: binding, root: root, config: config, db: db)
    } catch {
      await (db.pool as? MongoCluster)?.disconnect()
      throw safeError(error)
    }
  }
  public func close() async { await (db.pool as? MongoCluster)?.disconnect() }
  func validate() throws {
    try binding.validate()
    guard dataRoot.resolvingSymlinksInPath() == dataRoot,
      let data = try? Data(contentsOf: dataRoot.appendingPathComponent("meta.json")),
      let current = try? JSONDecoder().decode(StoreConfig.self, from: data), current == config
    else { throw MemoError.storageUnavailable }
  }
  public func save(_ input: SaveInput, agent: String = "cli") async throws -> SaveResult {
    try validate()
    guard
      ["fact", "decision", "task", "issue", "preference", "insight", "checkpoint"].contains(
        input.kind), !input.title.isEmpty, !input.content.isEmpty,
      input.title.utf8.count <= 240, input.content.utf8.count <= 32768,
      (input.sources ?? []).count <= 8, (input.tags ?? []).count <= 16,
      agent.utf8.count <= 64, (input.idempotencyKey?.utf8.count ?? 0) <= 128,
      (input.subject?.utf8.count ?? 0) <= 128, (input.predicate?.utf8.count ?? 0) <= 128
    else { throw MemoError.invalid("kind, content or field limits") }
    for tag in input.tags ?? [] {
      guard tag.utf8.count <= 128 else { throw MemoError.invalid("tag too long") }
    }
    try SecretFilter.check(String(decoding: try encodeJSON(input), as: UTF8.self))
    try SecretFilter.check(agent)
    let evidence = try (input.sources ?? []).map { try binding.evidence($0) }
    let branch = binding.branch
    let head = binding.head
    var normalized = input
    normalized.idempotencyKey = nil
    normalized.sources = evidence.map(\.path).sorted()
    normalized.tags = Array(Set(input.tags ?? [])).sorted()
    let requestHash = digest(try encodeJSON(normalized) + Data(branch.utf8))
    let fingerprint = digest(
      try encodeJSON(normalized) + Data(branch.utf8)
        + encodeJSON(evidence.sorted { $0.path < $1.path }))
    let dedup = input.idempotencyKey.map { "key:" + digest($0) } ?? "content:" + fingerprint
    let query: Document = ["project_id": binding.id, "dedup_key": dedup]
    let records = db["omnimem_records"]
    do {
      if let existing = try await records.findOne(query, as: MemoryRecord.self) {
        if input.idempotencyKey != nil && existing.requestHash != requestHash {
          throw MemoError.conflict
        }
        return SaveResult(id: existing.id, disposition: "merged", state: existing.state)
      }
      let record = MemoryRecord(
        id: UUID().uuidString.lowercased(), projectID: binding.id, branch: branch, gitHead: head,
        kind: input.kind, title: input.title, content: input.content, tags: input.tags ?? [],
        sources: evidence, state: evidence.isEmpty ? "unverified" : "active", agent: agent,
        createdAt: nowISO(), fingerprint: fingerprint, requestHash: requestHash, dedupKey: dedup,
        subject: input.subject, predicate: input.predicate, warnings: nil)
      let result = try await records.insertEncoded(record)
      if !(result.writeErrors ?? []).isEmpty {
        if let existing = try await records.findOne(query, as: MemoryRecord.self) {
          if input.idempotencyKey != nil && existing.requestHash != requestHash {
            throw MemoError.conflict
          }
          return SaveResult(id: existing.id, disposition: "merged", state: existing.state)
        }
        throw MemoError.database("write rejected")
      }
      return SaveResult(id: record.id, disposition: "created", state: record.state)
    } catch { throw Self.safeError(error) }
  }
  public func checkpoint(_ input: CheckpointInput, agent: String = "cli") async throws -> SaveResult
  {
    for list in [input.done, input.next, input.blocked, input.tests, input.changedFiles] {
      guard (list?.count ?? 0) <= 32 else { throw MemoError.invalid("checkpoint list too long") }
    }
    let content = String(decoding: try encodeJSON(input), as: UTF8.self)
    // Checkpoints claim progress, not independently verified test execution.
    return try await save(
      SaveInput(
        kind: "checkpoint", title: input.title ?? "Session handoff", content: content,
        sources: input.changedFiles ?? [], idempotencyKey: input.idempotencyKey), agent: agent)
  }
  private func checked(_ memo: MemoryRecord) -> MemoryRecord {
    var memo = memo
    var warnings: [String] = []
    if memo.branch != binding.branch { warnings.append("different_branch") }
    for source in memo.sources {
      if (try? binding.evidence(source.path)) != source {
        memo.state = "stale"
        warnings.append("source_changed:" + source.path)
      }
    }
    memo.warnings = warnings.isEmpty ? nil : warnings
    return memo
  }
  public func get(_ id: String) async throws -> MemoryRecord {
    try validate()
    guard id.utf8.count <= 128 else { throw MemoError.invalid("invalid id") }
    do {
      guard
        let record = try await db["omnimem_records"].findOne(
          ["project_id": binding.id, "id": id], as: MemoryRecord.self)
      else { throw MemoError.notFound }
      return checked(record)
    } catch { throw Self.safeError(error) }
  }
  public func search(_ query: String = "", limit: Int = 8) async throws -> [MemoryRecord] {
    try validate()
    guard query.utf8.count <= 1024, (1...100).contains(limit) else {
      throw MemoError.invalid("query or limit out of bounds")
    }
    let collection = db["omnimem_records"]
    do {
      var matches: [MemoryRecord] = []
      if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let text: Document = [
          "project_id": binding.id, "$text": ["$search": query, "$language": "none"],
        ]
        matches = try await collection.find(text).sort(["score": ["$meta": "textScore"]]).limit(
          limit
        ).decode(MemoryRecord.self).drain()
        if matches.count < limit {
          let escaped = NSRegularExpression.escapedPattern(for: query)
          let regex: Document = ["$regex": escaped, "$options": "i"]
          let fallback: Document = [
            "project_id": binding.id,
            "$or": [
              ["title": regex] as Document, ["content": regex] as Document,
              ["tags": regex] as Document,
            ],
          ]
          let extra = try await collection.find(fallback).sort(["created_at": -1]).limit(limit)
            .decode(MemoryRecord.self).drain()
          let ids = Set(matches.map(\.id))
          matches += extra.filter { !ids.contains($0.id) }
        }
      } else {
        matches = try await collection.find(["project_id": binding.id]).sort(["created_at": -1])
          .limit(limit).decode(MemoryRecord.self).drain()
      }
      return Array(matches.prefix(limit)).map { checked($0) }
    } catch { throw Self.safeError(error) }
  }
  public func delete(_ id: String) async throws {
    try validate()
    guard id.utf8.count <= 128 else { throw MemoError.invalid("invalid id") }
    do {
      let result = try await db["omnimem_records"].deleteOne(where: [
        "project_id": binding.id, "id": id,
      ])
      guard result.deletes == 1 else { throw MemoError.notFound }
      try cache.clear()
    } catch { throw Self.safeError(error) }
  }
  public func exportRecords() async throws -> [MemoryRecord] {
    try validate()
    // CLI export is intentionally explicit and separate from MCP discovery.
    do {
      let count = try await db["omnimem_records"].count(["project_id": binding.id])
      guard count <= 10000 else {
        throw MemoError.invalid("export exceeds 10000 records; use an administrative backup")
      }
      return try await db["omnimem_records"].find(["project_id": binding.id]).limit(10000).decode(
        MemoryRecord.self
      ).drain()
    } catch { throw Self.safeError(error) }
  }
  public func status() async throws -> StoreStatus {
    try validate()
    do {
      let count = try await db["omnimem_records"].count(["project_id": binding.id])
      return StoreStatus(
        projectID: binding.id, records: count, cacheBytes: try cache.size(),
        cacheMaxBytes: config.cacheMaxBytes)
    } catch { throw Self.safeError(error) }
  }
  public func clearCache() throws {
    try validate()
    try cache.clear()
  }
  public static func safeError(_ error: Error) -> MemoError {
    error as? MemoError ?? .database("operation failed; check server availability and permissions")
  }
}

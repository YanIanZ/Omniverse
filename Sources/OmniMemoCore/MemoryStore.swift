import Foundation
import MongoKitten

/// Opt-in automatic capture (PRD FR-15). Stored as `<data-dir>/autosave.json`; all off by default.
public struct AutoSave: Codable, Sendable, Equatable {
  public var checkpoints = false
  public var transitions = false
  public var prompts = false
  public init(checkpoints: Bool = false, transitions: Bool = false, prompts: Bool = false) {
    self.checkpoints = checkpoints
    self.transitions = transitions
    self.prompts = prompts
  }
  public static func load(_ root: URL) -> AutoSave {
    guard let data = try? Data(contentsOf: root.appendingPathComponent("autosave.json")),
      data.count < 1024, let value = try? JSONDecoder().decode(AutoSave.self, from: data)
    else { return AutoSave() }
    return value
  }
  public func write(_ root: URL) throws {
    try protectedWrite(try encodeJSON(self, pretty: true), to: root.appendingPathComponent("autosave.json"))
  }
}

/// Project-scoped memory and coordination. Business rules live here; `StoreBackend`
/// persists them in MongoDB (`mongodb` profile) or SQLite (`sqlite` profile).
public actor MemoryStore {
  public static let kinds = ["fact", "decision", "task", "issue", "preference", "insight", "checkpoint", "prompt"]
  public nonisolated let binding: ProjectBinding
  public nonisolated let dataRoot: URL
  public nonisolated var redisURL: String? { RedisSignal.configuredURL(dataRoot: dataRoot) }
  public nonisolated var autoSave: AutoSave { AutoSave.load(dataRoot) }
  public let config: StoreConfig
  public let cache: DiskCache
  let backend: any StoreBackend
  /// Runtime tables are prepared before the first coordination write in each process.
  var runtimeIndexesReady = false
  /// Test access to the MongoDB profile's database.
  var mongoDatabase: MongoDatabase? { (backend as? MongoBackend)?.db }
  public nonisolated var profile: String { config.profile }

  private init(binding: ProjectBinding, root: URL, config: StoreConfig, backend: any StoreBackend) {
    self.binding = binding
    self.dataRoot = root
    self.config = config
    self.backend = backend
    cache = DiskCache(
      directory: root.appendingPathComponent("cache/retrieval"), maxBytes: config.cacheMaxBytes,
      ttl: TimeInterval(config.cacheTTLSeconds))
  }

  /// Explicit, one-time choice of storage profile; there is no automatic fallback between them.
  public static func initialize(
    dataDir: String, project: String, uri: String? = nil, cacheMaxBytes: Int = 32 * 1024 * 1024,
    backend profile: String = "mongodb"
  ) async throws -> MemoryStore {
    let root = canonical(dataDir)
    let binding = try ProjectBinding(path: project)
    let file = root.appendingPathComponent("meta.json")
    if FileManager.default.fileExists(atPath: file.path) {
      return try await open(dataDir: dataDir, project: project)
    }
    guard (0...2048 * 1024 * 1024).contains(cacheMaxBytes) else {
      throw MemoError.invalid("cache quota out of range")
    }
    guard ["mongodb", "sqlite"].contains(profile) else {
      throw MemoError.invalid("backend must be mongodb or sqlite")
    }
    if profile == "sqlite" {
      try privateDirectory(root)
      let (backend, storeID) = try SQLiteBackend.initialize(root: root)
      let config = StoreConfig(
        schemaVersion: 1, storeID: storeID, mongoURI: nil, cacheMaxBytes: cacheMaxBytes,
        cacheTTLSeconds: 86400, backend: "sqlite")
      try protectedWrite(try encodeJSON(config, pretty: true), to: file)
      return MemoryStore(binding: binding, root: root, config: config, backend: backend)
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
    do {
      let (backend, storeID) = try await MongoBackend.initialize(address: address)
      let storedURI =
        credentialed
        ? address.replacingOccurrences(
          of: "(?<=mongodb://)[^/@]*@", with: "", options: .regularExpression) : address
      let config = StoreConfig(
        schemaVersion: 1, storeID: storeID, mongoURI: storedURI, cacheMaxBytes: cacheMaxBytes,
        cacheTTLSeconds: 86400, backend: nil)
      do {
        try privateDirectory(root)
        try protectedWrite(try encodeJSON(config, pretty: true), to: file)
      } catch {
        await backend.close()
        throw error
      }
      return MemoryStore(binding: binding, root: root, config: config, backend: backend)
    } catch { throw safeError(error) }
  }

  public static func open(dataDir: String, project: String) async throws -> MemoryStore {
    let root = canonical(dataDir)
    let file = root.appendingPathComponent("meta.json")
    guard let data = try? Data(contentsOf: file), data.count < 16384,
      let config = try? JSONDecoder().decode(StoreConfig.self, from: data)
    else { throw MemoError.storageUnavailable }
    guard config.schemaVersion == 1 else { throw MemoError.invalid("unsupported schema version") }
    guard (0...2048 * 1024 * 1024).contains(config.cacheMaxBytes), config.cacheTTLSeconds >= 0
    else { throw MemoError.invalid("invalid storage config") }
    let binding = try ProjectBinding(path: project)
    do {
      switch config.profile {
      case "sqlite":
        let backend = try SQLiteBackend.open(root: root, storeID: config.storeID)
        return MemoryStore(binding: binding, root: root, config: config, backend: backend)
      case "mongodb":
        guard let uri = ProcessInfo.processInfo.environment["OMNIMEM_MONGO_URI"] ?? config.mongoURI
        else { throw MemoError.storageUnavailable }
        let backend = try await MongoBackend.open(address: uri, storeID: config.storeID)
        return MemoryStore(binding: binding, root: root, config: config, backend: backend)
      default:
        throw MemoError.invalid("unknown storage profile")
      }
    } catch { throw safeError(error) }
  }

  public func close() async { await backend.close() }

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
      Self.kinds.contains(input.kind), !input.title.isEmpty, !input.content.isEmpty,
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
    do {
      func merged(_ existing: MemoryRecord) throws -> SaveResult {
        if input.idempotencyKey != nil && existing.requestHash != requestHash {
          throw MemoError.conflict
        }
        return SaveResult(id: existing.id, disposition: "merged", state: existing.state)
      }
      if let existing = try await backend.record(project: binding.id, dedupKey: dedup) {
        return try merged(existing)
      }
      let record = MemoryRecord(
        id: UUID().uuidString.lowercased(), projectID: binding.id, branch: branch, gitHead: head,
        kind: input.kind, title: input.title, content: input.content, tags: input.tags ?? [],
        sources: evidence, state: evidence.isEmpty ? "unverified" : "active", agent: agent,
        createdAt: nowISO(), fingerprint: fingerprint, requestHash: requestHash, dedupKey: dedup,
        subject: input.subject, predicate: input.predicate, warnings: nil)
      if try await backend.insert(record: record) {
        return SaveResult(id: record.id, disposition: "created", state: record.state)
      }
      // Another writer won the same dedup key between our read and insert.
      guard let existing = try await backend.record(project: binding.id, dedupKey: dedup) else {
        throw MemoError.database("write rejected")
      }
      return try merged(existing)
    } catch { throw Self.safeError(error) }
  }

  public func checkpoint(_ input: CheckpointInput, agent: String = "cli") async throws -> SaveResult
  {
    for list in [input.done, input.next, input.blocked, input.tests, input.changedFiles] {
      guard (list?.count ?? 0) <= 32 else { throw MemoError.invalid("checkpoint list too long") }
    }
    let content = String(decoding: try encodeJSON(input), as: UTF8.self)
    // Checkpoints claim progress, not independently verified test execution.
    let result = try await save(
      SaveInput(
        kind: "checkpoint", title: input.title ?? "Session handoff", content: content,
        sources: input.changedFiles ?? [], idempotencyKey: input.idempotencyKey), agent: agent)
    if result.disposition == "created" {
      _ = try? await emit(
        "memory.checkpoint.created", entity: result.id,
        data: ["agent": agent, "status": result.state])
    }
    return result
  }

  private func checked(_ memo: MemoryRecord) -> MemoryRecord {
    var memo = memo
    var warnings: [String] = []
    if memo.branch != binding.branch { warnings.append("different_branch") }
    for source in memo.sources where (try? binding.evidence(source.path)) != source {
      memo.state = "stale"
      warnings.append("source_changed:" + source.path)
    }
    memo.warnings = warnings.isEmpty ? nil : warnings
    return memo
  }

  public func get(_ id: String) async throws -> MemoryRecord {
    try validate()
    guard id.utf8.count <= 128 else { throw MemoError.invalid("invalid id") }
    do {
      guard let record = try await backend.record(project: binding.id, id: id) else {
        throw MemoError.notFound
      }
      return checked(record)
    } catch { throw Self.safeError(error) }
  }

  public func search(_ query: String = "", limit: Int = 8) async throws -> [MemoryRecord] {
    try validate()
    guard query.utf8.count <= 1024, (1...100).contains(limit) else {
      throw MemoError.invalid("query or limit out of bounds")
    }
    do {
      let found =
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? try await backend.recent(project: binding.id, limit: limit)
        : try await backend.search(project: binding.id, query: query, limit: limit)
      return found.prefix(limit).map { checked($0) }
    } catch { throw Self.safeError(error) }
  }

  public func delete(_ id: String) async throws {
    try validate()
    guard id.utf8.count <= 128 else { throw MemoError.invalid("invalid id") }
    do {
      guard try await backend.deleteRecord(project: binding.id, id: id) else {
        throw MemoError.notFound
      }
      try cache.clear()
    } catch { throw Self.safeError(error) }
  }

  public func exportRecords() async throws -> [MemoryRecord] {
    try validate()
    // CLI export is intentionally explicit and separate from MCP discovery.
    do {
      guard try await backend.countRecords(project: binding.id) <= 10000 else {
        throw MemoError.invalid("export exceeds 10000 records; use an administrative backup")
      }
      return try await backend.recent(project: binding.id, limit: 10000)
    } catch { throw Self.safeError(error) }
  }

  public func status() async throws -> StoreStatus {
    try validate()
    do {
      var status = StoreStatus(
        projectID: binding.id, records: try await backend.countRecords(project: binding.id),
        cacheBytes: try cache.size(), cacheMaxBytes: config.cacheMaxBytes)
      status.backend = profile == "sqlite" ? "SQLite" : "MongoDB"
      return status
    } catch { throw Self.safeError(error) }
  }

  public func clearCache() throws {
    try validate()
    try cache.clear()
  }

  public static func safeError(_ error: Error) -> MemoError {
    if let memo = error as? MemoError { return memo }
    // Opt-in local diagnostics; never part of MCP or HTTP responses.
    if ProcessInfo.processInfo.environment["OMNIMEM_DEBUG"] == "1" {
      FileHandle.standardError.write(Data("omnimem debug: \(String(reflecting: error))\n".utf8))
    }
    return .database("operation failed; check server availability and permissions")
  }
}

/// Earlier releases named the store after its only backend.
public typealias MongoStore = MemoryStore

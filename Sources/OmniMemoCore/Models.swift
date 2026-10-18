import Foundation

public enum MemoError: Error, LocalizedError {
  case invalid(String)
  case storageUnavailable
  case database(String)
  case denied, notFound, secret, conflict, revisionConflict
  public var errorDescription: String? {
    switch self {
    case .invalid(let message): return "invalid_request: \(message)"
    case .storageUnavailable:
      return "storage_unavailable: initialize explicitly or reconnect the configured volume"
    case .database(let message): return "database_error: \(message)"
    case .denied: return "scope_denied: request is outside the authorized project"
    case .notFound: return "not_found"
    case .secret: return "secret_detected: rejected content; no data saved"
    case .conflict: return "idempotency_conflict: key already used with different content"
    case .revisionConflict: return "revision_conflict: record changed; refresh and retry"
    }
  }
}

public struct Evidence: Codable, Sendable, Equatable {
  public var path: String
  public var sha256: String
}
public struct SaveInput: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case kind
    case title
    case content
    case sources
    case tags
    case idempotencyKey = "idempotency_key"
    case subject
    case predicate
  }

  public var kind: String
  public var title: String
  public var content: String
  public var sources: [String]?
  public var tags: [String]?
  public var idempotencyKey: String?
  public var subject: String?
  public var predicate: String?
  public init(
    kind: String = "fact", title: String, content: String, sources: [String] = [],
    tags: [String] = [], idempotencyKey: String? = nil, subject: String? = nil,
    predicate: String? = nil
  ) {
    self.kind = kind
    self.title = title
    self.content = content
    self.sources = sources
    self.tags = tags
    self.idempotencyKey = idempotencyKey
    self.subject = subject
    self.predicate = predicate
  }
}
public struct CheckpointInput: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case title
    case done
    case next
    case blocked
    case tests
    case changedFiles = "changed_files"
    case idempotencyKey = "idempotency_key"
  }

  public var title: String?
  public var done: [String]?
  public var next: [String]?
  public var blocked: [String]?
  public var tests: [String]?
  public var changedFiles: [String]?
  public var idempotencyKey: String?
  public init(
    title: String = "Session handoff", done: [String] = [], next: [String] = [],
    blocked: [String] = [], tests: [String] = [], changedFiles: [String] = [],
    idempotencyKey: String? = nil
  ) {
    self.title = title
    self.done = done
    self.next = next
    self.blocked = blocked
    self.tests = tests
    self.changedFiles = changedFiles
    self.idempotencyKey = idempotencyKey
  }
}
public struct MemoryRecord: Codable, Sendable, Equatable {
  enum CodingKeys: String, CodingKey {
    case id
    case projectID = "project_id"
    case branch
    case gitHead = "git_head"
    case kind
    case title
    case content
    case tags
    case sources
    case state
    case agent
    case createdAt = "created_at"
    case fingerprint
    case requestHash = "request_hash"
    case dedupKey = "dedup_key"
    case subject
    case predicate
    case warnings
  }

  public var id: String
  public var projectID: String
  public var branch: String
  public var gitHead: String
  public var kind: String
  public var title: String
  public var content: String
  public var tags: [String]
  public var sources: [Evidence]
  public var state: String
  public var agent: String
  public var createdAt: String
  public var fingerprint: String
  public var requestHash: String
  public var dedupKey: String
  public var subject: String?
  public var predicate: String?
  public var warnings: [String]?
}
public struct SaveResult: Codable, Sendable {
  public var id: String
  public var disposition: String
  public var state: String
}
public struct StoreConfig: Codable, Sendable, Equatable {
  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case storeID = "store_id"
    case mongoURI = "mongo_uri"
    case cacheMaxBytes = "cache_max_bytes"
    case cacheTTLSeconds = "cache_ttl_seconds"
    case backend
  }

  public var schemaVersion: Int
  public var storeID: String
  /// Present for the `mongodb` profile only.
  public var mongoURI: String?
  public var cacheMaxBytes: Int
  public var cacheTTLSeconds: Int
  /// Storage profile; stores created before profiles existed are MongoDB.
  public var backend: String?
  public var profile: String { backend ?? "mongodb" }
}
public struct StoreStatus: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case projectID = "project_id"
    case records
    case cacheBytes = "cache_bytes"
    case cacheMaxBytes = "cache_max_bytes"
    case backend
  }

  public var schemaVersion = 1
  public var projectID: String
  public var records: Int
  public var cacheBytes: Int
  public var cacheMaxBytes: Int
  public var backend = "MongoDB"
}
public func encodeJSON<T: Encodable>(_ value: T, pretty: Bool = false) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting =
    pretty
    ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    : [.sortedKeys, .withoutEscapingSlashes]
  return try encoder.encode(value)
}

import Foundation

public struct MemoryBrief: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case id
    case title
    case summary
    case state
    case sourceRefs = "source_refs"
  }

  public var id: String
  public var title: String
  public var summary: String
  public var state: String
  public var sourceRefs: [String]?
  public init(id: String, title: String, summary: String, state: String, sourceRefs: [String]?) {
    self.id = id
    self.title = title
    self.summary = summary
    self.state = state
    self.sourceRefs = sourceRefs
  }
}
public struct ContextEnvelope: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case result
    case warnings
    case estimatedTokens = "estimated_tokens"
    case tokenCountMethod = "token_count_method"
  }

  public var schemaVersion = 1
  public var result: [MemoryBrief]
  public var warnings: [String]
  public var estimatedTokens: Int
  public var tokenCountMethod = "utf8_upper_bound"
}
public enum ContextBudget {
  // A pessimistic upper bound for byte-level tokenizers; the MCP text wrapper is counted too.
  // Includes a 64-byte JSON-RPC id reserve. No claim of an exact provider token count.
  public static func bound(_ payload: Data) throws -> Int {
    let text = String(decoding: payload, as: UTF8.self)
    let wrapper: [String: Any] = [
      "jsonrpc": "2.0", "id": String(repeating: "i", count: 64),
      "result": ["content": [["type": "text", "text": text]], "isError": false],
    ]
    return try JSONSerialization.data(
      withJSONObject: wrapper, options: [.sortedKeys, .withoutEscapingSlashes]
    ).count
  }
  public static func fit(_ records: [MemoryRecord], maxTokens: Int) throws -> Data {
    guard (256...16384).contains(maxTokens) else {
      throw MemoError.invalid(
        "max_tokens must be 256...16384; lower budgets cannot fit the response envelope")
    }
    var envelope = ContextEnvelope(result: [], warnings: [], estimatedTokens: 0)
    func render(_ e: ContextEnvelope) throws -> Data {
      var e = e
      // Digit count converges in a few iterations.
      for _ in 0..<6 { e.estimatedTokens = try bound(encodeJSON(e)) }
      return try encodeJSON(e)
    }
    var data = try render(envelope)
    guard try bound(data) <= maxTokens else {
      throw MemoError.invalid("budget too small for metadata")
    }
    for record in records {
      var accepted = false
      for length in [320, 160, 80, 0] {
        var candidate = envelope
        let brief = MemoryBrief(
          id: record.id, title: String(record.title.prefix(80)),
          summary: String(record.content.prefix(length)), state: record.state,
          sourceRefs: record.sources.isEmpty ? nil : Array(record.sources.prefix(2).map(\.path)))
        candidate.result.append(brief)
        candidate.warnings = Array(Set(envelope.warnings + (record.warnings ?? []))).sorted()
        let trial = try render(candidate)
        if try bound(trial) <= maxTokens {
          envelope = candidate
          data = trial
          accepted = true
          break
        }
      }
      if !accepted { continue }
    }
    return data
  }
}
extension MongoStore {
  public func context(task: String, maxTokens: Int = 500) async throws -> Data {
    let matches = try await search(task, limit: 8)
    let recent = try await search(limit: 8)
    var records: [MemoryRecord] = []
    if let checkpoint = recent.first(where: { $0.kind == "checkpoint" }) {
      records.append(checkpoint)
    }
    let ids = Set(records.map(\.id))
    records += matches.filter { !ids.contains($0.id) }
    // Fresh records and source checks are part of the key; DB is consulted on every call.
    let key = digest(try encodeJSON(records)) + ":" + digest(task) + ":" + String(maxTokens) + ":v1"
    if let hit = cache.get(key), (try? ContextBudget.bound(hit)) ?? Int.max <= maxTokens {
      return hit
    }
    let output = try ContextBudget.fit(records, maxTokens: maxTokens)
    // Cache errors are recoverable; the memory store remains authoritative.
    try? cache.put(key, value: output)
    return output
  }
}

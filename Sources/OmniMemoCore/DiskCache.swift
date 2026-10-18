import Foundation

public struct DiskCache: Sendable {
  public let directory: URL
  public let maxBytes: Int
  public let ttl: TimeInterval
  private struct Entry: Codable {
    var created: Date
    var value: Data
  }
  public init(directory: URL, maxBytes: Int = 32 * 1024 * 1024, ttl: TimeInterval = 86400) {
    self.directory = directory
    self.maxBytes = max(0, maxBytes)
    self.ttl = ttl
  }
  public func get(_ key: String) -> Data? {
    let p = directory.appendingPathComponent(digest(key) + ".json")
    guard let a = try? p.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
      a.isRegularFile == true, (a.fileSize ?? Int.max) <= maxBytes,
      let data = try? Data(contentsOf: p),
      let entry = try? JSONDecoder().decode(Entry.self, from: data),
      Date().timeIntervalSince(entry.created) <= ttl
    else { return nil }
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: p.path)
    return entry.value
  }
  public func put(_ key: String, value: Data) throws {
    guard maxBytes > 0 else { return }
    let data = try encodeJSON(Entry(created: Date(), value: value))
    guard data.count <= maxBytes else { return }
    try privateDirectory(directory)
    try protectedWrite(data, to: directory.appendingPathComponent(digest(key) + ".json"))
    try evict()
  }
  private func files() throws -> [URL] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
    ).filter { $0.pathExtension == "json" && !$0.hasDirectoryPath }
  }
  public func size() throws -> Int {
    try files().reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
  }
  public func evict() throws {
    let entries = try files().map { url -> (URL, Int, Date) in
      let a = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
      return (url, a.fileSize ?? 0, a.contentModificationDate ?? .distantPast)
    }.sorted { $0.2 < $1.2 }
    var total = entries.reduce(0) { $0 + $1.1 }
    for (url, size, date) in entries where total > maxBytes || Date().timeIntervalSince(date) > ttl
    {
      if (try? FileManager.default.removeItem(at: url)) != nil { total -= size }
    }
  }
  public func clear() throws {
    for url in try files() { try FileManager.default.removeItem(at: url) }
  }
}

import XCTest

@testable import OmniMemoCore

final class CoreTests: XCTestCase {
  func workspace() throws -> URL {
    let base = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["OMNIMEM_TEST_ROOT"]
        ?? NSTemporaryDirectory())
    let root = base.appendingPathComponent(UUID().uuidString)
    try privateDirectory(root)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return root
  }
  func testSecretFilter() throws {
    for text in [
      "password=not-a-real-password", "api_key: abcdef123456",
      "-----BEGIN OPENSSH PRIVATE KEY-----", "github_pat_" + String(repeating: "x", count: 40),
      "mongodb://user:password@localhost/db",
    ] {
      XCTAssertThrowsError(try SecretFilter.check(text))
      XCTAssertFalse(MemoError.secret.localizedDescription.contains(text))
    }
    XCTAssertNoThrow(
      try SecretFilter.check("Prefer project-scoped memory and SQLite is replaced by MongoDB."))
  }
  func testCanonicalSourceAndSymlinkEscape() throws {
    let root = try workspace()
    let project = root.appendingPathComponent("project")
    try privateDirectory(project)
    let source = project.appendingPathComponent("src.swift")
    try Data("let x = 1".utf8).write(to: source)
    let binding = try ProjectBinding(path: project.path)
    let a = try binding.evidence("src.swift")
    XCTAssertEqual(a.path, "src.swift")
    XCTAssertEqual(a.sha256.count, 64)
    let outside = root.appendingPathComponent("outside.swift")
    try Data("outside".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(
      at: project.appendingPathComponent("escape"), withDestinationURL: outside)
    XCTAssertThrowsError(try binding.evidence("escape"))
    XCTAssertThrowsError(try binding.evidence("../outside.swift"))
    try Data("secret".utf8).write(to: project.appendingPathComponent(".env"))
    XCTAssertThrowsError(try binding.evidence(".env"))
  }
  func testBindingRejectsReplacedRoot() throws {
    let root = try workspace()
    let p = root.appendingPathComponent("project")
    try privateDirectory(p)
    let binding = try ProjectBinding(path: p.path)
    try FileManager.default.moveItem(at: p, to: root.appendingPathComponent("old"))
    try privateDirectory(p)
    XCTAssertThrowsError(try binding.validate())
  }
  func testCacheQuotaTTLAndClear() throws {
    let root = try workspace()
    let cache = DiskCache(directory: root.appendingPathComponent("cache"), maxBytes: 1800, ttl: 10)
    for i in 0..<20 { try cache.put(String(i), value: Data(repeating: 65, count: 300)) }
    XCTAssertLessThanOrEqual(try cache.size(), 1800)
    XCTAssertEqual(cache.get("19"), Data(repeating: 65, count: 300))
    let expired = DiskCache(directory: cache.directory, maxBytes: 1800, ttl: -1)
    XCTAssertNil(expired.get("19"))
    let memory = root.appendingPathComponent("memory.json")
    try Data("persist".utf8).write(to: memory)
    try cache.clear()
    XCTAssertEqual(try cache.size(), 0)
    XCTAssertTrue(FileManager.default.fileExists(atPath: memory.path))
  }
  func testBudgetIncludesEscapingAndUnicode() throws {
    let record = MemoryRecord(
      id: UUID().uuidString, projectID: "p", branch: "", gitHead: "", kind: "fact",
      title: "日本語 \"judul\"", content: String(repeating: "Unicode 🧠\\\"\n", count: 1000), tags: [],
      sources: [Evidence(path: "Sources/test.swift", sha256: "abc")], state: "active",
      agent: "test", createdAt: "now", fingerprint: "x", requestHash: "x", dedupKey: "x",
      subject: nil, predicate: nil, warnings: ["source_changed"])
    for budget in [500, 700, 1000, 2000] {
      let data = try ContextBudget.fit([record], maxTokens: budget)
      let envelope = try JSONDecoder().decode(ContextEnvelope.self, from: data)
      XCTAssertLessThanOrEqual(try ContextBudget.bound(data), budget)
      XCTAssertEqual(envelope.estimatedTokens, try ContextBudget.bound(data))
    }
    XCTAssertThrowsError(try ContextBudget.fit([record], maxTokens: 100))
  }
  func testAdapterPreviewApplyRoundTrip() throws {
    let root = try workspace()
    let project = root.appendingPathComponent("project")
    try privateDirectory(project)
    let installer = try AgentInstaller(
      configRoot: project.path, project: project.path, executable: "/tmp/omnimem",
      dataDir: root.appendingPathComponent("memory").path, agents: ["codex", "claude"])
    try privateDirectory(project.appendingPathComponent(".codex"))
    let toml = Data("model = \"existing\"\n".utf8)
    let json = Data("{\"mcpServers\":{\"existing\":{\"command\":\"hello\"}},\"custom\":true}".utf8)
    try toml.write(to: project.appendingPathComponent(".codex/config.toml"))
    try json.write(to: project.appendingPathComponent(".mcp.json"))
    XCTAssertTrue(installer.preview().requiresApply)
    XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent(".mcp.json")), json)
    try installer.apply()
    let first = try Data(contentsOf: project.appendingPathComponent(".codex/config.toml"))
    try installer.apply()
    XCTAssertEqual(
      first, try Data(contentsOf: project.appendingPathComponent(".codex/config.toml")))
    XCTAssertTrue(String(decoding: first, as: UTF8.self).contains("model = \"existing\""))
    _ = try installer.uninstall(apply: true)
    _ = try installer.uninstall(apply: true)
    XCTAssertEqual(toml, try Data(contentsOf: project.appendingPathComponent(".codex/config.toml")))
    XCTAssertEqual(json, try Data(contentsOf: project.appendingPathComponent(".mcp.json")))
  }
  func testUninstallRefusesEditedManagedEntry() throws {
    let root = try workspace()
    let installer = try AgentInstaller(
      configRoot: root.path, project: root.path, executable: "/tmp/omnimem", dataDir: root.path,
      agents: ["codex"])
    try installer.apply()
    let path = root.appendingPathComponent(".codex/config.toml")
    let edited = try String(contentsOf: path, encoding: .utf8).replacingOccurrences(
      of: "/tmp/omnimem", with: "/tmp/other")
    try Data(edited.utf8).write(to: path)
    XCTAssertThrowsError(try installer.uninstall(apply: true))
    XCTAssertEqual(edited, try String(contentsOf: path, encoding: .utf8))
  }
  func testAdapterRejectsConfigSymlinkEscape() throws {
    let root = try workspace()
    let project = root.appendingPathComponent("project")
    try privateDirectory(project)
    let outside = root.appendingPathComponent("outside")
    try privateDirectory(outside)
    try FileManager.default.createSymbolicLink(
      at: project.appendingPathComponent(".codex"), withDestinationURL: outside)
    let installer = try AgentInstaller(
      configRoot: project.path, project: project.path, executable: "/tmp/omnimem",
      dataDir: root.path, agents: ["codex"])
    XCTAssertThrowsError(try installer.apply())
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: outside.appendingPathComponent("config.toml").path))
  }
  func testInstallerManifestSymlinkEscape() throws {
    let root = try workspace()
    let project = root.appendingPathComponent("project")
    try privateDirectory(project)
    let outside = root.appendingPathComponent("outside")
    try privateDirectory(outside)
    try FileManager.default.createSymbolicLink(
      at: project.appendingPathComponent(".omnimemo-installer"), withDestinationURL: outside)
    let installer = try AgentInstaller(
      configRoot: project.path, project: project.path, executable: "/tmp/omnimem",
      dataDir: root.path, agents: ["codex"])
    XCTAssertThrowsError(try installer.apply())
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
  }

  func testClaudeConfigWithoutServersRoundTrip() throws {
    let root = try workspace()
    let initial = Data("{\"custom\":true}".utf8)
    let file = root.appendingPathComponent(".mcp.json")
    try initial.write(to: file)
    let installer = try AgentInstaller(
      configRoot: root.path, project: root.path, executable: "/tmp/omnimem", dataDir: root.path,
      agents: ["claude"])
    try installer.apply()
    _ = try installer.uninstall(apply: true)
    XCTAssertEqual(initial, try Data(contentsOf: file))
  }

}

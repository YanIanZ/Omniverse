import XCTest

@testable import OmniMemoCore

final class MongoTests: XCTestCase {
  /// Cleanup is registered on `owner`, the test that is running: a helper instance never runs,
  /// and some XCTest versions run its teardown blocks as soon as it is released.
  func fixture(owner: XCTestCase? = nil) async throws -> (URL, MemoryStore) {
    guard let uri = ProcessInfo.processInfo.environment["OMNIMEM_TEST_MONGO_URI"] else {
      throw XCTSkip("Set OMNIMEM_TEST_MONGO_URI for real MongoDB integration tests")
    }
    let base = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["OMNIMEM_TEST_ROOT"]
        ?? NSTemporaryDirectory())
    let root = base.appendingPathComponent(UUID().uuidString)
    let project = root.appendingPathComponent("project")
    try privateDirectory(project)
    try Data("let answer = 42\n".utf8).write(to: project.appendingPathComponent("main.swift"))
    let store = try await MemoryStore.initialize(
      dataDir: root.appendingPathComponent("memory").path, project: project.path, uri: uri)
    (owner ?? self).addTeardownBlock {
      await store.close()
      try? FileManager.default.removeItem(at: root)
    }
    return (root, store)
  }
  func testPersistenceDedupAndIdempotency() async throws {
    let (root, store) = try await fixture()
    let input = SaveInput(
      kind: "decision", title: "Storage choice", content: "Gunakan MongoDB untuk memory.",
      sources: ["main.swift"], idempotencyKey: "decision-1")
    let saved = try await store.save(input, agent: "codex")
    let second = try await store.save(input, agent: "claude")
    XCTAssertEqual(saved.id, second.id)
    XCTAssertEqual(second.disposition, "merged")
    var conflicting = input
    conflicting.content = "A different choice"
    do {
      _ = try await store.save(conflicting)
      XCTFail("expected idempotency conflict")
    } catch { XCTAssertTrue(error is MemoError) }
    let reopened = try await MemoryStore.open(
      dataDir: root.appendingPathComponent("memory").path,
      project: root.appendingPathComponent("project").path)
    let value = try await reopened.get(saved.id)
    XCTAssertEqual(value.content, input.content)
    XCTAssertEqual(value.agent, "codex")
    XCTAssertEqual(value.state, "active")
    await reopened.close()
  }
  func testIsolationAndStaleEvidence() async throws {
    let (root, store) = try await fixture()
    let saved = try await store.save(
      SaveInput(
        title: "Evidence", content: "main.swift declares the answer", sources: ["main.swift"]))
    let other = root.appendingPathComponent("other")
    try privateDirectory(other)
    let peer = try await MemoryStore.open(
      dataDir: root.appendingPathComponent("memory").path, project: other.path)
    let results = try await peer.search()
    XCTAssertTrue(results.isEmpty)
    do {
      _ = try await peer.get(saved.id)
      XCTFail("scope leak")
    } catch { XCTAssertTrue(error is MemoError) }
    await peer.close()
    try Data("changed".utf8).write(to: root.appendingPathComponent("project/main.swift"))
    let stale = try await store.get(saved.id)
    XCTAssertEqual(stale.state, "stale")
    XCTAssertTrue(stale.warnings?.contains("source_changed:main.swift") == true)
  }
  func testSecretRejectedWithoutPersisting() async throws {
    let (_, store) = try await fixture()
    let before = try await store.status().records
    // Quoted forms too: JSON encoding escapes the quotes, so fields are checked raw.
    for content in [
      "password=synthetic-do-not-store", #"password = "synthetic-do-not-store""#,
      #"{"password": "synthetic-do-not-store"}"#,
    ] {
      do {
        _ = try await store.save(SaveInput(title: "Sensitive", content: content))
        XCTFail("secret accepted: \(content)")
      } catch { XCTAssertTrue(error.localizedDescription.contains("secret_detected")) }
    }
    let after = try await store.status().records
    XCTAssertEqual(before, after)
  }
  func testBilingualSymbolSearchAndDelete() async throws {
    let (_, store) = try await fixture()
    let saved = try await store.save(
      SaveInput(
        title: "AuthService.refreshToken",
        content: "Keputusan penyimpanan sesi pengguna memakai MongoDB.", tags: ["authentication"]))
    for query in ["penyimpanan", "AuthService.refreshToken", "MongoDB"] {
      let results = try await store.search(query)
      XCTAssertTrue(results.contains { $0.id == saved.id }, query)
    }
    _ = try await store.context(task: "MongoDB", maxTokens: 1000)
    try await store.delete(saved.id)
    let remaining = try await store.search("MongoDB")
    XCTAssertTrue(remaining.isEmpty)
    let status = try await store.status()
    XCTAssertEqual(status.cacheBytes, 0)
  }
  func testMissingStorageDoesNotRecreate() async throws {
    let (root, store) = try await fixture()
    let meta = root.appendingPathComponent("memory/meta.json")
    try FileManager.default.removeItem(at: meta)
    do {
      _ = try await store.save(SaveInput(title: "No disk", content: "must not persist"))
      XCTFail("missing storage accepted")
    } catch { XCTAssertTrue(error.localizedDescription.contains("storage_unavailable")) }
    do {
      _ = try await MemoryStore.open(
        dataDir: root.appendingPathComponent("memory").path,
        project: root.appendingPathComponent("project").path)
      XCTFail("recreated store")
    } catch { XCTAssertTrue(error.localizedDescription.contains("storage_unavailable")) }
    XCTAssertFalse(FileManager.default.fileExists(atPath: meta.path))
  }
  func testConcurrentIdempotentWritesAcrossConnections() async throws {
    let (root, store) = try await fixture()
    let connections = try await withThrowingTaskGroup(of: MemoryStore.self) { group in
      for _ in 0..<4 {
        group.addTask {
          try await MemoryStore.open(
            dataDir: root.appendingPathComponent("memory").path,
            project: root.appendingPathComponent("project").path)
        }
      }
      var output: [MemoryStore] = []
      for try await connection in group { output.append(connection) }
      return output
    }
    let input = SaveInput(
      title: "Atomic decision", content: "Shared memory survives concurrent writers.",
      idempotencyKey: "same-operation")
    let ids = try await withThrowingTaskGroup(of: String.self) { group in
      for (index, connection) in connections.enumerated() {
        group.addTask { try await connection.save(input, agent: "agent-\(index)").id }
      }
      var ids: [String] = []
      for try await id in group { ids.append(id) }
      return ids
    }
    XCTAssertEqual(Set(ids).count, 1)
    let results = try await store.search("Atomic")
    XCTAssertEqual(results.count, 1)
    for connection in connections { await connection.close() }
  }
  func testHandoffAndCacheInvalidation() async throws {
    let (_, store) = try await fixture()
    let saved = try await store.checkpoint(
      CheckpointInput(
        done: ["MCP save works"], next: ["Run cross-agent test"], tests: ["fixture only"],
        changedFiles: ["main.swift"]), agent: "claude")
    let record = try await store.get(saved.id)
    XCTAssertEqual(record.kind, "checkpoint")
    XCTAssertTrue(record.content.contains("cross-agent"))
    let first = try await store.context(task: "", maxTokens: 1000)
    let repeatValue = try await store.context(task: "", maxTokens: 1000)
    XCTAssertEqual(first, repeatValue)
    _ = try await store.save(SaveInput(title: "New change", content: "Additional milestone"))
    let updated = try await store.context(task: "", maxTokens: 2000)
    let envelope = try JSONDecoder().decode(ContextEnvelope.self, from: updated)
    XCTAssertTrue(envelope.result.contains { $0.title == "New change" })
    try await store.clearCache()
    let status = try await store.status()
    XCTAssertEqual(status.records, 2)
  }
  func testNormalizedDedupAndUnmatchedTaskHandoff() async throws {
    let (_, store) = try await fixture()
    let input = SaveInput(title: "Normalize", content: "A shared decision", tags: ["b", "a"])
    let first = try await store.save(input)
    var other = input
    other.sources = nil
    other.tags = ["a", "b", "a"]
    let duplicate = try await store.save(other)
    XCTAssertEqual(first.id, duplicate.id)
    let checkpoint = try await store.checkpoint(CheckpointInput(next: ["Continue implementation"]))
    let context = try await store.context(task: "does-not-match-any-memory", maxTokens: 1500)
    let envelope = try JSONDecoder().decode(ContextEnvelope.self, from: context)
    XCTAssertTrue(envelope.result.contains { $0.id == checkpoint.id })
  }

  func testFutureSchemaRefused() async throws {
    let (root, store) = try await fixture()
    await store.close()
    let meta = root.appendingPathComponent("memory/meta.json")
    var object = try JSONSerialization.jsonObject(with: Data(contentsOf: meta)) as! [String: Any]
    object["schema_version"] = 2
    try JSONSerialization.data(withJSONObject: object).write(to: meta)
    do {
      _ = try await MemoryStore.open(
        dataDir: root.appendingPathComponent("memory").path,
        project: root.appendingPathComponent("project").path)
      XCTFail("future schema accepted")
    } catch { XCTAssertTrue(error.localizedDescription.contains("unsupported schema")) }
  }

}

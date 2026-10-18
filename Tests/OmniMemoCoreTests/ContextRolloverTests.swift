import XCTest

@testable import OmniMemoCore

final class ContextRolloverTests: XCTestCase {
  private func fixture(mongo: Bool) async throws -> MemoryStore {
    let root: URL
    let store: MemoryStore
    if mongo {
      (root, store) = try await MongoTests().fixture()
    } else {
      let (data, _, sqlite) = try await SQLiteTests().fixture()
      root = data.deletingLastPathComponent()
      store = sqlite
    }
    addTeardownBlock {
      await store.close()
      try? FileManager.default.removeItem(at: root)
    }
    try await store.ensureRuntimeIndexes()
    return store
  }

  private func start(_ store: MemoryStore, _ type: String = "session.started") async throws {
    _ = try await store.ingest(
      RuntimeEventInput(source: "claude_hook", provider: "claude", externalSessionID: "s1", eventType: type))
  }

  private func contextEvents(_ store: MemoryStore) async throws -> [RuntimeEvent] {
    try await store.events(after: 0).filter { $0.type == "context.usage.updated" }
  }

  func testLevels() {
    XCTAssertEqual(ContextUsage.level(69.9), "normal")
    XCTAssertEqual(ContextUsage.level(70), "prepare")
    XCTAssertEqual(ContextUsage.level(80), "handoff")
    XCTAssertEqual(ContextUsage.level(90), "critical")
  }

  func testSQLiteSamples() async throws { try await samples(mongo: false) }
  func testMongoSamples() async throws { try await samples(mongo: true) }

  private func samples(mongo: Bool) async throws {
    let store = try await fixture(mongo: mongo)
    // A status line alone proves no session: nothing is created or announced.
    let orphan = try await store.recordContext(
      agent: "claude", session: "s1", model: nil, usedPercent: 12, windowTokens: nil)
    XCTAssertNil(orphan)
    let none = try await store.runtimeAgents()
    XCTAssertTrue(none.isEmpty)

    try await start(store)
    let fresh = try await store.runtimeAgents().first
    XCTAssertEqual(fresh?.context, .unknown, "no sample is unknown, not 0%")
    let first = try await store.recordContext(
      agent: "claude", session: "s1", model: "claude-test", usedPercent: 42, windowTokens: 200_000)
    XCTAssertEqual(first?.level, "normal")
    XCTAssertEqual(first?.usedPercent, 42)
    // Too soon and not meaningfully different: skipped. A level change is never skipped.
    let soon = try await store.recordContext(
      agent: "claude", session: "s1", model: nil, usedPercent: 42.5, windowTokens: 200_000)
    XCTAssertNil(soon)
    let crossed = try await store.recordContext(
      agent: "claude", session: "s1", model: nil, usedPercent: 72, windowTokens: 200_000)
    XCTAssertEqual(crossed?.level, "prepare")

    // After the interval, an unchanged value is still skipped; a 1-point change is kept.
    var session = try await store.backend.session(project: store.binding.id, agent: "claude", session: "s1")!
    session.contextObservedAt = "2020-01-01T00:00:00Z"
    try await store.backend.save(session: session, project: store.binding.id)
    let same = try await store.recordContext(
      agent: "claude", session: "s1", model: nil, usedPercent: 72.4, windowTokens: 200_000)
    XCTAssertNil(same)
    let moved = try await store.recordContext(
      agent: "claude", session: "s1", model: nil, usedPercent: 74, windowTokens: 200_000)
    XCTAssertEqual(moved?.usedPercent, 74)
    let events = try await contextEvents(store)
    XCTAssertEqual(events.map { $0.data["used_percent"] }, ["42.0", "72.0", "74.0"])
    XCTAssertEqual(events[1].data["previous_level"], "normal")

    let card = try await store.runtimeAgents().first
    XCTAssertEqual(card?.context.measurement, "reported")
    XCTAssertEqual(card?.context.windowTokens, 200_000)
    XCTAssertEqual(card?.model, "claude-test")
    XCTAssertEqual(card?.progress.kind, "indeterminate", "context usage is never task progress")

    // An ended session keeps no numeric occupancy.
    try await start(store, "session.ended")
    let ended = try await store.runtimeAgents().first
    XCTAssertEqual(ended?.context, .unknown)
  }

  func testRejectsInvalidSamples() async throws {
    let store = try await fixture(mongo: false)
    try await start(store)
    for bad in [-1, 100.5, Double.nan] {
      do {
        _ = try await store.recordContext(agent: "claude", session: "s1", model: nil, usedPercent: bad, windowTokens: nil)
        XCTFail("accepted \(bad)")
      } catch MemoError.invalid {}
    }
    do {
      _ = try await store.recordContext(agent: "claude", session: "../x", model: nil, usedPercent: 5, windowTokens: nil)
      XCTFail("accepted a path as session")
    } catch MemoError.invalid {}
  }

  func testCapsuleIsBoundedAndPrepareIsIdempotent() async throws {
    let store = try await fixture(mongo: false)
    for n in 0..<12 {
      let task = try await store.createTask(
        title: "Task \(n) " + String(repeating: "long title ", count: 10), idempotencyKey: "t\(n)",
        priority: "P2", agent: "claude")
      _ = try await store.updateTask(
        id: task.id, expectedRevision: task.revision, status: "doing", owner: "claude", priority: nil,
        agent: "claude")
      _ = try await store.addMilestone(taskID: task.id, title: "Milestone for \(n)", agent: "claude")
    }
    let files = (0..<40).map { "Sources/Very/Long/Path/File\($0).swift" }
    let capsule = try await store.rolloverCapsule(
      agent: "claude", session: nil, gitBranch: "main", gitCommit: "abc1234", changedFiles: files)
    XCTAssertEqual(capsule.goal.count, 5)
    XCTAssertEqual(capsule.next.count, 8)
    XCTAssertEqual(capsule.changedFiles.count, 20)
    XCTAssertLessThan(capsule.text.utf8.count, 2500)
    XCTAssertTrue(capsule.text.contains("no commit or push"))

    let first = try await store.prepareRollover(capsule, agent: "claude", digest: "d1")
    let again = try await store.prepareRollover(capsule, agent: "claude", digest: "d1")
    XCTAssertEqual(first.id, again.id)
    let prepared = try await store.events(after: 0).filter { $0.type == "rollover.prepared" }
    XCTAssertEqual(prepared.count, 1)
  }

  func testCodexMapping() {
    XCTAssertEqual(RuntimeMapping.codexItemCategory("commandExecution"), "shell")
    XCTAssertEqual(RuntimeMapping.codexItemCategory("fileChange"), "file_edit")
    XCTAssertEqual(RuntimeMapping.codexItemCategory("mcpToolCall"), "mcp")
    XCTAssertNil(RuntimeMapping.codexItemCategory("agentMessage"), "messages are not tool calls")
    XCTAssertEqual(RuntimeMapping.codexContextPercent(lastInputTokens: 50_000, window: 200_000), 25)
    XCTAssertEqual(RuntimeMapping.codexContextPercent(lastInputTokens: 300_000, window: 200_000), 100)
    XCTAssertNil(RuntimeMapping.codexContextPercent(lastInputTokens: 50_000, window: nil), "no window, no percent")
  }

  func testSQLiteRolloverLineage() async throws { try await lineage(mongo: false) }
  func testMongoRolloverLineage() async throws { try await lineage(mongo: true) }

  private func session(_ store: MemoryStore, _ id: String, task: String? = nil) async throws {
    _ = try await store.ingest(
      RuntimeEventInput(source: "codex_app_server", provider: "codex", externalSessionID: id, eventType: "session.started"))
    if let task {
      _ = try await store.ingest(
        RuntimeEventInput(
          source: "codex_app_server", provider: "codex", externalSessionID: id, eventType: "task.assigned", taskID: task))
    }
  }

  private func stored(_ store: MemoryStore, _ id: String) async throws -> AgentSession {
    try await store.backend.session(project: store.binding.id, agent: "codex", session: id)!
  }

  private func lineage(mongo: Bool) async throws {
    let store = try await fixture(mongo: mongo)
    try await session(store, "p1", task: "task_a")
    // Two concurrent requests for the same parent: exactly one child is reserved.
    async let first = store.beginRollover(agent: "codex", parent: "p1")
    async let second = store.beginRollover(agent: "codex", parent: "p1")
    let claims = try await [first, second]
    XCTAssertEqual(claims.filter { $0 }.count, 1)

    // No acknowledgement: the parent keeps its task and the failure is recorded.
    try await session(store, "c1")
    try await store.linkRolloverChild(agent: "codex", parent: "p1", child: "c1")
    var parent = try await stored(store, "p1")
    XCTAssertEqual(parent.rolloverState, "waiting_ack")
    XCTAssertEqual(parent.childSessionID, "c1")
    try await store.finishRollover(agent: "codex", parent: "p1", child: "c1", acknowledged: false, reason: "no ack")
    parent = try await stored(store, "p1")
    XCTAssertEqual(parent.rolloverState, "failed_recoverable")
    XCTAssertEqual(parent.taskID, "task_a")
    let orphan = try await stored(store, "c1")
    XCTAssertNil(orphan.taskID)
    let retry = try await store.beginRollover(agent: "codex", parent: "p1")
    XCTAssertFalse(retry, "one child per parent, even after a failure")

    // Acknowledged: ownership moves to the child, the parent is retired.
    try await session(store, "p2", task: "task_b")
    let claimed = try await store.beginRollover(agent: "codex", parent: "p2")
    XCTAssertTrue(claimed)
    try await session(store, "c2")
    try await store.linkRolloverChild(agent: "codex", parent: "p2", child: "c2")
    try await store.finishRollover(agent: "codex", parent: "p2", child: "c2", acknowledged: true, reason: "acknowledged")
    let retired = try await stored(store, "p2")
    let child = try await stored(store, "c2")
    XCTAssertEqual(retired.rolloverState, "completed")
    XCTAssertNil(retired.taskID)
    XCTAssertEqual(child.taskID, "task_b")
    XCTAssertEqual(child.parentSessionID, "p2")
    let types = try await store.events(after: 0).map(\.type).filter { $0.hasPrefix("rollover.") }
    XCTAssertEqual(types, ["rollover.created", "rollover.failed", "rollover.created", "rollover.completed"])
  }
}

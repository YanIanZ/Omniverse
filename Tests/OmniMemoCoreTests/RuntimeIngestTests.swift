import XCTest

@testable import OmniMemoCore

final class RuntimeIngestTests: XCTestCase {
  private func fixture(mongo: Bool) async throws -> MemoryStore {
    let store = mongo
      ? try await MongoTests().fixture(owner: self).1
      : try await SQLiteTests().fixture(owner: self).2
    try await store.ensureRuntimeIndexes()
    return store
  }

  private func event(_ type: String = "prompt.received") -> RuntimeEventInput {
    RuntimeEventInput(source: "test_adapter", provider: "codex", externalSessionID: "session1", eventType: type)
  }

  func testSQLiteAcceptAndDeduplicate() async throws { try await acceptAndDeduplicate(mongo: false) }
  func testMongoAcceptAndDeduplicate() async throws { try await acceptAndDeduplicate(mongo: true) }

  private func acceptAndDeduplicate(mongo: Bool) async throws {
    let store = try await fixture(mongo: mongo)
    var input = event("tool.started")
    input.modelID = "test-model"
    input.metadata = ["tool_category": .string("file_read")]
    let result = try await store.ingest(input)
    XCTAssertTrue(result.accepted)
    XCTAssertFalse(result.duplicate)
    XCTAssertEqual(result.status, "working")
    XCTAssertNotNil(result.cursor)
    let before = try await store.runtimeAgents()
    let revision = try await store.latestRevision()
    input.eventID = input.eventID.uppercased()
    let duplicate = try await store.ingest(input)
    XCTAssertFalse(duplicate.accepted)
    XCTAssertTrue(duplicate.duplicate)
    XCTAssertNil(duplicate.cursor)
    let after = try await store.runtimeAgents()
    let afterRevision = try await store.latestRevision()
    XCTAssertEqual(afterRevision, revision)
    XCTAssertEqual(after.first?.runtimeID, before.first?.runtimeID)
    XCTAssertEqual(after.first?.lastSeen, before.first?.lastSeen)
    XCTAssertEqual(after.first?.eventCount, 1)
    XCTAssertEqual(after.first?.toolCategory, "file_read")
    XCTAssertEqual(after.first?.model, "test-model")
    // Dedup scope includes both provider and external session, not just event UUID.
    input.externalSessionID = "session2"
    let otherSession = try await store.ingest(input)
    XCTAssertTrue(otherSession.accepted)
    input.provider = "claude"
    let otherProvider = try await store.ingest(input)
    XCTAssertTrue(otherProvider.accepted)
    let cards = try await store.runtimeAgents()
    XCTAssertEqual(cards.count, 3)
    XCTAssertEqual(Set(cards.compactMap(\.runtimeID)).count, 3)
  }

  func testSQLiteOlderEventsPreserveState() async throws { try await olderEvents(mongo: false) }
  func testMongoOlderEventsPreserveState() async throws { try await olderEvents(mongo: true) }

  private func olderEvents(mongo: Bool) async throws {
    let store = try await fixture(mongo: mongo)
    let format = ISO8601DateFormatter()
    let timestamp = Date().addingTimeInterval(-30)
    var latest = event("turn.completed")
    latest.sequence = 10
    latest.occurredAt = format.string(from: timestamp)
    latest.modelID = "current-model"
    _ = try await store.ingest(latest)
    var reordered = event("tool.started")
    reordered.sequence = 9
    reordered.occurredAt = format.string(from: timestamp.addingTimeInterval(10))
    reordered.modelID = "old-model"
    reordered.metadata = ["tool_category": .string("shell")]
    _ = try await store.ingest(reordered)
    var older = reordered
    older.eventID = UUID().uuidString
    older.sequence = 11
    older.occurredAt = format.string(from: timestamp.addingTimeInterval(-10))
    _ = try await store.ingest(older)
    let sessions = try await store.agents()
    let session = try XCTUnwrap(sessions.first)
    XCTAssertEqual(session.status, "waiting")
    XCTAssertEqual(session.lastEvent, "turn.completed")
    XCTAssertEqual(session.lastSequence, 10)
    XCTAssertEqual(session.model, "current-model")
    XCTAssertNil(session.toolCategory)
    XCTAssertEqual(session.eventCount, 3, "older events are still recorded")
    let events = try await store.events(after: 0)
    XCTAssertEqual(events.count, 3)
    var next = event("approval.requested")
    next.sequence = 12
    _ = try await store.ingest(next)
    let cards = try await store.runtimeAgents()
    XCTAssertEqual(cards.first?.status, "blocked")
  }

  func testSQLiteStaleIsDerivedByObservability() async throws { try await stale(mongo: false) }
  func testMongoStaleIsDerivedByObservability() async throws { try await stale(mongo: true) }

  private func stale(mongo: Bool) async throws {
    let store = try await fixture(mongo: mongo)
    let format = ISO8601DateFormatter()
    for (id, mode, age, status) in [
      ("managed-old", "managed", 60.0, "working"),
      ("managed-fresh", "managed", 10.0, "working"),
      ("passive-fresh", "passive", 60.0, "waiting"),
      ("passive-old", "passive", 660.0, "blocked"),
      ("ended", "managed", 660.0, "offline"),
    ] {
      var session = AgentSession(
        agent: "codex", sessionID: id, status: status, source: "test_adapter",
        firstSeen: format.string(from: Date().addingTimeInterval(-1000)),
        lastSeen: format.string(from: Date().addingTimeInterval(-age)))
      session.observability = mode
      let saved = try await store.backend.save(session: session, project: store.binding.id)
      XCTAssertTrue(saved)
    }
    let cards = try await store.runtimeAgents()
    let states = Dictionary(uniqueKeysWithValues: cards.map { ($0.sessionID, $0.status) })
    XCTAssertEqual(states, ["managed-old": "stale", "managed-fresh": "working",
      "passive-fresh": "waiting", "passive-old": "stale", "ended": "offline"])
    let durable = try await store.backend.session(project: store.binding.id, agent: "codex", session: "managed-old")
    XCTAssertEqual(durable?.status, "working", "stale is derived without rewriting durable status")
  }

  func testSQLiteMilestoneProgress() async throws { try await milestones(mongo: false) }
  func testMongoMilestoneProgress() async throws { try await milestones(mongo: true) }

  private func milestones(mongo: Bool) async throws {
    let store = try await fixture(mongo: mongo)
    let task = try await store.createTask(title: "Verify runtime contract")
    XCTAssertEqual(OmniMemoCore.Progress.of(task.milestones).kind, "indeterminate")
    XCTAssertNil(OmniMemoCore.Progress.of(task.milestones).percent)
    _ = try await store.addMilestone(taskID: task.id, title: "Build", weight: 1, agent: "codex")
    let planned = try await store.addMilestone(taskID: task.id, title: "Test", weight: 2, agent: "codex")
    let plan = try XCTUnwrap(planned.milestones)
    XCTAssertEqual(OmniMemoCore.Progress.of(plan).percent, 0)
    let verified = try await store.setMilestone(taskID: task.id, milestoneID: plan[0].id,
      verified: true, evidence: "Observed build exit 0", agent: "codex")
    XCTAssertEqual(OmniMemoCore.Progress.of(verified.milestones).percent, 33)
    XCTAssertNotNil(verified.milestones?.first?.verifiedAt)
    // Before the task is assigned to this session, its milestones are not this session's to verify.
    var early = event("milestone.verified")
    early.taskID = task.id
    early.milestoneID = plan[1].id
    _ = try await store.ingest(early)
    let untouched = try await store.listTasks().first { $0.id == task.id }
    XCTAssertEqual(OmniMemoCore.Progress.of(untouched?.milestones).percent, 33)
    var assigned = event("task.assigned")
    assigned.taskID = task.id
    _ = try await store.ingest(assigned)
    var proof = event("milestone.verified")
    proof.taskID = task.id
    proof.milestoneID = plan[1].id
    _ = try await store.ingest(proof)
    let cards = try await store.runtimeAgents()
    let progress = try XCTUnwrap(cards.first?.progress)
    XCTAssertEqual(progress.kind, "determinate")
    XCTAssertEqual(progress.percent, 100)
    XCTAssertEqual(progress.completed, 2)
    XCTAssertEqual(progress.total, 2)
    XCTAssertEqual(cards.first?.task?.id, task.id)
    let reverted = try await store.setMilestone(taskID: task.id, milestoneID: plan[0].id,
      verified: false, evidence: "Build evidence invalidated", agent: "codex")
    XCTAssertEqual(OmniMemoCore.Progress.of(reverted.milestones).percent, 66)
    XCTAssertNil(reverted.milestones?.first?.verifiedAt)
  }

  func testSQLiteRejectedMetadataAndSecrets() async throws { try await rejected(mongo: false) }
  func testMongoRejectedMetadataAndSecrets() async throws { try await rejected(mongo: true) }

  private func rejected(mongo: Bool) async throws {
    let store = try await fixture(mongo: mongo)
    var input = event()
    input.metadata = ["tool_arguments": .string("must never be stored")]
    do {
      _ = try await store.ingest(input)
      XCTFail("unapproved metadata key accepted")
    } catch MemoError.invalid(let reason) {
      XCTAssertTrue(reason.contains("metadata key"))
    }
    input.metadata = ["reason": .string("password=synthetic-do-not-store")]
    do {
      _ = try await store.ingest(input)
      XCTFail("secret accepted")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("secret_detected"))
    }
    input.metadata = nil
    input.modelID = "password=synthetic-do-not-store"
    do {
      _ = try await store.ingest(input)
      XCTFail("secret in model label accepted")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("secret_detected"))
    }
    let sessions = try await store.runtimeAgents()
    let events = try await store.events(after: 0)
    XCTAssertTrue(sessions.isEmpty)
    XCTAssertTrue(events.isEmpty)
    // Validation rejection must not consume the dedup key.
    input.modelID = nil
    input.metadata = ["tool_category": .string("file_read")]
    let valid = try await store.ingest(input)
    XCTAssertTrue(valid.accepted)
    XCTAssertFalse(valid.duplicate)
    // An adapter clock far ahead would freeze the card: rejected.
    var ahead = event()
    ahead.occurredAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
    do {
      _ = try await store.ingest(ahead)
      XCTFail("future occurred_at accepted")
    } catch MemoError.invalid {}
  }

  func testSQLiteSessionSavesCompareRevision() async throws { try await sessionRevision(mongo: false) }
  func testMongoSessionSavesCompareRevision() async throws { try await sessionRevision(mongo: true) }

  /// Two writers that read the same session: the second save loses instead of overwriting.
  private func sessionRevision(mongo: Bool) async throws {
    let store = try await fixture(mongo: mongo)
    _ = try await store.ingest(event("session.started"))
    let read = { try await store.backend.session(project: store.binding.id, agent: "codex", session: "session1")! }
    var first = try await read()
    var second = try await read()
    first.status = "blocked"
    second.status = "working"
    let won = try await store.backend.save(session: first, project: store.binding.id)
    let lost = try await store.backend.save(session: second, project: store.binding.id)
    XCTAssertTrue(won)
    XCTAssertFalse(lost, "a stale copy overwrote a newer save")
    // A lifecycle wake counts as a write too.
    var stale = try await read()
    _ = try await store.wake(agent: "codex", session: "session1", status: "waiting", source: "test_adapter")
    stale.status = "working"
    let afterWake = try await store.backend.save(session: stale, project: store.binding.id)
    XCTAssertFalse(afterWake)
    // Through ingest, concurrent events all land.
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<8 { group.addTask { _ = try await store.ingest(self.event("tool.started")) } }
      try await group.waitForAll()
    }
    let counted = try await read().eventCount
    XCTAssertEqual(counted, 9)
  }
  /// One CLI = hook session + its MCP server's presence session: shown once.
  func testMCPPresenceHiddenBehindHookSession() {
    func s(_ agent: String, _ id: String, _ source: String, _ first: String, _ last: String) -> AgentSession {
      AgentSession(agent: agent, sessionID: id, status: "waiting", source: source,
        firstSeen: "2026-10-20T" + first + "Z", lastSeen: "2026-10-20T" + last + "Z")
    }
    let kept = MemoryStore.withoutMCPShadows([
      s("claude", "hook", "claude_hook", "10:00:00", "11:00:00"),
      s("claude", "mcp-a", "mcp", "10:00:01", "11:00:00"),  // same CLI
      s("claude", "mcp-b", "mcp", "13:00:00", "13:05:00"),  // later, no hook session
      s("opencode", "mcp-c", "mcp", "10:30:00", "10:40:00"),  // other client (IDE)
    ]).map(\.sessionID)
    XCTAssertEqual(kept, ["hook", "mcp-b", "mcp-c"])
  }
}

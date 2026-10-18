import MongoKitten
import XCTest

@testable import OmniMemoCore

final class RuntimeTests: XCTestCase {
  func store() async throws -> MongoStore {
    let (_, store) = try await MongoTests().fixture()
    try await store.ensureRuntimeIndexes()
    return store
  }

  func testWakeIsIdempotentAndEmitsOnlyOnChange() async throws {
    let store = try await store()
    _ = try await store.wake(agent: "claude", session: "s1", source: "claude_hook")
    _ = try await store.wake(agent: "claude", session: "s1", source: "claude_hook")
    var events = try await store.events(after: 0)
    XCTAssertEqual(events.map(\.type), ["agent.status.changed"])
    _ = try await store.wake(
      agent: "claude", session: "s1", status: "disconnected", source: "claude_hook")
    events = try await store.events(after: 0)
    XCTAssertEqual(events.map(\.revision), [1, 2])
    XCTAssertEqual(events.last?.data["status"], "disconnected")
    let agents = try await store.agents()
    XCTAssertEqual(agents.count, 1)
    XCTAssertEqual(agents.first?.status, "disconnected")
    XCTAssertThrowsError(try MongoStore.label("bad id; rm", "session"))
  }

  func testStalePresenceIsUnknown() async throws {
    let store = try await store()
    _ = try await store.wake(agent: "codex", session: "s2", source: "cli")
    _ = try await store.db["omnimem_sessions"].updateMany(
      where: ["project_id": store.binding.id], to: ["$set": ["last_seen": "2020-01-01T00:00:00Z"]])
    let agents = try await store.agents()
    XCTAssertEqual(agents.first?.status, "unknown")
  }

  func testPromptContextOnlyWhenChanged() async throws {
    let store = try await store()
    let empty = try await store.promptContext(agent: "claude", session: "p1")
    XCTAssertNil(empty, "an empty project must not add prompt tokens")
    _ = try await store.save(SaveInput(title: "Stack", content: "Swift, Vapor and React"))
    let first = try await store.promptContext(agent: "claude", session: "p1", maxTokens: 600)
    XCTAssertNotNil(first)
    XCTAssertLessThanOrEqual(try ContextBudget.bound(first!), 600)
    let repeated = try await store.promptContext(agent: "claude", session: "p1", maxTokens: 600)
    XCTAssertNil(repeated, "unchanged capsule must not repeat")
    let otherSession = try await store.promptContext(agent: "claude", session: "p2")
    XCTAssertNotNil(otherSession)
    _ = try await store.save(SaveInput(title: "New decision", content: "Redis is optional"))
    let changed = try await store.promptContext(agent: "claude", session: "p1", maxTokens: 600)
    XCTAssertNotNil(changed)
  }

  func testTaskCreateIdempotentAndRacingUpdates() async throws {
    let store = try await store()
    let task = try await store.createTask(title: "Review hook", idempotencyKey: "k1")
    let again = try await store.createTask(title: "Review hook", idempotencyKey: "k1")
    XCTAssertEqual(task, again)
    do {
      _ = try await store.createTask(title: "Different", idempotencyKey: "k1")
      XCTFail("expected idempotency conflict")
    } catch MemoError.conflict {}
    // Two agents race with the same revision: exactly one wins.
    let results = await withTaskGroup(of: Result<TaskRecord, Error>.self) { group in
      for owner in ["codex", "claude"] {
        group.addTask {
          do {
            return .success(
              try await store.updateTask(
                id: task.id, expectedRevision: 1, status: "doing", owner: owner))
          } catch { return .failure(error) }
        }
      }
      return await group.reduce(into: []) { $0.append($1) }
    }
    let wins = results.compactMap { try? $0.get() }
    XCTAssertEqual(wins.count, 1)
    XCTAssertEqual(wins.first?.revision, 2)
    let loss = results.compactMap { if case .failure(let e) = $0 { return e } else { return nil } }
    XCTAssertTrue(loss.first.map { "\($0)" == "\(MemoError.revisionConflict)" } ?? false)
    do {
      _ = try await store.updateTask(id: "task_missing", expectedRevision: 1, status: "done", owner: nil)
      XCTFail("expected not found")
    } catch MemoError.notFound {}
    do {
      _ = try await store.updateTask(id: task.id, expectedRevision: 2, status: "shipped", owner: nil)
      XCTFail("expected invalid status")
    } catch MemoError.invalid {}
    let events = try await store.events(after: 0)
    XCTAssertEqual(events.filter { $0.type == "task.updated" }.count, 2)
  }

  func testRedisUnavailableDoesNotBlockDurableWrites() async throws {
    setenv("OMNIMEM_REDIS_URL", "redis://127.0.0.1:1", 1)
    defer { unsetenv("OMNIMEM_REDIS_URL") }
    let store = try await store()
    let task = try await store.createTask(title: "Survives Redis outage")
    let tasks = try await store.listTasks()
    XCTAssertEqual(tasks.map(\.id), [task.id])
  }
}

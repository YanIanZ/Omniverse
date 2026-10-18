import MongoKitten
import XCTest

@testable import OmniMemoCore

final class RuntimeTests: XCTestCase {
  func store() async throws -> MemoryStore {
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
    XCTAssertEqual(events.last?.data["status"], "offline")
    let agents = try await store.agents()
    XCTAssertEqual(agents.count, 1)
    XCTAssertEqual(agents.first?.status, "offline")
    XCTAssertThrowsError(try MemoryStore.label("bad id; rm", "session"))
  }

  func testStalePresenceIsDerived() async throws {
    let store = try await store()
    _ = try await store.wake(agent: "codex", session: "s2", source: "cli")
    _ = try await store.mongoDatabase!["omnimem_sessions"].updateMany(
      where: ["project_id": store.binding.id], to: ["$set": ["last_seen": "2020-01-01T00:00:00Z"]])
    let agents = try await store.agents()
    XCTAssertEqual(agents.first?.status, "stale")
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

  func testConcurrentIdempotentCreateOnFreshStoreMakesOneTask() async throws {
    // No server ever ran here, so the unique index must be created by the first writer.
    let (_, store) = try await MongoTests().fixture()
    try? await store.mongoDatabase!["omnimem_tasks"].dropIndex(.name("project_task"))
    let made = await withTaskGroup(of: String?.self) { group in
      for _ in 0..<4 {
        group.addTask { try? await store.createTask(title: "idempotency probe", idempotencyKey: "p1").id }
      }
      return await group.reduce(into: [String]()) { if let id = $1 { $0.append(id) } }
    }
    XCTAssertEqual(Set(made).count, 1)
    let tasks = try await store.listTasks()
    XCTAssertEqual(tasks.count, 1)
  }

  func testDuplicateTaskCopiesMergeToHighestRevision() async throws {
    let (_, store) = try await MongoTests().fixture()
    // Reproduce a store written before the unique index existed.
    try? await store.mongoDatabase!["omnimem_tasks"].dropIndex(.name("project_task"))
    for revision in [1, 2] {
      var doc = try BSONEncoder().encode(
        TaskRecord(
          id: "task_dup", title: "probe", status: revision == 2 ? "done" : "todo",
          revision: revision, owner: nil, priority: "P2", createdAt: nowISO(), updatedAt: nowISO()))
      doc["project_id"] = store.binding.id
      _ = try await store.mongoDatabase!["omnimem_tasks"].insert(doc)
    }
    try await store.ensureRuntimeIndexes()
    let tasks = try await store.listTasks()
    XCTAssertEqual(tasks.map(\.revision), [2])
    XCTAssertEqual(tasks.first?.status, "done")
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

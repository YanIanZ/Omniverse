import XCTest

@testable import OmniMemoCore

/// The `sqlite` profile needs no server, so these always run.
final class SQLiteTests: XCTestCase {
  func fixture() async throws -> (URL, URL, MemoryStore) {
    let base = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["OMNIMEM_TEST_ROOT"] ?? NSTemporaryDirectory())
    let root = base.appendingPathComponent(UUID().uuidString)
    let project = root.appendingPathComponent("project")
    try privateDirectory(project)
    let git = Process()
    git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    git.arguments = ["init", "-q", project.path]
    try git.run()
    git.waitUntilExit()
    try Data("let answer = 42\n".utf8).write(to: project.appendingPathComponent("main.swift"))
    let data = root.appendingPathComponent("memory")
    let store = try await MemoryStore.initialize(dataDir: data.path, project: project.path, backend: "sqlite")
    addTeardownBlock {
      await store.close()
      try? FileManager.default.removeItem(at: root)
    }
    return (data, project, store)
  }

  func testSaveDedupSearchDeleteAndReopen() async throws {
    let (data, project, store) = try await fixture()
    XCTAssertEqual(store.profile, "sqlite")
    let input = SaveInput(
      kind: "decision", title: "Storage choice", content: "Embedded SQLite with FTS5 search",
      sources: ["main.swift"], idempotencyKey: "storage-1")
    let first = try await store.save(input, agent: "codex")
    let again = try await store.save(input, agent: "claude")
    XCTAssertEqual(first.id, again.id)
    XCTAssertEqual(again.disposition, "merged")
    var changed = input
    changed.content = "Something else"
    do {
      _ = try await store.save(changed)
      XCTFail("expected idempotency conflict")
    } catch MemoError.conflict {}
    _ = try await store.save(SaveInput(title: "Kantor", content: "Ruang rapat untuk handoff"))
    let fts = try await store.search("fts5 embedded")
    XCTAssertEqual(fts.first?.id, first.id)
    let substring = try await store.search("apat untu")
    XCTAssertEqual(substring.map(\.title), ["Kantor"])
    let value1 = try await store.status()
    XCTAssertEqual(value1.records, 2)

    let reopened = try await MemoryStore.open(dataDir: data.path, project: project.path)
    let value2 = try await reopened.get(first.id)
    XCTAssertEqual(value2.title, "Storage choice")
    try await reopened.delete(first.id)
    let afterDelete = try await reopened.search("storage")
    XCTAssertTrue(afterDelete.isEmpty)
    await reopened.close()
  }

  func testMissingDatabaseIsNeverRecreated() async throws {
    let (data, project, store) = try await fixture()
    await store.close()
    let file = data.appendingPathComponent("db/memory.sqlite")
    try FileManager.default.removeItem(at: file)
    do {
      _ = try await MemoryStore.open(dataDir: data.path, project: project.path)
      XCTFail("expected storage_unavailable")
    } catch MemoError.storageUnavailable {}
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
  }

  func testTwoConnectionsRaceOnTasksAndApprovals() async throws {
    let (data, project, first) = try await fixture()
    let second = try await MemoryStore.open(dataDir: data.path, project: project.path)
    addTeardownBlock { await second.close() }
    // Same idempotency key from two connections: one task.
    async let a = first.createTask(title: "Probe", idempotencyKey: "same")
    async let b = second.createTask(title: "Probe", idempotencyKey: "same")
    let (taskA, taskB) = try await (a, b)
    XCTAssertEqual(taskA.id, taskB.id)
    let value3 = try await first.listTasks()
    XCTAssertEqual(value3.count, 1)
    // Racing CAS updates: exactly one wins.
    let results = await withTaskGroup(of: Bool.self) { group in
      for store in [first, second] {
        group.addTask {
          (try? await store.updateTask(
            id: taskA.id, expectedRevision: 1, status: "doing", owner: "codex")) != nil
        }
      }
      return await group.reduce(into: [Bool]()) { $0.append($1) }
    }
    XCTAssertEqual(results.filter { $0 }.count, 1)
    let request = try await first.requestApproval(action: "Push main", reason: "", agent: "codex")
    _ = try await second.decideApproval(id: request.id, decision: "approved")
    do {
      _ = try await first.decideApproval(id: request.id, decision: "denied")
      XCTFail("expected a single decision")
    } catch MemoError.revisionConflict {}
    let events = try await first.events(after: 0)
    XCTAssertEqual(events.map(\.revision), Array(1...events.count), "revisions stay contiguous")
  }

  func testSessionsAndPromptCapsuleOncePerChange() async throws {
    let (_, _, store) = try await fixture()
    let value4 = try await store.promptContext(agent: "claude", session: "s1")
    XCTAssertNil(value4)
    _ = try await store.save(SaveInput(title: "Stack", content: "Swift and SQLite"))
    let value5 = try await store.promptContext(agent: "claude", session: "s1")
    XCTAssertNotNil(value5)
    let value6 = try await store.promptContext(agent: "claude", session: "s1")
    XCTAssertNil(value6)
    _ = try await store.wake(agent: "claude", session: "s1", status: "disconnected", source: "cli")
    let value7 = try await store.agents()
    XCTAssertEqual(value7.first?.status, "disconnected")
  }

  func testAutoSaveIsOptInAndNeverStoresSecretsOrInflatesCapsules() async throws {
    let (data, project, store) = try await fixture()
    // Off by default.
    let offPrompt = await store.autoPromptSummary(agent: "claude", session: "s", prompt: "hello")
    let offCheckpoint = await store.autoCheckpoint(agent: "claude", session: "s", reason: "end")
    XCTAssertNil(offPrompt)
    XCTAssertNil(offCheckpoint)
    try AutoSave(checkpoints: true, transitions: true, prompts: true).write(data)

    let prompt = await store.autoPromptSummary(
      agent: "claude", session: "s", prompt: "  Refactor   the storage\nlayer please ")
    XCTAssertNotNil(prompt)
    let secret = await store.autoPromptSummary(
      agent: "claude", session: "s", prompt: "api_key = abcdef123456")
    XCTAssertNil(secret, "prompts with secrets are skipped")
    let capsule = try await store.context(task: "storage", maxTokens: 2000)
    XCTAssertFalse(String(decoding: capsule, as: UTF8.self).contains("Refactor"), "prompts stay out of capsules")

    let task = try await store.createTask(title: "Wire autosave")
    _ = try await store.updateTask(id: task.id, expectedRevision: 1, status: "doing", owner: "claude")
    try Data("let changed = true\n".utf8).write(to: project.appendingPathComponent("new.swift"))
    let checkpoint = await store.autoCheckpoint(agent: "claude", session: "s", reason: "SessionEnd")
    XCTAssertEqual(checkpoint?.disposition, "created")
    let saved = try await store.get(checkpoint!.id)
    XCTAssertTrue(saved.content.contains("new.swift"))
    XCTAssertTrue(saved.content.contains("Continue: Wire autosave"))
    let repeated = await store.autoCheckpoint(agent: "claude", session: "s", reason: "SessionEnd")
    XCTAssertEqual(repeated?.disposition, "merged", "unchanged state does not add a second checkpoint")
    _ = try await store.updateTask(id: task.id, expectedRevision: 2, status: "done", owner: nil)
    let titles = try await store.search("", limit: 20).map(\.title)
    XCTAssertTrue(titles.contains("Task done: Wire autosave"))
    XCTAssertFalse(titles.contains("Task doing: Wire autosave"), "only review/done/blocked are remembered")
  }

  func testChangedFilesParsesPorcelain() async throws {
    let (_, project, store) = try await fixture()
    try Data("a\n".utf8).write(to: project.appendingPathComponent("space name.txt"))
    let files = store.binding.changedFiles()
    XCTAssertTrue(files.contains("main.swift"))
    XCTAssertTrue(files.contains("space name.txt"))
  }
}

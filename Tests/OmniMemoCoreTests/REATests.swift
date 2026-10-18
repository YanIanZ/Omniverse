import XCTest

@testable import OmniMemoCore

final class REATests: XCTestCase {
  private func workspace() throws -> URL {
    let base = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["OMNIMEM_TEST_ROOT"]
        ?? NSTemporaryDirectory())
    let root = base.appendingPathComponent(UUID().uuidString)
    try privateDirectory(root)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return root
  }
  func testMissingRuntimeDoesNotFetchOrCreateStorage() throws {
    let root = try workspace()
    let absent = root.appendingPathComponent("missing/runtime.json")
    XCTAssertThrowsError(try REARuntime(manifestPath: absent.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: absent.deletingLastPathComponent().path))
  }
  func testForeignRuntimeRejectedBeforeExecution() throws {
    let root = try workspace()
    var identity = try REARuntime.bundledIdentity()
    identity.commit = "foreign"
    let descriptor = REARuntimeDescriptor(
      schemaVersion: 1, identity: identity, packageRoot: root.path, nodePath: "/bin/echo",
      tempDirectory: root.path)
    let file = root.appendingPathComponent("runtime.json")
    try encodeJSON(descriptor).write(to: file)
    XCTAssertThrowsError(try REARuntime(manifestPath: file.path))
  }
  func testChangedRuntimeArtifactRejected() throws {
    let root = try workspace()
    let identity = try REARuntime.bundledIdentity()
    try privateDirectory(root.appendingPathComponent("scripts"))
    try Data("modified runtime".utf8).write(to: root.appendingPathComponent("scripts/rea.mjs"))
    let file = root.appendingPathComponent("runtime.json")
    let descriptor = REARuntimeDescriptor(
      schemaVersion: 1, identity: identity, packageRoot: root.path, nodePath: "/bin/echo",
      tempDirectory: root.path)
    try encodeJSON(descriptor).write(to: file)
    XCTAssertThrowsError(try REARuntime(manifestPath: file.path))
  }
  func testPreviewNeedsNoRuntimeAndChangesNoFiles() throws {
    let root = try workspace()
    let installer = try AgentInstaller(
      configRoot: root.path, project: root.path, executable: "/tmp/omnimem", dataDir: root.path,
      agents: ["codex", "claude"], withRea: true,
      reaManifestPath: root.appendingPathComponent("missing.json").path)
    let plan = installer.preview()
    XCTAssertEqual(plan.profile, "memory+rea")
    XCTAssertTrue(
      plan.files.contains(
        ".agents/skills/reverse-engineer-anything/references/javascript-applications.md"))
    XCTAssertTrue(plan.files.contains(".claude/skills/reverse-engineer-anything/SKILL.md"))
    XCTAssertNotNil(plan.additionalServers?[installer.reaServerID])
    XCTAssertThrowsError(try installer.apply())
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: root.appendingPathComponent(".mcp.json").path))
  }
  func testFullSkillAndTwoServersRoundTrip() throws {
    guard let manifest = ProcessInfo.processInfo.environment["OMNIMEM_TEST_REA_MANIFEST"] else {
      throw XCTSkip("Prepare REA and set OMNIMEM_TEST_REA_MANIFEST")
    }
    let root = try workspace()
    let original = Data("{\"mcpServers\":{\"other\":{\"command\":\"other\"}}}".utf8)
    let config = root.appendingPathComponent(".mcp.json")
    try original.write(to: config)
    let installer = try AgentInstaller(
      configRoot: root.path, project: root.path, executable: "/tmp/omnimem", dataDir: root.path,
      agents: ["codex", "claude"], withRea: true, reaManifestPath: manifest)
    try installer.apply()
    try installer.apply()
    let document =
      try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as! [String: Any]
    let servers = document["mcpServers"] as! [String: Any]
    XCTAssertNotNil(servers[installer.serverID])
    XCTAssertNotNil(servers[installer.reaServerID])
    XCTAssertNotNil(servers["other"])
    let reference = root.appendingPathComponent(
      ".agents/skills/reverse-engineer-anything/references/javascript-applications.md")
    XCTAssertTrue(FileManager.default.fileExists(atPath: reference.path))
    let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
        "Sources/OmniMemoCore/Skills/reverse-engineer-anything")
    let enumerator = FileManager.default.enumerator(
      at: sourceRoot, includingPropertiesForKeys: [.isRegularFileKey])!
    for case let file as URL in enumerator
    where (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
      let relative = String(file.path.dropFirst(sourceRoot.path.count + 1))
      XCTAssertEqual(
        try Data(contentsOf: file),
        try Data(
          contentsOf: root.appendingPathComponent(
            ".agents/skills/reverse-engineer-anything/" + relative)))
    }
    // A normal uninstaller reads ownership from the manifest, without requiring REA flags/runtime.
    let uninstaller = try AgentInstaller(
      configRoot: root.path, project: root.path, executable: "/tmp/omnimem", dataDir: root.path,
      agents: ["codex", "claude"])
    XCTAssertEqual(try uninstaller.uninstall().profile, "memory+rea")
    _ = try uninstaller.uninstall(apply: true)
    _ = try uninstaller.uninstall(apply: true)
    XCTAssertEqual(original, try Data(contentsOf: config))
    XCTAssertFalse(FileManager.default.fileExists(atPath: reference.path))
  }
  func testProfileChangeRequiresReviewWithoutMutation() throws {
    let root = try workspace()
    let base = try AgentInstaller(
      configRoot: root.path, project: root.path, executable: "/tmp/omnimem", dataDir: root.path,
      agents: ["codex"])
    try base.apply()
    let file = root.appendingPathComponent(".codex/config.toml")
    let before = try Data(contentsOf: file)
    let changed = try AgentInstaller(
      configRoot: root.path, project: root.path, executable: "/tmp/omnimem", dataDir: root.path,
      agents: ["codex"], withRea: true)
    XCTAssertThrowsError(try changed.apply())
    XCTAssertEqual(before, try Data(contentsOf: file))
  }
}

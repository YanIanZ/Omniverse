import Foundation

public struct AdapterPreview: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case project
    case files
    case serverID = "server_id"
    case command
    case arguments
    case requiresApply = "requires_apply"
  }

  public var project: String
  public var files: [String]
  public var serverID: String
  public var command: String
  public var arguments: [String]
  public var requiresApply = true
}
public struct AgentInstaller {
  public let root: URL
  public let project: ProjectBinding
  public let executable: String
  public let dataDir: String
  public let agents: [String]
  public var serverID: String { "omnimemo_" + project.id.prefix(12) }
  private var manifestURL: URL {
    root.appendingPathComponent(".omnimemo-installer/\(serverID).json")
  }
  private struct Manifest: Codable {
    enum CodingKeys: String, CodingKey {
      case serverID = "server_id"
      case files
    }

    var serverID: String
    var files: [Change]
  }
  private struct Change: Codable {
    var path: String
    var kind: String
    var content: Data
    var existed: Bool
    var before: Data?
  }
  public init(
    configRoot: String, project: String, executable: String, dataDir: String, agents: [String]
  ) throws {
    self.root = canonical(configRoot)
    self.project = try ProjectBinding(path: project)
    self.executable = canonical(executable).path
    self.dataDir = canonical(dataDir).path
    self.agents = agents
    guard !agents.isEmpty, Set(agents).isSubset(of: ["codex", "claude"]) else {
      throw MemoError.invalid("supported adapters: codex,claude")
    }
  }
  public var arguments: [String] {
    ["--data-dir", dataDir, "--project", project.root.path, "mcp", "serve", "--stdio"]
  }
  public func preview() -> AdapterPreview {
    AdapterPreview(
      project: project.root.path,
      files: agents.map { $0 == "codex" ? ".codex/config.toml" : ".mcp.json" } + [
        ".agents/skills/omnimem-recall/SKILL.md", ".agents/skills/omnimem-handoff/SKILL.md",
      ], serverID: serverID, command: executable, arguments: arguments)
  }
  private func allowed(_ relative: String) throws -> URL {
    let url = root.appendingPathComponent(relative)
    var ancestor = url
    while !FileManager.default.fileExists(atPath: ancestor.path) && ancestor.path != root.path
      && ancestor.path != "/"
    { ancestor = ancestor.deletingLastPathComponent() }
    let resolved = ancestor.resolvingSymlinksInPath().path
    guard resolved == root.path || resolved.hasPrefix(root.path + "/") else {
      throw MemoError.denied
    }
    guard url.standardizedFileURL.path.hasPrefix(root.path + "/") else { throw MemoError.denied }
    return url
  }
  private func read(_ relative: String) throws -> Data? {
    let path = try allowed(relative)
    guard FileManager.default.fileExists(atPath: path.path) else { return nil }
    let attrs = try path.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard attrs.isRegularFile == true, (attrs.fileSize ?? Int.max) <= 2 * 1024 * 1024 else {
      throw MemoError.invalid("configuration file too large or not regular")
    }
    return try Data(contentsOf: path)
  }
  private var codexBlock: String {
    let quote: (String) -> String = {
      let e = JSONEncoder()
      e.outputFormatting = [.withoutEscapingSlashes]
      return String(decoding: try! e.encode($0), as: UTF8.self)
    }
    return
      "# BEGIN OmniMemo \(serverID)\n[mcp_servers.\(serverID)]\ncommand = \(quote(executable))\nargs = [\(arguments.map(quote).joined(separator:", "))]\n# END OmniMemo \(serverID)\n"
  }
  private var claudeEntry: [String: Any] {
    ["type": "stdio", "command": executable, "args": arguments]
  }
  private func isSameJSON(_ a: Any, _ b: Any) -> Bool {
    (try? JSONSerialization.data(withJSONObject: a, options: .sortedKeys))
      == (try? JSONSerialization.data(withJSONObject: b, options: .sortedKeys))
  }
  public func apply() throws {
    try project.validate()
    _ = try allowed(".omnimemo-installer/\(serverID).json")
    if let data = try? Data(contentsOf: manifestURL),
      let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
    {
      // Repeated install is a no-op only while the managed entries are intact.
      for change in manifest.files { try verify(change) }
      return
    }
    var changes: [Change] = []
    for agent in agents {
      if agent == "codex" {
        let name = ".codex/config.toml"
        let before = try read(name)
        let text = before.map { String(decoding: $0, as: UTF8.self) } ?? ""
        guard !text.contains(serverID) else {
          throw MemoError.invalid("unmanaged Codex server id collision")
        }
        let content = Data(((text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + codexBlock).utf8)
        changes.append(
          Change(path: name, kind: "toml", content: content, existed: before != nil, before: before)
        )
      } else {
        let name = ".mcp.json"
        let before = try read(name)
        var document =
          try before.map {
            try JSONSerialization.jsonObject(with: $0) as? [String: Any]
              ?? { throw MemoError.invalid("MCP config must be an object") }()
          } ?? [:]
        if let value = document["mcpServers"], !(value is [String: Any]) {
          throw MemoError.invalid("mcpServers must be an object")
        }
        var servers = document["mcpServers"] as? [String: Any] ?? [:]
        guard servers[serverID] == nil else {
          throw MemoError.invalid("unmanaged Claude server id collision")
        }
        servers[serverID] = claudeEntry
        document["mcpServers"] = servers
        let output = try JSONSerialization.data(
          withJSONObject: document, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        changes.append(
          Change(path: name, kind: "json", content: output, existed: before != nil, before: before))
      }
    }
    for (name, text) in [
      ("omnimem-recall", try Self.loadSkill("omnimem-recall")),
      ("omnimem-handoff", try Self.loadSkill("omnimem-handoff")),
    ] {
      let path = ".agents/skills/\(name)/SKILL.md"
      let before = try read(path)
      guard before == nil else {
        throw MemoError.invalid("existing skill requires manual merge: \(name)")
      }
      changes.append(
        Change(path: path, kind: "file", content: Data(text.utf8), existed: false, before: nil))
      if agents.contains("claude") {
        // A short Claude entry point directs the agent to the same canonical skill body.
        let shim = ".claude/skills/\(name)/SKILL.md"
        guard try read(shim) == nil else {
          throw MemoError.invalid("existing Claude skill requires manual merge")
        }
        let body =
          "---\nname: \(name)\ndescription: \(name=="omnimem-recall" ? "Recall OmniMemo project context before resuming work.":"Save an OmniMemo checkpoint before an agent handoff.")\n---\nRead `\(root.path)/.agents/skills/\(name)/SKILL.md` and follow it.\n"
        changes.append(
          Change(path: shim, kind: "file", content: Data(body.utf8), existed: false, before: nil))
      }
    }
    // Validate every destination before writing the first file.
    for c in changes { _ = try allowed(c.path) }
    try privateDirectory(manifestURL.deletingLastPathComponent())
    var written: [Change] = []
    do {
      for c in changes {
        let path = try allowed(c.path)
        try privateDirectory(path.deletingLastPathComponent())
        if let original = c.before {
          try protectedWrite(
            original,
            to: manifestURL.deletingLastPathComponent().appendingPathComponent(
              serverID + "-" + digest(c.path) + ".backup"))
        }
        let output = c.kind == "toml" ? (c.before ?? Data()) + c.content : c.content
        try protectedWrite(output, to: path)
        written.append(c)
      }
      try protectedWrite(
        try encodeJSON(Manifest(serverID: serverID, files: changes), pretty: true), to: manifestURL
      )
    } catch {
      for c in written.reversed() {
        let p = try allowed(c.path)
        if let before = c.before {
          try? protectedWrite(before, to: p)
        } else {
          try? FileManager.default.removeItem(at: p)
        }
      }
      throw error
    }
  }
  private func verify(_ c: Change) throws {
    guard let current = try read(c.path) else { throw MemoError.invalid("managed file missing") }
    switch c.kind {
    case "toml":
      guard
        String(decoding: current, as: UTF8.self).components(
          separatedBy: String(decoding: c.content, as: UTF8.self)
        ).count == 2
      else { throw MemoError.invalid("managed Codex entry changed; manual review required") }
    case "json":
      let object = try JSONSerialization.jsonObject(with: current) as? [String: Any]
      let expected =
        (try JSONSerialization.jsonObject(with: c.content) as? [String: Any])?["mcpServers"]
        as? [String: Any]
      guard let entry = (object?["mcpServers"] as? [String: Any])?[serverID],
        let expectedEntry = expected?[serverID], isSameJSON(entry, expectedEntry)
      else { throw MemoError.invalid("managed Claude entry changed; manual review required") }
    default:
      guard current == c.content else {
        throw MemoError.invalid("managed skill changed; manual review required")
      }
    }
  }
  public func uninstall(apply: Bool = false) throws -> AdapterPreview {
    guard apply else { return preview() }
    _ = try allowed(".omnimemo-installer/\(serverID).json")
    guard let data = try? Data(contentsOf: manifestURL) else { return preview() }
    let manifest = try JSONDecoder().decode(Manifest.self, from: data)
    guard manifest.serverID == serverID else { throw MemoError.denied }
    for c in manifest.files { try verify(c) }
    for c in manifest.files {
      let p = try allowed(c.path)
      let current = try Data(contentsOf: p)
      if c.kind == "toml" {
        let text = String(decoding: current, as: UTF8.self).replacingOccurrences(
          of: String(decoding: c.content, as: UTF8.self), with: "")
        if !c.existed && text.isEmpty {
          try FileManager.default.removeItem(at: p)
        } else {
          try protectedWrite(Data(text.utf8), to: p)
        }
      } else if c.kind == "json" {
        var doc = try JSONSerialization.jsonObject(with: current) as! [String: Any]
        var servers = doc["mcpServers"] as! [String: Any]
        servers.removeValue(forKey: serverID)
        doc["mcpServers"] = servers
        if servers.isEmpty, let original = c.before,
          let old = try JSONSerialization.jsonObject(with: original) as? [String: Any],
          old["mcpServers"] == nil
        {
          doc.removeValue(forKey: "mcpServers")
        }
        if let before = c.before,
          let old = try JSONSerialization.jsonObject(with: before) as? [String: Any],
          isSameJSON(doc, old)
        {
          try protectedWrite(before, to: p)
        } else if !c.existed && servers.isEmpty && doc.count == 1 {
          try FileManager.default.removeItem(at: p)
        } else {
          try protectedWrite(
            try JSONSerialization.data(
              withJSONObject: doc, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
            to: p)
        }
      } else {
        try FileManager.default.removeItem(at: p)
      }
    }
    try FileManager.default.removeItem(at: manifestURL)
    return preview()
  }
  private static func loadSkill(_ name: String) throws -> String {
    guard
      let path = Bundle.module.url(
        forResource: "SKILL", withExtension: "md", subdirectory: "Skills/" + name)
    else { throw MemoError.invalid("bundled skill is missing") }
    return try String(contentsOf: path, encoding: .utf8)
  }
}

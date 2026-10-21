import ArgumentParser
import Foundation
import OmniMemoCore

struct Options: ParsableArguments {
  @Option(name: .long, help: "Local metadata/cache root. Only init creates it.") var dataDir:
    String = defaultDataDirectory()
  @Option(name: .customLong("project"), help: "Authorized project root, fixed for this process (default: working directory).")
  var explicitProject: String?
  var project: String { explicitProject ?? FileManager.default.currentDirectoryPath }
  @Option(name: .long, help: "Provenance label; not an authentication identity.") var agent:
    String = "cli"
  @Flag(name: .long, help: "Print JSON even in a terminal (piped output is always JSON).") var json = false
  func open() async throws -> MemoryStore {
    try await MemoryStore.open(dataDir: dataDir, project: project)
  }
}
/// JSON for agents, plugins and scripts (anything that pipes us); a readable layout only when a
/// person runs the command in a terminal and did not ask for --json.
func output<T: Encodable>(_ value: T) throws {
  let data = try encodeJSON(value, pretty: true)
  guard isatty(STDOUT_FILENO) == 1, !CommandLine.arguments.contains("--json"),
    let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
  else { return print(String(decoding: data, as: UTF8.self)) }
  print(Readable.render(object))
}

enum Readable {
  /// Columns shown for lists, in this order, when the rows have them.
  static let columns = [
    "id", "agent", "client", "kind", "status", "priority", "owner", "model", "title", "action",
    "requested_by", "last_seen", "created_at", "session_id",
  ]

  static func render(_ object: Any) -> String {
    if let rows = object as? [[String: Any]] { return table(rows) }
    if let list = object as? [Any] { return list.isEmpty ? "(none)" : list.map(cell).joined(separator: "\n") }
    if let fields = object as? [String: Any] {
      let width = fields.keys.map(\.count).max() ?? 0
      return fields.keys.sorted().map { key in
        key.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + cell(fields[key]!)
      }.joined(separator: "\n")
    }
    return cell(object)
  }

  static func table(_ rows: [[String: Any]]) -> String {
    guard !rows.isEmpty else { return "(none)" }
    let keys = columns.filter { key in rows.contains { $0[key] != nil && !($0[key] is [Any]) && !($0[key] is [String: Any]) } }
      .prefix(6)
    let cells = rows.map { row in keys.map { row[$0].map { String(cell($0).prefix(40)) } ?? "" } }
    let widths = keys.enumerated().map { i, key in max(key.count, cells.map { $0[i].count }.max() ?? 0) }
    let line = { (values: [String]) in
      zip(values, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: "  ")
        .trimmingCharacters(in: .whitespaces)
    }
    return ([line(keys.map { $0.uppercased() })] + cells.map(line)).joined(separator: "\n")
      + "\n(\(rows.count) \(rows.count == 1 ? "row" : "rows"); --json for every field)"
  }

  static func cell(_ value: Any) -> String {
    switch value {
    case let text as String: return text
    case let number as NSNumber:
      return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "yes" : "no") : number.stringValue
    case is NSNull: return "-"
    default:
      let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) ?? Data()
      return String(decoding: data, as: UTF8.self)
    }
  }
}
@main
struct OmniMemo: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "omnimem", abstract: "Local Swift + MongoDB memory and handoff for coding agents.",
    version: "0.3.0",
    subcommands: [
      Init.self, Status.self, Doctor.self, Project.self, Memory.self, Context.self, Checkpoint.self,
      Cache.self, MCP.self, Rea.self, Install.self, Uninstall.self, Wake.self, Recall.self,
      Agents.self, Tasks.self, Runtime.self, Statusline.self, Rollover.self, Codex.self, OpenCode.self, Approvals.self, Redis.self, Autosave.self, Serve.self, Office.self, Stop.self, Hook.self,
    ])
  @OptionGroup var options: Options
  /// Bare `om`: status plus the next useful command; never starts a server.
  func run() async throws {
    let store = try await options.open()
    do {
      let s = try await store.status()
      let running = ServerState.read(dataDir: options.dataDir, project: s.projectID).map {
        "running on port \($0.port); open it with: om office"
      }
      try output([
        "project": URL(fileURLWithPath: options.project).lastPathComponent, "project_id": s.projectID,
        "records": String(s.records), "storage": "available",
        "office": running ?? "not running; start it with: om office",
        "next": "om context \"what you are about to do\" · om recall <words> · om office (Mission Control)",
      ])
      await store.close()
    } catch {
      await store.close()
      throw MemoryStore.safeError(error)
    }
  }
  struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Explicitly initialize MongoDB indexes and local metadata/cache.")
    @OptionGroup var options: Options
    @Option(help: "MongoDB URI without credentials; OMNIMEM_MONGO_URI, if set, takes precedence.")
    var mongoUri: String?
    @Option(help: "Disposable cache quota in MiB.") var cacheMib: Int = 32
    @Option(help: "Storage profile: mongodb (default; MongoDB, optional Redis) or sqlite (embedded db/memory.sqlite).")
    var backend: String?
    @Flag(help: "Make this data directory the default via a small user-level pointer.")
    var setDefault = false
    func run() async throws {
      guard (0...2048).contains(cacheMib) else {
        throw ValidationError("cache-mib must be 0...2048")
      }
      let store = try await MemoryStore.initialize(
        dataDir: options.dataDir, project: options.project, uri: mongoUri,
        cacheMaxBytes: cacheMib * 1024 * 1024, backend: backend)
      do {
        if setDefault {
          let pointer = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            ".config/omnimem/location.json")
          try privateDirectory(pointer.deletingLastPathComponent())
          if FileManager.default.fileExists(atPath: pointer.path) {
            try FileManager.default.copyItem(
              at: pointer,
              to: pointer.deletingLastPathComponent().appendingPathComponent(
                "location-\(UUID().uuidString).backup"))
          }
          try protectedWrite(
            try encodeJSON(["data_dir": canonical(options.dataDir).path]), to: pointer)
        }
        try output(await store.status())
        await store.close()
      } catch {
        await store.close()
        throw MemoryStore.safeError(error)
      }
    }
  }
  struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show the project, its record count and storage state.")
    @OptionGroup var options: Options
    func run() async throws {
      let store = try await options.open()
      do {
        try output(await store.status())
        await store.close()
      } catch {
        await store.close()
        throw MemoryStore.safeError(error)
      }
    }
  }
  struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check storage, MCP and host adapters; prints no secrets.")
    @OptionGroup var options: Options
    func run() async throws {
      let store = try await options.open()
      do {
        let s = try await store.status()
        try output([
          "backend": s.backend, "project_id": s.projectID, "storage": "available", "schema": "1",
          "mcp": "Swift SDK 0.12.x; stdio", "adapters": "codex,claude",
          "token_counter": "conservative UTF-8 bound; not exact tokenizer",
        ])
        await store.close()
      } catch {
        await store.close()
        throw MemoryStore.safeError(error)
      }
    }
  }
  struct Project: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Show how OmniMemo identifies a project folder.", subcommands: [Attach.self])
    struct Attach: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Argument var path: String?
      func run() async throws {
        let p = try ProjectBinding(path: path ?? options.project)
        try output([
          "project_id": p.id, "root": p.root.path, "branch": p.branch, "git_head": p.head,
        ])
      }
    }
  }
  struct Memory: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Save, search, show, list, delete or export memories.", subcommands: [
      Save.self, Search.self, Show.self, List.self, Delete.self, Export.self,
    ])
    struct Save: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Option(help: "fact, decision, task, issue, preference, insight or checkpoint.") var kind: String = "fact"
      @Option(help: "Short title.") var title: String
      @Option(
        help: "Memory text; for sensitive environments use --stdin instead of shell arguments.")
      var content: String?
      @Flag(help: "Read memory text from stdin.") var stdin = false
      @Option(name: .customLong("source"), help: "Project file that backs this memory; it is marked stale when the file changes.")
      var sources: [String] = []
      @Option(name: .customLong("tag"), help: "Label for finding it later (repeat for each).") var tags: [String] = []
      @Option(help: "Reusing the same key updates the same memory instead of adding another.") var idempotencyKey: String?
      @Option(help: "What the fact is about, e.g. AuthService (optional).") var subject: String?
      @Option(help: "The relation, e.g. uses or replaces (optional).") var predicate: String?
      func run() async throws {
        guard stdin != (content != nil) else {
          throw ValidationError("provide exactly one of --content or --stdin")
        }
        let text: String
        if stdin {
          let data = FileHandle.standardInput.readData(ofLength: 32769)
          guard data.count <= 32768 else { throw ValidationError("stdin exceeds 32 KiB") }
          text = String(decoding: data, as: UTF8.self)
        } else {
          text = content!
        }
        let store = try await options.open()
        do {
          try output(
            await store.save(
              SaveInput(
                kind: kind, title: title, content: text, sources: sources, tags: tags,
                idempotencyKey: idempotencyKey, subject: subject, predicate: predicate),
              agent: options.agent))
          await store.close()
        } catch {
          await store.close()
          throw MemoryStore.safeError(error)
        }
      }
    }
    struct Search: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Argument var query: String
      @Option var limit: Int = 8
      func run() async throws {
        let store = try await options.open()
        do {
          try output(await store.search(query, limit: limit))
          await store.close()
        } catch {
          await store.close()
          throw MemoryStore.safeError(error)
        }
      }
    }
    struct Show: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Argument var id: String
      func run() async throws {
        let store = try await options.open()
        do {
          try output(await store.get(id))
          await store.close()
        } catch {
          await store.close()
          throw MemoryStore.safeError(error)
        }
      }
    }
    struct List: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Option var limit: Int = 20
      func run() async throws {
        let store = try await options.open()
        do {
          try output(await store.search(limit: limit))
          await store.close()
        } catch {
          await store.close()
          throw MemoryStore.safeError(error)
        }
      }
    }
    struct Delete: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Argument var id: String
      @Flag(help: "Confirm permanent deletion of this record and invalidation of local cache.")
      var confirm = false
      func run() async throws {
        guard confirm else { throw ValidationError("deletion requires --confirm") }
        let store = try await options.open()
        do {
          try await store.delete(id)
          try output(["deleted": id])
          await store.close()
        } catch {
          await store.close()
          throw MemoryStore.safeError(error)
        }
      }
    }
    struct Export: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Option var outputFile: String
      func run() async throws {
        let destination = canonical(outputFile)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
          throw ValidationError("export destination exists")
        }
        let store = try await options.open()
        do {
          let records = try await store.exportRecords()
          let data = try records.reduce(into: Data()) {
            $0.append(try encodeJSON($1))
            $0.append(0x0a)
          }
          try protectedWrite(data, to: destination)
          try output(["exported": String(records.count), "format": "jsonl"])
          await store.close()
        } catch {
          await store.close()
          throw MemoryStore.safeError(error)
        }
      }
    }
  }
  struct Context: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print a short memory brief for what you are about to do.")
    @OptionGroup var options: Options
    @Argument(help: "What you are about to work on, in plain words (not a task id).") var task: String?
    @Option(help: "Upper bound for the brief, in tokens.") var maxTokens: Int = 500
    @Flag(help: "Session capsule; printed only when changed since this session last received it.")
    var firstPrompt = false
    @Option(help: "Session for --first-prompt; --agent names the provider.") var session: String?
    func validate() throws {
      if firstPrompt {
        guard session != nil else {
          throw ValidationError("--first-prompt requires --session")
        }
      } else if task == nil {
        throw ValidationError("provide a task or --first-prompt")
      }
    }
    func run() async throws {
      let store = try await options.open()
      do {
        let data =
          firstPrompt
          ? try await store.promptContext(
            agent: options.agent, session: session!, maxTokens: maxTokens)
          : try await store.context(task: task!, maxTokens: maxTokens)
        if let data {
          FileHandle.standardOutput.write(data)
          print("")
        }
        await store.close()
      } catch {
        await store.close()
        throw MemoryStore.safeError(error)
      }
    }
  }
  struct Checkpoint: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Save a handoff for the next session: done, next, blocked, tests, changed files.")
    @OptionGroup var options: Options
    @Option(help: "Short title for this handoff.") var title: String = "Session handoff"
    @Option(help: "Something finished (repeat for each).") var done: [String] = []
    @Option(help: "What the next session should do (repeat for each).") var next: [String] = []
    @Option(help: "What is stuck and why (repeat for each).") var blocked: [String] = []
    @Option(help: "A test command and its real result (repeat for each).") var tests: [String] = []
    @Option(name: .customLong("changed-file"), help: "A file this work changed (repeat for each).")
    var changedFiles: [String] = []
    @Option(help: "Reusing the same key updates the same checkpoint instead of adding another.")
    var idempotencyKey: String?
    func run() async throws {
      let store = try await options.open()
      do {
        try output(
          await store.checkpoint(
            CheckpointInput(
              title: title, done: done, next: next, blocked: blocked, tests: tests,
              changedFiles: changedFiles, idempotencyKey: idempotencyKey), agent: options.agent))
        await store.close()
      } catch {
        await store.close()
        throw MemoryStore.safeError(error)
      }
    }
  }
  struct Cache: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Inspect or clear the disposable local cache (memory itself is kept).", subcommands: [Info.self, Clear.self])
    struct Info: AsyncParsableCommand {
      @OptionGroup var options: Options
      func run() async throws {
        let store = try await options.open()
        do {
          let s = try await store.status()
          try output(["bytes": s.cacheBytes, "max_bytes": s.cacheMaxBytes])
          await store.close()
        } catch {
          await store.close()
          throw MemoryStore.safeError(error)
        }
      }
    }
    struct Clear: AsyncParsableCommand {
      @OptionGroup var options: Options
      func run() async throws {
        let store = try await options.open()
        do {
          try await store.clearCache()
          try output(["cache": "cleared", "persistent_memory": "preserved"])
          await store.close()
        } catch {
          await store.close()
          throw MemoryStore.safeError(error)
        }
      }
    }
  }
  struct MCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "mcp", abstract: "Run the MCP server that agent hosts connect to.", subcommands: [Serve.self])
    struct Serve: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Flag(help: "Serve MCP using standard input/output.") var stdio = false
      func run() async throws {
        guard stdio else { throw ValidationError("only --stdio transport is supported") }
        // Hosts may start MCP servers from any directory: the project is never inferred (SPEC V21).
        guard options.explicitProject != nil else {
          throw ValidationError("mcp serve needs --project; use scripts/global-mcp.sh for hosts")
        }
        let store = try await options.open()
        try await MCPService.serve(store: store, agent: options.agent)
      }
    }
  }
  struct Install: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Preview (or --apply) project MCP and skill config for agent hosts.")
    @OptionGroup var options: Options
    @Option(help: "Comma-separated host adapters.") var agents: String = "codex,claude"
    @Option(help: "Root receiving .codex/config.toml, .mcp.json and skills; defaults to project.")
    var configRoot: String?
    @Flag(help: "Apply the preview with backups. Otherwise only print the managed additions.")
    var apply = false
    @Flag(help: "Include the complete pinned REA skill and a separate REA MCP server.")
    var withRea = false
    @Option(help: "REA runtime manifest used by --with-rea.") var reaRuntimeManifest: String?
    func run() async throws {
      let installer = try AgentInstaller(
        configRoot: configRoot ?? options.project, project: options.project,
        executable: executablePath(), dataDir: options.dataDir,
        agents: agents.split(separator: ",").map(String.init), withRea: withRea,
        reaManifestPath: reaRuntimeManifest)
      if apply { try installer.apply() }
      try output(installer.preview())
    }
  }
  struct Uninstall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Remove the project host config OmniMemo manages; memory is kept.")
    @OptionGroup var options: Options
    @Option var agents: String = "codex,claude"
    @Option var configRoot: String?
    @Flag(help: "Remove only intact managed entries. Memory remains.") var apply = false
    func run() async throws {
      let installer = try AgentInstaller(
        configRoot: configRoot ?? options.project, project: options.project,
        executable: executablePath(), dataDir: options.dataDir,
        agents: agents.split(separator: ",").map(String.init))
      try output(installer.uninstall(apply: apply))
    }
  }
}

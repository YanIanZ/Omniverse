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
  func open() async throws -> MemoryStore {
    try await MemoryStore.open(dataDir: dataDir, project: project)
  }
}
func output<T: Encodable>(_ value: T) throws {
  print(String(decoding: try encodeJSON(value, pretty: true), as: UTF8.self))
}
@main
struct OmniMemo: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "omnimem", abstract: "Local Swift + MongoDB memory and handoff for coding agents.",
    version: "0.3.0",
    subcommands: [
      Init.self, Status.self, Doctor.self, Project.self, Memory.self, Context.self, Checkpoint.self,
      Cache.self, MCP.self, Rea.self, Install.self, Uninstall.self, Wake.self, Recall.self,
      Agents.self, Tasks.self, Runtime.self, Statusline.self, Rollover.self, Codex.self, Approvals.self, Redis.self, Autosave.self, Serve.self, Office.self, Stop.self, Hook.self,
    ])
  @OptionGroup var options: Options
  /// Bare `om`: status plus the next useful command; never starts a server.
  func run() async throws {
    let store = try await options.open()
    do {
      let s = try await store.status()
      let running = ServerState.read(dataDir: options.dataDir).map { "http://127.0.0.1:\($0.port)/" }
      try output([
        "project_id": s.projectID, "records": String(s.records), "storage": "available",
        "office": running ?? "not running",
        "next": "om context \"<task>\" | om recall <query> | om office",
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
    @OptionGroup var options: Options
    func run() async throws {
      let store = try await options.open()
      do {
        let s = try await store.status()
        try output([
          "backend": "MongoDB", "project_id": s.projectID, "storage": "available", "schema": "1",
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
    static let configuration = CommandConfiguration(subcommands: [Attach.self])
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
    static let configuration = CommandConfiguration(subcommands: [
      Save.self, Search.self, Show.self, List.self, Delete.self, Export.self,
    ])
    struct Save: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Option var kind: String = "fact"
      @Option var title: String
      @Option(
        help: "Memory text; for sensitive environments use --stdin instead of shell arguments.")
      var content: String?
      @Flag(help: "Read memory text from stdin.") var stdin = false
      @Option(name: .customLong("source")) var sources: [String] = []
      @Option(name: .customLong("tag")) var tags: [String] = []
      @Option var idempotencyKey: String?
      @Option var subject: String?
      @Option var predicate: String?
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
    @OptionGroup var options: Options
    @Argument var task: String?
    @Option var maxTokens: Int = 500
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
    @OptionGroup var options: Options
    @Option var title: String = "Session handoff"
    @Option var done: [String] = []
    @Option var next: [String] = []
    @Option var blocked: [String] = []
    @Option var tests: [String] = []
    @Option(name: .customLong("changed-file")) var changedFiles: [String] = []
    @Option var idempotencyKey: String?
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
    static let configuration = CommandConfiguration(subcommands: [Info.self, Clear.self])
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
    static let configuration = CommandConfiguration(commandName: "mcp", subcommands: [Serve.self])
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

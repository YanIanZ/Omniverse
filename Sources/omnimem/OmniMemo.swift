import ArgumentParser
import Foundation
import OmniMemoCore

struct Options: ParsableArguments {
  @Option(name: .long, help: "Local metadata/cache root. Only init creates it.") var dataDir:
    String = defaultDataDirectory()
  @Option(name: .long, help: "Authorized project root, fixed for this process.") var project:
    String = FileManager.default.currentDirectoryPath
  @Option(name: .long, help: "Provenance label; not an authentication identity.") var agent:
    String = "cli"
  func open() async throws -> MongoStore {
    try await MongoStore.open(dataDir: dataDir, project: project)
  }
}
func output<T: Encodable>(_ value: T) throws {
  print(String(decoding: try encodeJSON(value, pretty: true), as: UTF8.self))
}
@main
struct OmniMemo: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "omnimem", abstract: "Local Swift + MongoDB memory and handoff for coding agents.",
    version: "0.1.0",
    subcommands: [
      Init.self, Status.self, Doctor.self, Project.self, Memory.self, Context.self, Checkpoint.self,
      Cache.self, MCP.self, Install.self, Uninstall.self,
    ])
  @OptionGroup var options: Options
  struct Init: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Explicitly initialize MongoDB indexes and local metadata/cache.")
    @OptionGroup var options: Options
    @Option(help: "MongoDB URI without credentials; use OMNIMEM_MONGO_URI for authentication.")
    var mongoUri: String?
    @Option(help: "Disposable cache quota in MiB.") var cacheMib: Int = 32
    @Flag(help: "Make this data directory the default via a small user-level pointer.")
    var setDefault = false
    func run() async throws {
      guard (0...2048).contains(cacheMib) else {
        throw ValidationError("cache-mib must be 0...2048")
      }
      let store = try await MongoStore.initialize(
        dataDir: options.dataDir, project: options.project, uri: mongoUri,
        cacheMaxBytes: cacheMib * 1024 * 1024)
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
        throw MongoStore.safeError(error)
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
        throw MongoStore.safeError(error)
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
        throw MongoStore.safeError(error)
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
          throw MongoStore.safeError(error)
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
          throw MongoStore.safeError(error)
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
          throw MongoStore.safeError(error)
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
          throw MongoStore.safeError(error)
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
          throw MongoStore.safeError(error)
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
          throw MongoStore.safeError(error)
        }
      }
    }
  }
  struct Context: AsyncParsableCommand {
    @OptionGroup var options: Options
    @Argument var task: String
    @Option var maxTokens: Int = 500
    func run() async throws {
      let store = try await options.open()
      do {
        let data = try await store.context(task: task, maxTokens: maxTokens)
        FileHandle.standardOutput.write(data)
        print("")
        await store.close()
      } catch {
        await store.close()
        throw MongoStore.safeError(error)
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
        throw MongoStore.safeError(error)
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
          throw MongoStore.safeError(error)
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
          throw MongoStore.safeError(error)
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
    func run() async throws {
      let installer = try AgentInstaller(
        configRoot: configRoot ?? options.project, project: options.project,
        executable: CommandLine.arguments[0], dataDir: options.dataDir,
        agents: agents.split(separator: ",").map(String.init))
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
        executable: CommandLine.arguments[0], dataDir: options.dataDir,
        agents: agents.split(separator: ",").map(String.init))
      try output(installer.uninstall(apply: apply))
    }
  }
}

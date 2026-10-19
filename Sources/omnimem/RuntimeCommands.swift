import ArgumentParser
import CryptoKit
import Darwin
import Foundation
import OmniMemoCore
import OmniServer

/// Pointer to the one OmniMemo-owned HTTP server for a data directory.
struct ServerState: Codable {
  enum CodingKeys: String, CodingKey {
    case pid, port
    case projectID = "project_id"
  }
  var pid: Int32
  var port: Int
  var projectID: String

  static func file(_ dataDir: String) -> URL {
    canonical(dataDir).appendingPathComponent("server.json")
  }
  static func read(dataDir: String) -> ServerState? {
    guard let data = try? Data(contentsOf: file(dataDir)), data.count < 4096,
      let state = try? JSONDecoder().decode(ServerState.self, from: data), alive(state.pid)
    else { return nil }
    return state
  }
  static func alive(_ pid: Int32) -> Bool { pid > 0 && kill(pid, 0) == 0 }
  /// Per-install browser/API credential; created once, private to the data directory.
  static func token(dataDir: String) throws -> String {
    let root = canonical(dataDir)
    guard FileManager.default.fileExists(atPath: root.appendingPathComponent("meta.json").path)
    else { throw MemoError.storageUnavailable }
    let url = root.appendingPathComponent("server-token")
    if let data = try? Data(contentsOf: url), data.count == 64 {
      return String(decoding: data, as: UTF8.self)
    }
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw MemoError.invalid("cannot generate server credential")
    }
    let token = bytes.map { String(format: "%02x", $0) }.joined()
    try protectedWrite(Data(token.utf8), to: url)
    return token
  }
  struct Health: Decodable {
    var pid: String
    enum CodingKeys: String, CodingKey {
      case pid
      case projectID = "project_id"
    }
    var projectID: String
  }
  /// Single-use sign-in code for the browser URL.
  static func loginCode(port: Int, token: String) async -> String? {
    guard let url = URL(string: "http://127.0.0.1:\(port)/api/v1/login-code") else { return nil }
    var request = URLRequest(url: url, timeoutInterval: 2)
    request.httpMethod = "POST"
    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return (try? JSONDecoder().decode([String: String].self, from: data))?["code"]
  }

  static func probe(port: Int, token: String) async -> Health? {
    guard let url = URL(string: "http://127.0.0.1:\(port)/api/v1/health") else { return nil }
    var request = URLRequest(url: url, timeoutInterval: 1)
    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    guard let (data, response) = try? await URLSession.shared.data(for: request),
      (response as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return try? JSONDecoder().decode(Health.self, from: data)
  }
}

func withStore<T>(_ options: Options, _ body: (MemoryStore) async throws -> T) async throws -> T {
  let store = try await options.open()
  do {
    let value = try await body(store)
    await store.close()
    return value
  } catch {
    await store.close()
    throw MemoryStore.safeError(error)
  }
}

extension OmniMemo {
  struct Wake: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "(internal, used by host adapters) Mark a session present; never starts a server.")
    @OptionGroup var options: Options
    @Option(help: "Host session identifier; --agent names the provider (e.g. claude).")
    var session: String
    @Option(help: "waiting, working, blocked or offline (ready/active/disconnected accepted).") var status = "waiting"
    func run() async throws {
      try await withStore(options) { store in
        try output(
          await store.wake(agent: options.agent, session: session, status: status, source: "cli"))
      }
    }
  }

  struct Recall: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Search project memory (same as om memory search).")
    @OptionGroup var options: Options
    @Argument var query: String
    @Option(help: "Most results to show.") var limit: Int = 8
    func run() async throws {
      try await withStore(options) { try output(await $0.search(query, limit: limit)) }
    }
  }

  struct Agents: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Agent sessions OmniMemo has seen; ones with no recent signal are marked stale.")
    @OptionGroup var options: Options
    func run() async throws {
      try await withStore(options) { try output(await $0.agents()) }
    }
  }

  struct Tasks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Shared project tasks; every change names the revision you last read, so two agents cannot overwrite each other.",
      subcommands: [List.self, Add.self, Move.self, Milestones.self], defaultSubcommand: List.self)
    struct List: AsyncParsableCommand {
      @OptionGroup var options: Options
      func run() async throws {
        try await withStore(options) { try output(await $0.listTasks()) }
      }
    }
    struct Add: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Argument var title: String
      @Option var idempotencyKey: String?
      @Option(help: "P0 (urgent) to P3.") var priority = "P2"
      func run() async throws {
        try await withStore(options) {
          try output(
            await $0.createTask(
              title: title, idempotencyKey: idempotencyKey, priority: priority,
              agent: options.agent))
        }
      }
    }
    struct Move: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Argument var id: String
      @Argument(help: "todo, doing, review, done or blocked.") var status: String
      @Option(help: "Revision you last read (see om tasks list); stale revisions are rejected.") var revision: Int
      @Option var owner: String?
      func run() async throws {
        try await withStore(options) {
          try output(
            await $0.updateTask(
              id: id, expectedRevision: revision, status: status, owner: owner,
              agent: options.agent))
        }
      }
    }
    /// Verified-progress plan: progress is the verified share of milestone weight.
    struct Milestones: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Task milestones; progress counts only verified ones.", subcommands: [Add.self, Verify.self])
      struct Add: AsyncParsableCommand {
        @OptionGroup var options: Options
        @Argument var task: String
        @Argument var title: String
        @Option var weight = 1
        func run() async throws {
          try await withStore(options) {
            try output(await $0.addMilestone(taskID: task, title: title, weight: weight, agent: options.agent))
          }
        }
      }
      struct Verify: AsyncParsableCommand {
        @OptionGroup var options: Options
        @Argument var task: String
        @Argument var milestone: String
        @Option(help: "What proves it, e.g. a test command and result.") var evidence: String
        @Flag(help: "Mark it unverified again.") var revert = false
        func run() async throws {
          try await withStore(options) {
            try output(
              await $0.setMilestone(
                taskID: task, milestoneID: milestone, verified: !revert, evidence: evidence,
                agent: options.agent))
          }
        }
      }
    }
  }

  /// Runtime bridge: adapter events in, agent cards out (docs/RUNTIME_EVENTS.md).
  struct Runtime: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Runtime events from host adapters and the agent cards they produce.",
      subcommands: [Ingest.self, Sessions.self, Doctor.self])
    struct Ingest: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "(internal, used by host adapters) Ingest JSON or JSONL runtime events from stdin.")
      @OptionGroup var options: Options
      func run() async throws {
        let input = FileHandle.standardInput.readData(ofLength: 1 << 20 + 1)
        guard input.count <= 1 << 20 else { throw MemoError.invalid("input over 1 MiB") }
        let text = String(decoding: input, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // One (possibly pretty-printed) JSON object is one event; otherwise each line is one event.
        let single = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) is [String: Any]
        let lines = single ? [text] : text.split(whereSeparator: \.isNewline).map(String.init)
        struct Rejected: Encodable {
          var accepted = false
          var error: String
        }
        var failed = false
        try await withStore(options) { store in
          for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            do {
              let event = try JSONDecoder().decode(RuntimeEventInput.self, from: Data(line.utf8))
              try output(try await store.ingest(event))
            } catch is DecodingError {
              failed = true
              try output(Rejected(error: "malformed runtime event"))
            } catch {
              failed = true
              try output(Rejected(error: MemoryStore.safeError(error).localizedDescription))
            }
          }
        }
        if failed { throw ExitCode(1) }
      }
    }
    struct Sessions: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Agent cards as Mission Control shows them (same data as om agents).")
      @OptionGroup var options: Options
      func run() async throws {
        try await withStore(options) { try output(await $0.runtimeAgents()) }
      }
    }
    struct Doctor: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Runtime bridge diagnostics without credentials or private paths.")
      @OptionGroup var options: Options
      func run() async throws {
        try await withStore(options) { store in
          let status = try await store.status()
          let agents = try await store.runtimeAgents()
          var report = [
            "storage": status.backend.lowercased(), "workspace_id": status.projectID,
            "sessions": String(agents.count),
            "server": "not running", "server_route": "unknown",
          ]
          for state in ["waiting", "working", "blocked", "offline", "stale"] {
            report["status_" + state] = String(agents.filter { $0.status == state }.count)
          }
          if let server = ServerState.read(dataDir: options.dataDir) {
            report["server"] = "running on 127.0.0.1:\(server.port)"
            if let token = try? ServerState.token(dataDir: options.dataDir),
              let url = URL(string: "http://127.0.0.1:\(server.port)/api/runtime/health")
            {
              var request = URLRequest(url: url, timeoutInterval: 2)
              request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
              let code = (try? await URLSession.shared.data(for: request)).flatMap {
                ($0.1 as? HTTPURLResponse)?.statusCode
              }
              report["server_route"] = code == 200 ? "ok" : code.map { "HTTP \($0)" } ?? "unreachable"
            }
          }
          try output(report)
        }
      }
    }
  }

  struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Run the Vapor HTTP/WebSocket server in the foreground (loopback only).")
    @OptionGroup var options: Options
    @Option(help: "Loopback address to listen on (127.0.0.1 or localhost).") var host = "127.0.0.1"
    @Option(help: "Port to listen on.") var port = 8787
    @Option(help: "Built React dist directory; defaults to the packaged frontend.") var dist:
      String?
    @Option(name: .customLong("dev-origin"), help: "Allowed Vite dev origin, e.g. http://127.0.0.1:5173.")
    var devOrigins: [String] = []
    func validate() throws {
      guard ["127.0.0.1", "localhost"].contains(host) else {
        throw ValidationError("only loopback binding is supported")
      }
      guard (1024...65535).contains(port) else { throw ValidationError("port must be 1024...65535") }
      for origin in devOrigins
      where !(origin.hasPrefix("http://127.0.0.1:") || origin.hasPrefix("http://localhost:")) {
        throw ValidationError("dev origins must be loopback http origins")
      }
    }
    func run() async throws {
      let token = try ServerState.token(dataDir: options.dataDir)
      if let running = ServerState.read(dataDir: options.dataDir), running.pid != getpid() {
        throw ValidationError(
          "OmniMemo server already running (pid \(running.pid), port \(running.port)); use om office or om stop")
      }
      let store = try await options.open()
      let packaged = canonical(executablePath()).deletingLastPathComponent()
        .appendingPathComponent("frontend").path
      let config = ServerConfig(
        host: host, port: port, token: token, distPath: dist.map { canonical($0).path } ?? packaged,
        devOrigins: devOrigins)
      let stateFile = ServerState.file(options.dataDir)
      defer { try? FileManager.default.removeItem(at: stateFile) }
      do {
        try await OmniServer.run(store: store, config: config) {
          try protectedWrite(
            try encodeJSON(
              ServerState(pid: getpid(), port: port, projectID: store.binding.id)), to: stateFile)
          FileHandle.standardError.write(Data("OmniMemo serving http://\(host):\(port)/\n".utf8))
        }
      } catch {
        await store.close()
        throw error
      }
      await store.close()
    }
  }

  struct Office: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Start or reuse the one OmniMemo server, then open Mission Control.")
    @OptionGroup var options: Options
    @Option(help: "Port for a new server; a running one is reused wherever it listens.") var port = 8787
    @Flag(help: "Do not open a browser; print a single-use sign-in link instead.") var noOpen = false
    func run() async throws {
      let token = try ServerState.token(dataDir: options.dataDir)
      let binding = try ProjectBinding(path: options.project)
      let lock = canonical(options.dataDir).appendingPathComponent("server.lock")
      guard mkdir(lock.path, 0o700) == 0 else {
        throw ValidationError("another om office is starting; retry shortly")
      }
      defer { rmdir(lock.path) }
      var reused = true
      var state = ServerState.read(dataDir: options.dataDir)
      if let running = state {
        guard let health = await ServerState.probe(port: running.port, token: token),
          health.pid == String(running.pid)
        else { throw ValidationError("server pid \(running.pid) is not responding; run om stop") }
        guard health.projectID == binding.id else {
          throw ValidationError(
            "Mission Control is already serving another project on port \(running.port). Run om stop, then om office here.")
        }
      } else {
        reused = false
        try spawnServer()
        for _ in 0..<60 {
          try await Task.sleep(nanoseconds: 250_000_000)
          state = ServerState.read(dataDir: options.dataDir)
          if let s = state, await ServerState.probe(port: s.port, token: token) != nil { break }
          state = nil
        }
        guard state != nil else {
          throw ValidationError("server did not start; see \(canonical(options.dataDir).path)/server.log")
        }
      }
      let base = "http://127.0.0.1:\(state!.port)/"
      // The plain URL does not sign in: a browser needs this single-use link.
      guard let code = await ServerState.loginCode(port: state!.port, token: token) else {
        throw ValidationError("server did not issue a sign-in code; see server.log in the data directory")
      }
      let signIn = base + "auth?code=" + code
      if !noOpen {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = [signIn]
        try open.run()
        open.waitUntilExit()
      }
      var result = ["url": base, "pid": String(state!.pid), "reused": String(reused)]
      if noOpen {
        result["sign_in"] = signIn
        result["note"] = "sign_in works once, within 60 s, in a browser on this Mac"
      }
      try output(result)
    }
    /// New session (setsid) so the server survives the terminal; output goes to server.log.
    func spawnServer() throws {
      let log = canonical(options.dataDir).appendingPathComponent("server.log").path
      let args = [
        executablePath(), "--data-dir", canonical(options.dataDir).path, "--project",
        canonical(options.project).path, "serve", "--port", String(port),
      ]
      var actions: posix_spawn_file_actions_t?
      posix_spawn_file_actions_init(&actions)
      defer { posix_spawn_file_actions_destroy(&actions) }
      posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
      posix_spawn_file_actions_addopen(&actions, 1, log, O_WRONLY | O_CREAT | O_APPEND, 0o600)
      posix_spawn_file_actions_adddup2(&actions, 1, 2)
      var attributes: posix_spawnattr_t?
      posix_spawnattr_init(&attributes)
      defer { posix_spawnattr_destroy(&attributes) }
      posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
      var argv = args.map { strdup($0) } + [nil]
      defer { for a in argv { free(a) } }
      var pid: pid_t = 0
      let result = posix_spawn(&pid, args[0], &actions, &attributes, &argv, environ)
      guard result == 0 else { throw ValidationError("cannot start server (errno \(result))") }
    }
  }

  struct Stop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Stop the OmniMemo-owned server only; databases are never touched.")
    @OptionGroup var options: Options
    func run() async throws {
      guard let state = ServerState.read(dataDir: options.dataDir) else {
        try? FileManager.default.removeItem(at: ServerState.file(options.dataDir))
        try output(["server": "not running"])
        return
      }
      let token = try ServerState.token(dataDir: options.dataDir)
      // Signal only a pid that proves it is our server on the recorded port.
      guard let health = await ServerState.probe(port: state.port, token: token),
        health.pid == String(state.pid)
      else { throw ValidationError("pid \(state.pid) is not a responding OmniMemo server") }
      kill(state.pid, SIGTERM)
      for _ in 0..<40 where ServerState.alive(state.pid) {
        try await Task.sleep(nanoseconds: 250_000_000)
      }
      guard !ServerState.alive(state.pid) else { throw ValidationError("server did not stop") }
      try? FileManager.default.removeItem(at: ServerState.file(options.dataDir))
      try output(["server": "stopped", "pid": String(state.pid)])
    }
  }

  struct Autosave: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Opt-in automatic memory: session-end checkpoints, task/approval transitions, prompt summaries.",
      subcommands: [Enable.self, Disable.self, Status.self], defaultSubcommand: Status.self)
    struct Enable: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Flag(inversion: .prefixedNo, help: "Checkpoint at session end (git branch, commit, changed files, owned tasks).")
      var checkpoints = true
      @Flag(inversion: .prefixedNo, help: "Remember task review/done/blocked and approval decisions.")
      var transitions = true
      @Flag(inversion: .prefixedNo, help: "Store a short, secret-checked summary of each prompt (never the full text).")
      var prompts = true
      func run() async throws {
        let root = canonical(options.dataDir)
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("meta.json").path)
        else { throw MemoError.storageUnavailable }
        let value = AutoSave(checkpoints: checkpoints, transitions: transitions, prompts: prompts)
        try value.write(root)
        try output(value)
      }
    }
    struct Disable: AsyncParsableCommand {
      @OptionGroup var options: Options
      func run() async throws {
        let root = canonical(options.dataDir)
        try AutoSave().write(root)
        try output(AutoSave())
      }
    }
    struct Status: AsyncParsableCommand {
      @OptionGroup var options: Options
      func run() async throws { try output(AutoSave.load(canonical(options.dataDir))) }
    }
  }

  struct Redis: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Optional Redis live signal (Pub/Sub only; never keys, FLUSH or CONFIG).",
      subcommands: [Enable.self, Disable.self, Status.self], defaultSubcommand: Status.self)
    struct Enable: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Option(help: "Existing Redis server, without credentials.") var url = "redis://127.0.0.1:6379"
      func run() async throws {
        let root = canonical(options.dataDir)
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("meta.json").path)
        else { throw MemoError.storageUnavailable }
        try output(["redis": try await RedisSignal.enable(url: url, dataRoot: root), "state": "enabled"])
      }
    }
    struct Disable: AsyncParsableCommand {
      @OptionGroup var options: Options
      func run() async throws {
        try RedisSignal.disable(dataRoot: canonical(options.dataDir))
        try output(["state": "disabled"])
      }
    }
    struct Status: AsyncParsableCommand {
      @OptionGroup var options: Options
      func run() async throws {
        let url = RedisSignal.configuredURL(dataRoot: canonical(options.dataDir))
        let source = ProcessInfo.processInfo.environment["OMNIMEM_REDIS_URL"] != nil ? "environment" : "data directory"
        // Never print a credential-bearing environment URL.
        try output(url == nil ? ["state": "disabled"] : ["state": "enabled", "source": source,
          "url": url!.contains("@") ? "redis://<credentials hidden>" : url!])
      }
    }
  }

  struct Approvals: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Ask a human to decide. Decisions are made only in Mission Control.",
      subcommands: [List.self, Request.self, Show.self], defaultSubcommand: List.self)
    struct List: AsyncParsableCommand {
      @OptionGroup var options: Options
      func run() async throws {
        try await withStore(options) { try output(await $0.listApprovals()) }
      }
    }
    struct Request: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Argument(help: "What needs approval, e.g. \"push main to origin\".") var action: String
      @Option var reason = ""
      func run() async throws {
        try await withStore(options) {
          try output(
            await $0.requestApproval(action: action, reason: reason, agent: options.agent))
        }
      }
    }
    struct Show: AsyncParsableCommand {
      @OptionGroup var options: Options
      @Argument var id: String
      func run() async throws {
        try await withStore(options) { store in
          guard let record = try await store.listApprovals(limit: 500).first(where: { $0.id == id })
          else { throw MemoError.notFound }
          try output(record)
        }
      }
    }
  }

  /// Claude Code `statusLine` command: prints one line and records the reported context usage.
  struct Statusline: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "(internal, used by the Claude Code status line) Record reported context usage; never blocks the host.")
    @OptionGroup var options: Options
    @Argument(help: "Only claude reports context usage through a status line.") var host: String

    func run() async {
      let input = FileHandle.standardInput.readData(ofLength: 65537)
      guard host == "claude", input.count <= 65536,
        let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any]
      else { return print("OmniMemo") }
      let window = object["context_window"] as? [String: Any]
      let percent = (window?["used_percentage"] as? NSNumber)?.doubleValue
      let model = object["model"] as? [String: Any]
      guard let percent else { return print("OmniMemo · ctx unknown") }
      let level = ContextUsage.level(percent)
      var line = "OmniMemo · ctx \(Int(percent))%"
      if level == "handoff" || level == "critical" { line += " · fresh session advised: om rollover prepare" }
      print(line)
      guard let session = object["session_id"] as? String,
        let cwd = ((object["workspace"] as? [String: Any])?["project_dir"] as? String) ?? object["cwd"] as? String,
        Self.due(dataDir: options.dataDir, session: session, percent: percent),
        let project = Hook.gitRoot(cwd),
        let store = try? await MemoryStore.open(dataDir: options.dataDir, project: project)
      else { return }
      if (try? await store.recordContext(
        agent: "claude", session: session, model: model?["id"] as? String, usedPercent: percent,
        windowTokens: (window?["context_window_size"] as? NSNumber)?.intValue)) != nil
      {
        Self.stamp(dataDir: options.dataDir, session: session, percent: percent)
      }
      await store.close()
    }

    /// Local stamp so most refreshes skip opening the store; the store applies the same rule.
    static func due(dataDir: String, session: String, percent: Double) -> Bool {
      // The id names a file here, so it must be a plain label.
      guard (1...128).contains(session.utf8.count),
        session.range(of: "^[A-Za-z0-9._:-]+$", options: .regularExpression) != nil, !session.hasPrefix(".")
      else { return false }
      let folder = canonical(dataDir).appendingPathComponent("statusline")
      let file = folder.appendingPathComponent(session)
      let now = Date().timeIntervalSince1970
      if let text = try? String(contentsOf: file, encoding: .utf8) {
        let parts = text.split(separator: " ").compactMap { Double($0) }
        if parts.count == 2, ContextUsage.level(parts[1]) == ContextUsage.level(percent),
          now - parts[0] < MemoryStore.contextSampleInterval || abs(parts[1] - percent) < 1
        {
          return false
        }
      }
      return true
    }

    static func stamp(dataDir: String, session: String, percent: Double) {
      let folder = canonical(dataDir).appendingPathComponent("statusline")
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try? "\(Date().timeIntervalSince1970) \(percent)".write(
        to: folder.appendingPathComponent(session), atomically: true, encoding: .utf8)
    }
  }

  /// Manual fresh-session handoff near context capacity. Nothing is launched (suggest mode).
  struct Rollover: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "Hand work to a fresh agent session near the context limit: a short summary (capsule) saved as a checkpoint.",
      subcommands: [Preview.self, Prepare.self, Begin.self, Link.self, Report.self])
    struct Target: ParsableArguments {
      @Option(help: "Host session id whose reported context usage to include.") var session: String?
      @Option(help: "Provider whose tasks lead the capsule (default: all open tasks).") var provider: String?
    }
    struct Preview: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "Print the capsule; writes nothing.")
      @OptionGroup var options: Options
      @OptionGroup var target: Target
      func run() async throws {
        try await withStore(options) { print(try await Rollover.capsule($0, options, target).text, terminator: "") }
      }
    }
    struct Prepare: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Save the capsule as a checkpoint first, then print it with its handoff id.")
      @OptionGroup var options: Options
      @OptionGroup var target: Target
      func run() async throws {
        try await withStore(options) { store in
          let capsule = try await Rollover.capsule(store, options, target)
          let digest = SHA256.hash(data: Data(capsule.text.utf8)).map { String(format: "%02x", $0) }.joined()
          let saved = try await store.prepareRollover(capsule, agent: options.agent, digest: digest)
          print(capsule.text + "Handoff: \(saved.id) · digest \(digest.prefix(16)) (\(saved.disposition))")
        }
      }
    }

    // A host that starts its own fresh session (Claude Code /clear from a mod): begin reserves the
    // only child of the parent, link records the new session, report settles it on the ACK.
    struct Begin: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "(internal, used by the Claude Code plugin) Reserve the one fresh session a parent may hand off to.")
      @OptionGroup var options: Options
      @Option(help: "The parent session id (the one handing off).") var session: String
      @Option var provider = "claude"
      func run() async throws {
        let reserved = try await withStore(options) { try await $0.beginRollover(agent: provider, parent: session) }
        if !reserved { throw ExitCode(1) }
      }
    }
    struct Link: AsyncParsableCommand {
      static let configuration = CommandConfiguration(abstract: "(internal, used by the Claude Code plugin) Record the fresh session of a reserved handoff.")
      @OptionGroup var options: Options
      @Option(help: "The parent session id (the one handing off).") var session: String
      @Option var child: String
      @Option var provider = "claude"
      func run() async throws {
        try await withStore(options) { store in
          // The host's own start hook may not have reported the child yet.
          _ = try await store.ingest(
            RuntimeEventInput(
              source: provider + "_mod", provider: provider, externalSessionID: child, eventType: "session.started",
              metadata: ["observability": .string("passive")]))
          try await store.linkRolloverChild(agent: provider, parent: session, child: child)
        }
      }
    }
    struct Report: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "(internal, used by the Claude Code plugin) Record whether the fresh session acknowledged the handoff.")
      @OptionGroup var options: Options
      @Option(help: "The parent session id (the one handing off).") var session: String
      @Option(help: "Fresh child session; omit for a same-session reset.") var child: String?
      @Option var provider = "claude"
      @Option(help: "Digest printed by prepare.") var digest: String
      @Option(help: "completed (acknowledged) or failed.") var outcome: String
      @Option var reason = ""
      func validate() throws {
        guard ["completed", "failed"].contains(outcome) else { throw ValidationError("--outcome completed|failed") }
      }
      func run() async throws {
        let ok = outcome == "completed"
        let why = reason.isEmpty ? outcome : reason
        try await withStore(options) {
          if let child {
            try await $0.finishRollover(agent: provider, parent: session, child: child, acknowledged: ok, reason: why)
          } else {
            try await $0.reportInPlaceRollover(agent: provider, session: session, digest: digest, acknowledged: ok, reason: why)
          }
        }
      }
    }

    static func capsule(_ store: MemoryStore, _ options: Options, _ target: Target) async throws -> ContextCapsule {
      let root = store.binding.root.path
      let status = git(root, ["status", "--porcelain"]) ?? ""
      // Paths only; renames keep the new name, deleted files are not evidence.
      let files = status.split(separator: "\n").compactMap { line -> String? in
        guard line.count > 3 else { return nil }
        let path = String(line.dropFirst(3)).components(separatedBy: " -> ").last!
        return FileManager.default.fileExists(atPath: root + "/" + path) ? path : nil
      }
      return try await store.rolloverCapsule(
        agent: target.provider ?? (target.session == nil ? nil : "claude"), session: target.session,
        gitBranch: git(root, ["rev-parse", "--abbrev-ref", "HEAD"]),
        gitCommit: git(root, ["rev-parse", "--short", "HEAD"]), changedFiles: files)
    }

    static func git(_ root: String, _ args: [String]) -> String? {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      p.arguments = ["-C", root] + args
      let out = Pipe()
      p.standardOutput = out
      p.standardError = FileHandle.nullDevice
      guard (try? p.run()) != nil else { return nil }
      let data = out.fileHandleForReading.readDataToEndOfFile()
      p.waitUntilExit()
      let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
      return p.terminationStatus == 0 && !text.isEmpty ? text : nil
    }
  }

  struct Hook: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      abstract: "(internal, used by host adapters) Lifecycle event from a hook or plugin (stdin JSON); never blocks the host.")
    @OptionGroup var options: Options
    @Argument(help: "claude, codex, gemini or opencode.") var host: String
    @Option var maxTokens = 600

    enum Phase { case start, prompt, stop, end, tool }
    /// Host hook event -> lifecycle phase and the runtime event it proves.
    static func phase(_ event: String) -> (Phase, String)? {
      switch event {
      case "SessionStart", "session.created": return (.start, "session.started")
      case "UserPromptSubmit", "BeforeAgent", "chat.message": return (.prompt, "prompt.received")
      case "Stop", "AfterAgent", "session.idle": return (.stop, "turn.completed")
      case "SessionEnd", "session.deleted": return (.end, "session.ended")
      case "PreToolUse", "BeforeTool", "tool.execute.before": return (.tool, "tool.started")
      case "PostToolUse", "AfterTool", "tool.execute.after": return (.tool, "tool.succeeded")
      case "PostToolUseFailure", "tool.execute.failed": return (.tool, "tool.failed")
      default: return nil
      }
    }

    func run() async {
      guard ["claude", "codex", "gemini", "opencode"].contains(host) else { return }
      let input = FileHandle.standardInput.readData(ofLength: 65537)
      guard input.count <= 65536,
        let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
        let event = object["hook_event_name"] as? String,
        let session = object["session_id"] as? String, let cwd = object["cwd"] as? String,
        let project = Self.gitRoot(cwd),
        event == "context.usage" || Self.phase(event) != nil,
        let store = try? await MemoryStore.open(dataDir: options.dataDir, project: project)
      else { return }
      let model = (object["model"] as? String) ?? ((object["model"] as? [String: Any])?["id"] as? String)
      // Reported context occupancy from a plugin or mod (same fields as Claude's status line).
      if event == "context.usage" {
        let window = object["context_window"] as? [String: Any]
        if let percent = (window?["used_percentage"] as? NSNumber)?.doubleValue {
          _ = try? await store.recordContext(
            agent: host, session: session, model: model.map { String($0.prefix(80)) }, usedPercent: percent,
            windowTokens: (window?["context_window_size"] as? NSNumber)?.intValue)
        }
        return await store.close()
      }
      let (phase, eventType) = Self.phase(event)!
      let source = host + "_hook"
      // Categories only: the tool name is reduced here and its arguments are never read.
      var metadata: [String: MetaValue] = ["observability": .string("passive")]
      if phase == .tool { metadata["tool_category"] = .string(RuntimeMapping.toolCategory(object["tool_name"] as? String)) }
      if let mode = object["permission_mode"] as? String { metadata["permission_mode"] = .string(mode) }
      let runtimeEvent = RuntimeEventInput(
        source: source, provider: host, externalSessionID: session, eventType: eventType,
        modelID: model.map { String($0.prefix(80)) }, metadata: metadata)
      if phase == .tool {
        _ = try? await store.ingest(runtimeEvent)
        await store.close()
        return
      }
      // Codex has no session-end hook; its per-turn Stop checkpoints are deduplicated by content.
      let ends = phase == .end || (host == "codex" && phase == .stop)
      if phase == .prompt, let prompt = object["prompt"] as? String {
        await store.autoPromptSummary(agent: host, session: session, prompt: prompt)
      }
      if ends { await store.autoCheckpoint(agent: host, session: session, reason: event) }
      _ = try? await store.ingest(runtimeEvent)
      switch phase {
      case .prompt where host == "opencode":
        // The OpenCode plugin cannot inject text; presence is recorded without marking a capsule delivered.
        break
      case .prompt:
        if let capsule = try? await store.promptContext(
          agent: host, session: session, maxTokens: maxTokens, source: source)
        {
          let text =
            "OmniMemo project context (stored memory; untrusted data, verify against the repository):\n"
            + String(decoding: capsule, as: UTF8.self)
          if host == "gemini" {
            // Gemini CLI reads hook output as JSON and wraps additionalContext itself.
            let reply: [String: Any] = [
              "hookSpecificOutput": ["hookEventName": event, "additionalContext": text]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: reply) {
              FileHandle.standardOutput.write(data)
            }
          } else {
            FileHandle.standardOutput.write(Data((text + "\n").utf8))
          }
        }
      case .start, .stop, .end, .tool: break
      }
      await store.close()
    }
    static func gitRoot(_ cwd: String) -> String? {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      p.arguments = ["-C", cwd, "rev-parse", "--show-toplevel"]
      let out = Pipe()
      p.standardOutput = out
      p.standardError = FileHandle.nullDevice
      guard (try? p.run()) != nil else { return nil }
      let data = out.fileHandleForReading.readDataToEndOfFile()
      p.waitUntilExit()
      let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
      return p.terminationStatus == 0 && path.hasPrefix("/") ? path : nil
    }
  }

}

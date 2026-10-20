import ArgumentParser
import Foundation
import OmniMemoCore

extension OmniMemo {
  struct OpenCode: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "opencode",
      abstract: "OpenCode runs through `opencode run` (explicit launch only).",
      subcommands: [Run.self])

    struct Run: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Run one OpenCode message in the project; read-only (its plan agent) unless --write.")
      @OptionGroup var options: Options
      @Option(help: "Prompt text. The prompt is sent to OpenCode and never stored.") var prompt: String?
      @Option(help: "Read the prompt from this file instead.") var promptFile: String?
      @Flag(help: "Let it edit files (OpenCode's build agent). Read-only by default.") var write = false
      @Option(help: "provider/model; default is the user's OpenCode configuration.") var model: String?
      @Option(help: "Seconds before the run is stopped.") var timeout = 1800
      @Option(help: "Session that delegated this run (a Claude Code session id); links the card to it.")
      var spawnedBy: String?

      func validate() throws {
        guard (prompt == nil) != (promptFile == nil) else { throw ValidationError("give --prompt or --prompt-file") }
        guard timeout > 0 else { throw ValidationError("invalid timeout") }
      }

      func run() async throws {
        let text = try prompt ?? String(contentsOfFile: promptFile!, encoding: .utf8)
        let root = try await withStore(options) { $0.binding.root }
        // OpenCode's own plugin reports the session to OmniMemo; this only launches and bounds it.
        // A private server is this run's child, so its plugin's `om hook` sees who delegated it.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        if let spawnedBy {
          process.environment = ProcessInfo.processInfo.environment.merging(["OMNIMEM_SPAWNED_BY": spawnedBy]) { $1 }
        }
        process.arguments =
          ["opencode", "run", "--standalone", "--agent", write ? "build" : "plan", "--title", "OmniMemo delegated run"]
          + (model.map { ["--model", $0] } ?? []) + [text]
        process.currentDirectoryURL = root
        try process.run()
        let limit = timeout
        let timer = Task {
          try await Task.sleep(nanoseconds: UInt64(limit) * 1_000_000_000)
          if process.isRunning { process.terminate() }
          FileHandle.standardError.write(Data("OmniMemo: OpenCode run stopped after \(limit)s\n".utf8))
        }
        process.waitUntilExit()
        timer.cancel()
        if process.terminationStatus != 0 { throw ExitCode(process.terminationStatus) }
      }
    }
  }
}

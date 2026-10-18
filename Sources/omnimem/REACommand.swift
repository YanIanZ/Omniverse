import ArgumentParser
import Foundation
import OmniMemoCore

extension OmniMemo {
  struct Rea: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "rea", abstract: "Run the complete pinned REA CLI/MCP runtime.",
      subcommands: [Status.self, Run.self, Serve.self])
    struct RuntimeOptions: ParsableArguments {
      @Option(
        help: "Reviewed REA runtime manifest; defaults to packaged manifest or OMNIMEM_REA_RUNTIME."
      ) var runtimeManifest: String?
    }
    struct Status: AsyncParsableCommand {
      @OptionGroup var runtimeOptions: RuntimeOptions
      private struct Report: Encodable {
        let identity: REABuildIdentity
        let nodeVersion: String
        let runtimeManifest: String
        let scope: String
      }
      func run() async throws {
        let runtime = try REARuntime(manifestPath: runtimeOptions.runtimeManifest)
        try output(
          Report(
            identity: runtime.descriptor.identity, nodeVersion: runtime.nodeVersion(),
            runtimeManifest: runtime.manifestPath,
            scope:
              "Full upstream catalog; individual tools retain upstream prerequisites and host support"
          ))
      }
    }
    struct Run: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        abstract: "Forward arguments directly to the pinned REA CLI; no shell or runtime download.")
      @OptionGroup var options: Options
      @OptionGroup var runtimeOptions: RuntimeOptions
      @Argument(
        parsing: .captureForPassthrough,
        help: "REA command and options. Use -- before the upstream arguments if needed.")
      var arguments: [String] = []
      func run() async throws {
        let arguments =
          self.arguments.first == "--" ? Array(self.arguments.dropFirst()) : self.arguments
        try REARuntime(manifestPath: runtimeOptions.runtimeManifest).launch(
          arguments: arguments, project: options.project)
      }
    }
    struct Serve: AsyncParsableCommand {
      static let configuration = CommandConfiguration(
        commandName: "mcp", abstract: "Serve all upstream REA MCP tools and prompts over stdio.")
      @OptionGroup var options: Options
      @OptionGroup var runtimeOptions: RuntimeOptions
      func run() async throws {
        try REARuntime(manifestPath: runtimeOptions.runtimeManifest).launch(
          arguments: ["--mcp"], project: options.project)
      }
    }
  }
}

import Darwin
import Foundation

public struct REABuildIdentity: Codable, Sendable, Equatable {
  enum CodingKeys: String, CodingKey {
    case sourceURL = "source_url"
    case commit, version
    case entrypointSHA256 = "entrypoint_sha256"
    case lockSHA256 = "lock_sha256"
    case catalogSHA256 = "catalog_sha256"
    case mcpSHA256 = "mcp_sha256"
    case toolCount = "tool_count"
    case cliCount = "cli_count"
    case promptCount = "prompt_count"
  }
  public var sourceURL: String
  public var commit: String
  public var version: String
  public var entrypointSHA256: String
  public var lockSHA256: String
  public var catalogSHA256: String
  public var mcpSHA256: String
  public var toolCount: Int
  public var cliCount: Int
  public var promptCount: Int
}

public struct REARuntimeDescriptor: Codable, Sendable {
  enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case identity
    case packageRoot = "package_root"
    case nodePath = "node_path"
    case tempDirectory = "temp_directory"
  }
  public var schemaVersion: Int
  public var identity: REABuildIdentity
  public var packageRoot: String
  public var nodePath: String
  public var tempDirectory: String
}

public struct REARuntime: Sendable {
  public let descriptor: REARuntimeDescriptor
  public let manifestPath: String
  public static func defaultManifestPath() -> String {
    if let path = ProcessInfo.processInfo.environment["OMNIMEM_REA_RUNTIME"] { return path }
    let packaged = canonical(executablePath()).deletingLastPathComponent()
      .appendingPathComponent("rea-runtime.json")
    if FileManager.default.fileExists(atPath: packaged.path) { return packaged.path }
    return "/Volumes/Ext/DevCache/OmniMemo/integrations/rea-runtime.json"
  }
  public static func bundledIdentity() throws -> REABuildIdentity {
    guard
      let path = Bundle.module.url(
        forResource: "provenance", withExtension: "json", subdirectory: "REA")
    else {
      throw MemoError.invalid("REA provenance is missing from this build")
    }
    return try JSONDecoder().decode(REABuildIdentity.self, from: Data(contentsOf: path))
  }
  public init(manifestPath: String? = nil) throws {
    let path = canonical(manifestPath ?? Self.defaultManifestPath())
    guard let data = try? Data(contentsOf: path), data.count <= 65536,
      let descriptor = try? JSONDecoder().decode(REARuntimeDescriptor.self, from: data)
    else {
      throw MemoError.invalid(
        "REA runtime unavailable; run scripts/prepare-rea.py or select --runtime-manifest")
    }
    guard descriptor.schemaVersion == 1, descriptor.identity == (try Self.bundledIdentity()) else {
      throw MemoError.invalid("REA runtime revision or schema does not match the bundled skill")
    }
    guard descriptor.packageRoot.hasPrefix("/"), descriptor.nodePath.hasPrefix("/"),
      descriptor.tempDirectory.hasPrefix("/"),
      FileManager.default.isExecutableFile(atPath: descriptor.nodePath)
    else {
      throw MemoError.invalid("REA runtime requires absolute paths and an executable Node runtime")
    }
    let root = canonical(descriptor.packageRoot)
    for (relative, expected) in [
      ("scripts/rea.mjs", descriptor.identity.entrypointSHA256),
      ("package-lock.json", descriptor.identity.lockSHA256),
      ("dist/catalogIdentity.js", descriptor.identity.catalogSHA256),
      ("dist/mcp/main.js", descriptor.identity.mcpSHA256),
    ] {
      let file = root.appendingPathComponent(relative)
      guard file.resolvingSymlinksInPath().path.hasPrefix(root.path + "/"),
        let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
        size <= 64 * 1024 * 1024,
        let bytes = try? Data(contentsOf: file), digest(bytes) == expected
      else {
        throw MemoError.invalid("REA runtime artifact missing or changed: " + relative)
      }
    }
    self.descriptor = descriptor
    self.manifestPath = path.path
  }
  public func nodeVersion() throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: descriptor.nodePath)
    process.arguments = ["--version"]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let value = String(decoding: data, as: UTF8.self).trimmingCharacters(
      in: .whitespacesAndNewlines)
    guard process.terminationStatus == 0, data.count < 128 else {
      throw MemoError.invalid("cannot inspect Node version")
    }
    let numbers = value.dropFirst().split(separator: ".").compactMap { Int($0) }
    guard numbers.count >= 2,
      (numbers[0] == 22 && numbers[1] >= 19) || (numbers[0] == 24 && numbers[1] >= 11)
        || numbers[0] >= 26
    else {
      throw MemoError.invalid("REA requires Node 22.19+, 24.11+ or 26+")
    }
    return value
  }
  public func launch(arguments: [String], project: String) throws -> Never {
    _ = try nodeVersion()
    let binding = try ProjectBinding(path: project)
    try binding.validate()
    let temp = canonical(descriptor.tempDirectory)
    guard FileManager.default.fileExists(atPath: temp.deletingLastPathComponent().path) else {
      throw MemoError.storageUnavailable
    }
    try privateDirectory(temp)
    guard chdir(binding.root.path) == 0 else { throw MemoError.denied }
    setenv("TMPDIR", temp.path, 1)
    setenv("TMP", temp.path, 1)
    setenv("TEMP", temp.path, 1)
    // execv preserves stdio, signals and the exact upstream exit code, without a shell.
    let args =
      [
        descriptor.nodePath,
        canonical(descriptor.packageRoot).appendingPathComponent("scripts/rea.mjs").path,
      ] + arguments
    var argv = args.map { strdup($0) }
    argv.append(nil)
    defer { for argument in argv { free(argument) } }
    execv(descriptor.nodePath, &argv)
    throw MemoError.invalid("cannot execute the configured REA runtime")
  }
}

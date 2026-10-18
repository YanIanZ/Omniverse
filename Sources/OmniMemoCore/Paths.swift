import CryptoKit
import Foundation

public func digest(_ bytes: Data) -> String {
  SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}
public func digest(_ text: String) -> String { digest(Data(text.utf8)) }
public func nowISO() -> String { ISO8601DateFormatter().string(from: Date()) }
public func canonical(_ path: String) -> URL {
  URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
    .resolvingSymlinksInPath()
}
public func protectedWrite(_ data: Data, to url: URL) throws {
  try data.write(to: url, options: .atomic)
  try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}
public func privateDirectory(_ url: URL) throws {
  try FileManager.default.createDirectory(
    at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
}
public func defaultDataDirectory() -> String {
  if let explicit = ProcessInfo.processInfo.environment["OMNIMEM_HOME"] { return explicit }
  let home = FileManager.default.homeDirectoryForCurrentUser
  let pointer = home.appendingPathComponent(".config/omnimem/location.json")
  if let data = try? Data(contentsOf: pointer),
    let value = try? JSONDecoder().decode([String: String].self, from: data),
    let path = value["data_dir"]
  {
    return path
  }
  return home.appendingPathComponent(".local/share/omnimem").path
}
public struct ProjectBinding: Sendable {
  public let root: URL
  public let id: String
  private let identity: String
  public init(path: String) throws {
    root = canonical(path)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue
    else { throw MemoError.denied }
    identity = try Self.identity(root)
    let common = Self.git(root, ["rev-parse", "--git-common-dir"])
    let anchor =
      common.isEmpty
      ? root
      : URL(fileURLWithPath: common, relativeTo: root).standardizedFileURL.resolvingSymlinksInPath()
    id = digest(anchor.path)
  }
  private static func identity(_ path: URL) throws -> String {
    let a = try FileManager.default.attributesOfItem(atPath: path.path)
    return "\(a[.systemNumber] ?? ""):\(a[.systemFileNumber] ?? "")"
  }
  public func validate() throws {
    guard root.resolvingSymlinksInPath() == root, (try? Self.identity(root)) == identity else {
      throw MemoError.denied
    }
  }
  public var branch: String { Self.git(root, ["symbolic-ref", "--quiet", "--short", "HEAD"]) }
  public var head: String { Self.git(root, ["rev-parse", "--verify", "HEAD"]) }
  private static func git(_ root: URL, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", root.path] + args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do {
      try p.run()
      let d = out.fileHandleForReading.readDataToEndOfFile()
      p.waitUntilExit()
      guard p.terminationStatus == 0, d.count < 4096 else { return "" }
      return String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    } catch { return "" }
  }
  public func evidence(_ path: String) throws -> Evidence {
    try validate()
    guard path.utf8.count <= 1024 else { throw MemoError.invalid("source path too long") }
    let target = URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL
      .resolvingSymlinksInPath()
    guard target.path.hasPrefix(root.path + "/") else { throw MemoError.denied }
    let parts = target.pathComponents
    guard
      !parts.contains(where: {
        $0.hasPrefix(".env") || [".ssh", ".aws", ".gnupg", "credentials"].contains($0)
      })
    else { throw MemoError.denied }
    let attrs = try FileManager.default.attributesOfItem(atPath: target.path)
    guard attrs[.type] as? FileAttributeType == .typeRegular, let size = attrs[.size] as? NSNumber,
      size.intValue <= 4 * 1024 * 1024
    else { throw MemoError.invalid("source must be a regular file <=4 MiB") }
    let data = try Data(contentsOf: target, options: .mappedIfSafe)
    return Evidence(path: String(target.path.dropFirst(root.path.count + 1)), sha256: digest(data))
  }
}
public enum SecretFilter {
  public static func check(_ text: String) throws {
    let patterns = [
      "-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
      "(?i)(?:api[_-]?key|password|passwd|secret|access[_-]?token|authorization)\\s*[\\\"']?\\s*[:=]\\s*[\\\"']?[^\\s\\\"']{6,}",
      "(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16})",
      "mongodb(?:\\+srv)?://[^\\s/@]+:[^\\s/@]+@",
      "eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+",
    ]
    for pattern in patterns {
      if text.range(of: pattern, options: .regularExpression) != nil { throw MemoError.secret }
    }
  }
}

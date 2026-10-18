import Foundation
import NIOCore
import NIOPosix
import RediStack

/// Optional, best-effort Redis Pub/Sub hint that new events were committed to MongoDB.
/// Redis is never the event log: subscribers re-read MongoDB, and every failure is a no-op.
/// OmniMemo only PUBLISHes/SUBSCRIBEs on its own channel; it never writes keys, flushes or
/// changes the server configuration.
public enum RedisSignal {
  static let file = "redis.json"

  /// `OMNIMEM_REDIS_URL` (may carry credentials) wins over the credential-free URL that
  /// `om redis enable` stores in the data directory.
  public static func configuredURL(dataRoot: URL) -> String? {
    if let value = ProcessInfo.processInfo.environment["OMNIMEM_REDIS_URL"], !value.isEmpty {
      return value
    }
    guard let data = try? Data(contentsOf: dataRoot.appendingPathComponent(file)),
      data.count < 1024,
      let object = try? JSONDecoder().decode([String: String].self, from: data),
      let url = object["url"], (try? validate(url)) != nil
    else { return nil }
    return url
  }

  static func validate(_ url: String) throws {
    guard url.hasPrefix("redis://"), !url.contains("@"), url.utf8.count <= 256 else {
      throw MemoError.invalid("use redis:// without credentials; put credentials in OMNIMEM_REDIS_URL")
    }
  }

  public static func channel(_ projectID: String) -> RedisChannelName {
    RedisChannelName("omnimemo:v1:" + projectID.prefix(16) + ":events")
  }

  static func connect(_ url: String) async throws -> RedisConnection {
    let loop = MultiThreadedEventLoopGroup.singleton.next()
    let config = try RedisConnection.Configuration(url: url)
    let client = ClientBootstrap.makeRedisTCPClient(group: loop)
      .connectTimeout(.milliseconds(300))
    return try await RedisConnection.make(
      configuration: config, boundEventLoop: loop, configuredTCPClient: client
    ).get()
  }

  /// Verifies the server answers PING, then records the URL for every later process.
  public static func enable(url: String, dataRoot: URL) async throws -> String {
    try validate(url)
    guard let connection = try? await connect(url) else {
      throw MemoError.invalid("Redis did not accept a connection at \(url)")
    }
    let pong = try? await connection.ping().get()
    _ = try? await connection.close().get()
    guard pong == "PONG" else { throw MemoError.invalid("Redis did not answer PING") }
    try protectedWrite(try encodeJSON(["url": url], pretty: true), to: dataRoot.appendingPathComponent(file))
    return url
  }

  public static func disable(dataRoot: URL) throws {
    let path = dataRoot.appendingPathComponent(file)
    if FileManager.default.fileExists(atPath: path.path) {
      try FileManager.default.removeItem(at: path)
    }
  }

  public static func publish(projectID: String, url: String?) async {
    guard let url, let connection = try? await connect(url) else { return }
    _ = try? await connection.publish("1", to: channel(projectID)).get()
    _ = try? await connection.close().get()
  }

  /// Calls `onSignal` for each hint until the connection drops; returns the open connection.
  public static func subscribe(
    projectID: String, url: String?, onSignal: @escaping @Sendable () -> Void
  ) async -> RedisConnection? {
    guard let url, let connection = try? await connect(url) else { return nil }
    do {
      try await connection.subscribe(
        to: [channel(projectID)], messageReceiver: { _, _ in onSignal() }, onSubscribe: nil,
        onUnsubscribe: nil
      ).get()
      return connection
    } catch {
      _ = try? await connection.close().get()
      return nil
    }
  }
}

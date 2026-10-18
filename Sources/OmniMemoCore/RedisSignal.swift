import Foundation
import NIOCore
import NIOPosix
import RediStack

/// Optional, best-effort Redis Pub/Sub hint that new events were committed to MongoDB.
/// Redis is never the event log: subscribers re-read MongoDB, and every failure is a no-op.
public enum RedisSignal {
  public static var url: String? {
    guard let value = ProcessInfo.processInfo.environment["OMNIMEM_REDIS_URL"], !value.isEmpty
    else { return nil }
    return value
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
  public static func publish(projectID: String) async {
    guard let url else { return }
    guard let connection = try? await connect(url) else { return }
    _ = try? await connection.publish("1", to: channel(projectID)).get()
    _ = try? await connection.close().get()
  }
  /// Calls `onSignal` for each hint until the connection drops; returns the open connection.
  public static func subscribe(
    projectID: String, onSignal: @escaping @Sendable () -> Void
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

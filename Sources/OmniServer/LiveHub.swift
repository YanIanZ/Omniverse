import Foundation
import OmniMemoCore
import RediStack
import Vapor

/// Fans out MongoDB-committed events to WebSocket clients in one process.
/// MongoDB is polled every second; an optional Redis hint triggers an immediate poll.
public actor LiveHub {
  public static let maxClients = 32
  let store: MongoStore
  private(set) var revision: Int
  private(set) var redisState = RedisSignal.url == nil ? "disabled" : "unavailable"
  private var clients: [ObjectIdentifier: WebSocket] = [:]
  private var task: Task<Void, Never>?
  private var redis: RedisConnection?
  private let wakeups: AsyncStream<Void>
  private let wake: AsyncStream<Void>.Continuation

  init(store: MongoStore, start revision: Int) {
    self.store = store
    self.revision = revision
    (wakeups, wake) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
  }

  nonisolated func start() {
    Task { await self.run() }
  }

  private func run() async {
    let wake = self.wake
    if let connection = await RedisSignal.subscribe(
      projectID: store.binding.id, onSignal: { wake.yield() })
    {
      redis = connection
      redisState = "connected"
    }
    let ticker = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        wake.yield()
      }
    }
    task = ticker
    for await _ in wakeups {
      if Task.isCancelled || ticker.isCancelled { break }
      await poll()
    }
  }

  func stop() async {
    task?.cancel()
    wake.finish()
    for ws in clients.values { try? await ws.close(code: .goingAway) }
    clients.removeAll()
    if let redis { _ = try? await redis.close().get() }
  }

  func add(_ ws: WebSocket) async {
    guard clients.count < Self.maxClients else {
      try? await ws.close(code: .policyViolation)
      return
    }
    let id = ObjectIdentifier(ws)
    clients[id] = ws
    ws.onClose.whenComplete { _ in Task { await self.remove(id) } }
    // Clients load a REST snapshot, then apply events newer than this revision.
    if let hello = try? encodeJSON(["v": "1", "type": "hello", "revision": String(revision)]) {
      try? await ws.send(String(decoding: hello, as: UTF8.self))
    }
  }

  private func remove(_ id: ObjectIdentifier) { clients[id] = nil }

  /// Reads committed events after the last broadcast revision and sends them in order.
  func poll() async {
    guard let events = try? await store.events(after: revision), !events.isEmpty else { return }
    for event in events {
      guard event.revision > revision else { continue }
      revision = event.revision
      guard let data = try? encodeJSON(event) else { continue }
      let text = String(decoding: data, as: UTF8.self)
      for ws in clients.values { try? await ws.send(text) }
    }
  }
}

import Crypto
import Foundation
import OmniMemoCore
import Vapor

public struct ServerConfig: Sendable {
  public var host: String
  public var port: Int
  public var token: String
  public var distPath: String?
  /// Extra allowed browser origins (e.g. the Vite dev server); loopback only by policy.
  public var devOrigins: [String]
  public init(
    host: String = "127.0.0.1", port: Int = 8787, token: String, distPath: String? = nil,
    devOrigins: [String] = []
  ) {
    self.host = host
    self.port = port
    self.token = token
    self.distPath = distPath
    self.devOrigins = devOrigins
  }
  var allowedHosts: Set<String> { ["127.0.0.1:\(port)", "localhost:\(port)"] }
  var allowedOrigins: Set<String> {
    Set(["http://127.0.0.1:\(port)", "http://localhost:\(port)"] + devOrigins)
  }
}

public enum OmniServer {
  public static let cookie = "omnimemo_session"

  /// Registers middleware and routes. Returns the hub so callers can stop polling on shutdown.
  @discardableResult
  public static func configure(_ app: Application, store: MongoStore, config: ServerConfig)
    async throws -> LiveHub
  {
    try await store.ensureRuntimeIndexes()
    app.http.server.configuration.hostname = config.host
    app.http.server.configuration.port = config.port
    app.routes.defaultMaxBodySize = "16kb"
    app.middleware = .init()
    app.middleware.use(GuardMiddleware(config: config))
    if let dist = config.distPath, FileManager.default.fileExists(atPath: dist + "/index.html") {
      app.middleware.use(FileMiddleware(publicDirectory: dist + "/", defaultFile: "index.html"))
    }
    let hub = LiveHub(store: store, start: try await store.latestRevision())
    hub.start()
    app.lifecycle.use(HubLifecycle(hub: hub))

    app.get("auth") { req async throws -> Response in
      guard let token = req.query[String.self, at: "token"], matches(token, config.token) else {
        throw Abort(.unauthorized)
      }
      let response = req.redirect(to: "/")
      response.cookies[cookie] = HTTPCookies.Value(
        string: config.token, path: "/", isSecure: false, isHTTPOnly: true, sameSite: .strict)
      return response
    }

    let api = app.grouped("api", "v1").grouped(AuthMiddleware(config: config))
    api.get("health") { _ async throws -> Response in
      let status = try await store.status()
      return try json([
        "status": "ok", "storage": "mongodb", "project_id": status.projectID,
        "records": String(status.records), "revision": String(await hub.revision),
        "redis": await hub.redisState, "pid": String(getpid()),
      ])
    }
    api.get("agents") { _ async throws -> Response in try json(try await store.agents()) }
    api.get("tasks") { _ async throws -> Response in try json(try await store.listTasks()) }
    api.post("tasks") { req async throws -> Response in
      struct Body: Content {
        var title: String
        var idempotency_key: String?
      }
      let body = try req.content.decode(Body.self)
      let task = try await store.createTask(
        title: body.title, idempotencyKey: body.idempotency_key, agent: "mission-control")
      await hub.poll()
      return try json(task, status: .created)
    }
    api.patch("tasks", ":id") { req async throws -> Response in
      struct Body: Content {
        var status: String?
        var owner: String?
      }
      guard let raw = req.headers.first(name: .ifMatch),
        let revision = Int(raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")))
      else { throw Abort(.preconditionRequired, reason: "If-Match revision required") }
      let body = try req.content.decode(Body.self)
      let task = try await store.updateTask(
        id: req.parameters.get("id") ?? "", expectedRevision: revision, status: body.status,
        owner: body.owner, agent: "mission-control")
      await hub.poll()
      return try json(task)
    }
    api.get("memory", "search") { req async throws -> Response in
      let query = req.query[String.self, at: "q"] ?? ""
      let limit = min(max(req.query[Int.self, at: "limit"] ?? 20, 1), 50)
      let found = try await store.search(query, limit: limit).map {
        MemoryBrief(
          id: $0.id, title: String($0.title.prefix(120)), summary: String($0.content.prefix(240)),
          state: $0.state, sourceRefs: $0.sources.isEmpty ? nil : $0.sources.map(\.path))
      }
      return try json(found)
    }
    api.get("events") { req async throws -> Response in
      try json(try await store.events(after: max(req.query[Int.self, at: "after"] ?? 0, 0)))
    }

    app.grouped(AuthMiddleware(config: config, requireOrigin: true))
      .webSocket("ws", "v1", "live", maxFrameSize: .init(integerLiteral: 1 << 14)) {
        req, ws async in
        if let scope = req.query[String.self, at: "project_id"], scope != store.binding.id {
          try? await ws.close(code: .policyViolation)
          return
        }
        await hub.add(ws)
      }

    // SPA fallback for client routes only; API and WebSocket paths never resolve to HTML.
    app.get(.catchall) { req async throws -> Response in
      let path = req.url.path
      guard !path.hasPrefix("/api/"), !path.hasPrefix("/ws/"), let dist = config.distPath,
        FileManager.default.fileExists(atPath: dist + "/index.html")
      else { throw Abort(.notFound) }
      return try await req.fileio.asyncStreamFile(at: dist + "/index.html")
    }
    return hub
  }

  /// Foreground server until SIGINT/SIGTERM. `onReady` runs after routes are configured.
  public static func run(
    store: MongoStore, config: ServerConfig, onReady: () throws -> Void
  ) async throws {
    let app = try await Application.make(Environment(name: "production", arguments: ["om"]))
    app.logger.logLevel = .warning
    do {
      try await configure(app, store: store, config: config)
      try onReady()
      try await app.execute()
    } catch {
      try? await app.asyncShutdown()
      throw error
    }
    try await app.asyncShutdown()
  }

  static func matches(_ supplied: String, _ expected: String) -> Bool {
    let a = Data(SHA256.hash(data: Data(supplied.utf8)))
    let b = Data(SHA256.hash(data: Data(expected.utf8)))
    return a.withUnsafeBytes { x in b.withUnsafeBytes { y in zip(x, y).reduce(0) { $0 | ($1.0 ^ $1.1) } } }
      == 0
  }

  static func json<T: Encodable>(_ value: T, status: HTTPResponseStatus = .ok) throws -> Response {
    var headers = HTTPHeaders()
    headers.contentType = .json
    return Response(status: status, headers: headers, body: .init(data: try encodeJSON(value)))
  }
}

/// Host allowlist (DNS rebinding), security headers and safe error bodies for every request.
struct GuardMiddleware: AsyncMiddleware {
  let config: ServerConfig
  func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
    guard let host = req.headers.first(name: .host), config.allowedHosts.contains(host) else {
      return Response(status: .misdirectedRequest)
    }
    let response: Response
    do {
      response = try await next.respond(to: req)
    } catch let error as MemoError {
      response = try OmniServer.json(["error": error.localizedDescription], status: error.status)
    } catch let error as AbortError {
      response = try OmniServer.json(["error": error.reason], status: error.status)
    } catch {
      response = try OmniServer.json(["error": "request failed"], status: .badRequest)
    }
    response.headers.replaceOrAdd(
      name: "Content-Security-Policy",
      value:
        "default-src 'self'; connect-src 'self' ws://\(host); img-src 'self' data:; frame-ancestors 'none'"
    )
    response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
    response.headers.replaceOrAdd(name: "Referrer-Policy", value: "no-referrer")
    return response
  }
}

/// Session cookie or bearer token; browser Origin must be allowed for writes and WebSockets.
struct AuthMiddleware: AsyncMiddleware {
  let config: ServerConfig
  var requireOrigin = false
  func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
    let bearer = req.headers.bearerAuthorization?.token
    let cookie = req.cookies[OmniServer.cookie]?.string
    guard let token = bearer ?? cookie, OmniServer.matches(token, config.token) else {
      throw Abort(.unauthorized)
    }
    let origin = req.headers.first(name: .origin)
    if let origin, !config.allowedOrigins.contains(origin) { throw Abort(.forbidden) }
    let unsafe = ![.GET, .HEAD, .OPTIONS].contains(req.method)
    // Cookie-authenticated writes must prove same-origin; bearer clients are not browsers.
    if (requireOrigin || (unsafe && bearer == nil)) && origin == nil { throw Abort(.forbidden) }
    return try await next.respond(to: req)
  }
}

extension MemoError {
  var status: HTTPResponseStatus {
    switch self {
    case .invalid: return .badRequest
    case .denied: return .forbidden
    case .notFound: return .notFound
    case .conflict, .revisionConflict: return .conflict
    case .secret: return .unprocessableEntity
    case .storageUnavailable, .database: return .serviceUnavailable
    }
  }
}

struct HubLifecycle: LifecycleHandler {
  let hub: LiveHub
  func shutdownAsync(_ application: Application) async { await hub.stop() }
}

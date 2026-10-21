import Crypto
import Foundation
import OmniMemoCore
import Vapor

#if canImport(LocalAuthentication)
  import LocalAuthentication
#endif

public struct ServerConfig: Sendable {
  public var host: String
  public var port: Int
  public var token: String
  public var distPath: String?
  /// Extra allowed browser origins (e.g. the Vite dev server); loopback only by policy.
  public var devOrigins: [String]
  /// Asks the person at the Mac to confirm an approval; tests substitute their own answer.
  public var confirmPresence: @Sendable (String) async -> Bool
  public init(
    host: String = "127.0.0.1", port: Int = 8787, token: String, distPath: String? = nil,
    devOrigins: [String] = [], confirmPresence: @escaping @Sendable (String) async -> Bool = HumanPresence.confirm
  ) {
    self.host = host
    self.port = port
    self.token = token
    self.distPath = distPath
    self.devOrigins = devOrigins
    self.confirmPresence = confirmPresence
  }
  var allowedHosts: Set<String> { ["127.0.0.1:\(port)", "localhost:\(port)"] }
  var allowedOrigins: Set<String> {
    Set(["http://127.0.0.1:\(port)", "http://localhost:\(port)"] + devOrigins)
  }
}

/// Random browser sessions minted by `/auth`. The cookie never carries the server token,
/// so cookies sent to other localhost ports do not leak it.
final class BrowserSessions: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String] = []
  private var codes: [String: Date] = [:]
  /// How long a sign-in code from `om office` stays valid.
  static let codeLifetime: TimeInterval = 60

  private static func random() -> String {
    [UInt8].random(count: 32).map { String(format: "%02x", $0) }.joined()
  }

  func mint() -> String {
    let value = Self.random()
    lock.lock()
    defer { lock.unlock() }
    values = Array((values + [value]).suffix(16))
    return value
  }

  /// A short-lived, single-use code for the sign-in URL, so the server token never reaches
  /// browser history or the `open` command line.
  func mintCode() -> String {
    let code = Self.random()
    lock.lock()
    defer { lock.unlock() }
    codes = codes.filter { $0.value > Date() }
    codes[code] = Date().addingTimeInterval(Self.codeLifetime)
    return code
  }

  func redeem(_ supplied: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard let code = codes.keys.first(where: { OmniServer.matches(supplied, $0) }) else { return false }
    let expires = codes.removeValue(forKey: code)!
    return expires > Date()
  }

  func contains(_ supplied: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return values.contains { OmniServer.matches(supplied, $0) }
  }
}

/// Same-user agents can read the server token and so reach the browser routes. An approval is
/// therefore confirmed by the system owner check (Touch ID, Apple Watch or the login password),
/// a dialog the operating system shows and an agent cannot answer. Unavailable means refused.
public enum HumanPresence {
  public static func confirm(_ reason: String) async -> Bool {
    #if canImport(LocalAuthentication)
      let context = LAContext()
      var error: NSError?
      guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
      return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    #else
      return false
    #endif
  }
}

public enum OmniServer {
  /// Browsers share cookies across ports of a host, and each project's server has its own port and
  /// sessions: the name carries the port so signing in to one project does not sign out another.
  public static func cookie(_ port: Int) -> String { "omnimemo_session_\(port)" }

  /// Registers middleware and routes. Returns the hub so callers can stop polling on shutdown.
  @discardableResult
  public static func configure(_ app: Application, store: MemoryStore, config: ServerConfig)
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

    let sessions = BrowserSessions()
    app.get("auth") { req async throws -> Response in
      // A used or expired link (back button, history, another browser) lands on the locked
      // screen, which says how to get a fresh one, instead of a raw 401.
      guard let code = req.query[String.self, at: "code"], sessions.redeem(code) else {
        return req.redirect(to: "/")
      }
      let response = req.redirect(to: "/")
      response.cookies[cookie(config.port)] = HTTPCookies.Value(
        string: sessions.mint(), path: "/", isSecure: false, isHTTPOnly: true, sameSite: .strict)
      return response
    }

    let api = app.grouped("api", "v1").grouped(AuthMiddleware(config: config, sessions: sessions))
    api.get("health") { _ async throws -> Response in
      let status = try await store.status()
      return try json([
        "status": "ok", "storage": status.backend.lowercased(), "project_id": status.projectID,
        "project_name": store.binding.root.lastPathComponent,
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
        var priority: String?
      }
      let body = try req.content.decode(Body.self)
      let task = try await store.createTask(
        title: body.title, idempotencyKey: body.idempotency_key, priority: body.priority ?? "P2",
        agent: "mission-control")
      await hub.poll()
      return try json(task, status: .created)
    }
    api.patch("tasks", ":id") { req async throws -> Response in
      struct Body: Content {
        var status: String?
        var owner: String?
        var priority: String?
      }
      guard let raw = req.headers.first(name: .ifMatch),
        let revision = Int(raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")))
      else { throw Abort(.preconditionRequired, reason: "If-Match revision required") }
      let body = try req.content.decode(Body.self)
      let task = try await store.updateTask(
        id: req.parameters.get("id") ?? "", expectedRevision: revision, status: body.status,
        owner: body.owner, priority: body.priority, agent: "mission-control")
      await hub.poll()
      return try json(task)
    }
    // Bearer only (CLI): a browser session must not mint further sign-ins.
    api.post("login-code") { req async throws -> Response in
      guard req.headers.bearerAuthorization != nil else { throw Abort(.forbidden) }
      return try json(["code": sessions.mintCode()])
    }
    api.get("approvals") { _ async throws -> Response in try json(try await store.listApprovals()) }
    // Human decision: only a browser session (cookie + allowed Origin) may decide.
    // Bearer tokens are what CLIs and agents hold, so they are refused here.
    api.post("approvals", ":id", "decision") { req async throws -> Response in
      guard req.headers.bearerAuthorization == nil, req.headers.first(name: .origin) != nil else {
        throw Abort(.forbidden, reason: "decisions require the Mission Control browser session")
      }
      struct Body: Content { var decision: String }
      let body = try req.content.decode(Body.self)
      let id = req.parameters.get("id") ?? ""
      // Denying is always safe; approving needs the person at this Mac.
      if body.decision == "approved" {
        guard let pending = try await store.listApprovals().first(where: { $0.id == id && $0.status == "pending" })
        else { throw Abort(.conflict, reason: "this request was already decided") }
        let action = String(pending.action.split(whereSeparator: \.isNewline).first ?? "").prefix(120)
        guard await config.confirmPresence("approve \"\(action)\" requested by \(pending.requestedBy)") else {
          throw Abort(.forbidden, reason: "approval was not confirmed at this Mac")
        }
      }
      let record: ApprovalRecord
      do { record = try await store.decideApproval(id: id, decision: body.decision) } catch MemoError.conflict {
        throw Abort(.conflict, reason: "this request was already decided")
      }
      await hub.poll()
      return try json(record)
    }
    api.get("memory", "search") { req async throws -> Response in
      let query = req.query[String.self, at: "q"] ?? ""
      let limit = min(max(req.query[Int.self, at: "limit"] ?? 20, 1), 50)
      let found = try await store.search(query, limit: limit).map {
        MemoryBrief(
          // Checkpoints are JSON the UI renders as fields; a cut-off prefix would not parse.
          id: $0.id, title: String($0.title.prefix(120)),
          summary: $0.kind == "checkpoint" ? $0.content : String($0.content.prefix(240)),
          state: $0.state, sourceRefs: $0.sources.isEmpty ? nil : $0.sources.map(\.path))
      }
      return try json(found)
    }
    api.get("events") { req async throws -> Response in
      try json(try await store.events(after: max(req.query[Int.self, at: "after"] ?? 0, 0)))
    }

    // Runtime bridge (docs/RUNTIME_EVENTS.md). Adapters post with a bearer token; a browser
    // session must also send an allowed Origin (AuthMiddleware enforces both).
    let runtime = app.grouped("api", "runtime").grouped(AuthMiddleware(config: config, sessions: sessions))
    let workspace: @Sendable (Request) throws -> Void = { req in
      if let scope = req.query[String.self, at: "workspace_id"], scope != store.binding.id, scope != "local" {
        throw Abort(.forbidden)
      }
    }
    runtime.post("events") { req async throws -> Response in
      guard let body = req.body.data else { throw Abort(.badRequest, reason: "event body required") }
      let event: RuntimeEventInput
      do {
        event = try JSONDecoder().decode(RuntimeEventInput.self, from: body)
      } catch { throw Abort(.badRequest, reason: "malformed runtime event") }
      let result = try await store.ingest(event)
      if result.accepted { await hub.poll() }
      return try json(result, status: result.duplicate ? .ok : .accepted)
    }
    runtime.get("sessions") { req async throws -> Response in
      try workspace(req)
      struct Body: Encodable {
        var workspace_id: String
        var agents: [RuntimeAgentView]
      }
      return try json(Body(workspace_id: store.binding.id, agents: try await store.runtimeAgents()))
    }
    runtime.get("tasks") { req async throws -> Response in
      try workspace(req)
      struct Item: Encodable {
        var task: TaskRecord
        var progress: OmniMemoCore.Progress
      }
      let tasks = try await store.listTasks().map { Item(task: $0, progress: .of($0.milestones)) }
      return try json(["tasks": tasks])
    }
    runtime.get("health") { _ async throws -> Response in
      let status = try await store.status()
      return try json([
        "status": "ok", "storage": status.backend.lowercased(), "workspace_id": status.projectID,
        "revision": String(await hub.revision), "redis": await hub.redisState,
      ])
    }

    // `/ws/office` is the v2.3 name for the same committed-event stream.
    for path in [["ws", "v1", "live"], ["ws", "office"]] {
      app.grouped(AuthMiddleware(config: config, sessions: sessions, requireOrigin: true))
        .webSocket(path.map { PathComponent(stringLiteral: $0) }, maxFrameSize: .init(integerLiteral: 1 << 14)) {
          req, ws async in
          let scope = req.query[String.self, at: "project_id"] ?? req.query[String.self, at: "workspace_id"]
          if let scope, scope != store.binding.id {
            try? await ws.close(code: .policyViolation)
            return
          }
          await hub.add(ws)
        }
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
    store: MemoryStore, config: ServerConfig, onReady: () throws -> Void
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
      // Not a client mistake we recognised: report a server failure, not a 400.
      response = try OmniServer.json(["error": "request failed"], status: .internalServerError)
    }
    response.headers.replaceOrAdd(
      name: "Content-Security-Policy",
      value:
        "default-src 'self'; connect-src 'self' ws://\(host); img-src 'self' data:; frame-ancestors 'none'"
    )
    response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
    // Vite fingerprints assets; the HTML that names them must be revalidated after upgrades.
    let path = req.url.path
    if path.hasPrefix("/assets/") {
      response.headers.replaceOrAdd(name: .cacheControl, value: "public, max-age=31536000, immutable")
    } else {
      response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
    }
    response.headers.replaceOrAdd(name: "Referrer-Policy", value: "no-referrer")
    return response
  }
}

/// Session cookie or bearer token; browser Origin must be allowed for writes and WebSockets.
struct AuthMiddleware: AsyncMiddleware {
  let config: ServerConfig
  let sessions: BrowserSessions
  var requireOrigin = false
  func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
    let bearer = req.headers.bearerAuthorization?.token
    let cookie = req.cookies[OmniServer.cookie(config.port)]?.string
    if let bearer {
      guard OmniServer.matches(bearer, config.token) else { throw Abort(.unauthorized) }
    } else {
      guard let cookie, sessions.contains(cookie) else { throw Abort(.unauthorized) }
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

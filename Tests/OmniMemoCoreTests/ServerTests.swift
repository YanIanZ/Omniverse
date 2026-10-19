import OmniServer
import XCTVapor
import XCTest

@testable import OmniMemoCore

final class ServerTests: XCTestCase {
  let token = String(repeating: "a", count: 64)

  func app(dist: String? = nil, present: Bool = true) async throws -> (Application, MemoryStore) {
    let (_, store) = try await MongoTests().fixture()
    let app = try await Application.make(.testing)
    try await OmniServer.configure(
      app, store: store,
      config: ServerConfig(port: 8787, token: token, distPath: dist, confirmPresence: { _ in present }))
    addTeardownBlock { try? await app.asyncShutdown() }
    return (app, store)
  }

  func headers(_ extra: [(String, String)] = [], auth: Bool = true) -> HTTPHeaders {
    var h = HTTPHeaders([("Host", "127.0.0.1:8787")] + extra)
    if auth { h.bearerAuthorization = .init(token: token) }
    return h
  }

  /// Signs in like the browser does and returns the minted session cookie value.
  func session(_ app: Application) async throws -> String {
    var value = ""
    try await app.test(.GET, "auth?code=\(try await code(app))", headers: headers(auth: false)) {
      value = $0.headers.setCookie?[OmniServer.cookie]?.string ?? ""
    }
    return value
  }

  /// A single-use sign-in code, as `om office` requests it with the bearer token.
  func code(_ app: Application) async throws -> String {
    var value = ""
    try await app.test(.POST, "api/v1/login-code", headers: headers()) {
      value = (try? $0.content.decode([String: String].self))?["code"] ?? ""
    }
    return value
  }

  func testAuthHostAndOriginGuards() async throws {
    let (app, store) = try await app()
    try await app.test(.GET, "api/v1/health", headers: headers(auth: false)) {
      XCTAssertEqual($0.status, .unauthorized)
    }
    try await app.test(.GET, "api/v1/health", headers: HTTPHeaders([("Host", "evil.test:8787")])) {
      XCTAssertEqual($0.status, .misdirectedRequest)
    }
    try await app.test(
      .GET, "api/v1/tasks", headers: headers([("Origin", "http://evil.test")])
    ) { XCTAssertEqual($0.status, .forbidden) }
    // Cookie-authenticated writes without an Origin are refused (CSRF defence).
    let cookie = try await session(app)
    try await app.test(
      .POST, "api/v1/tasks",
      headers: headers(
        [("Cookie", "omnimemo_session=\(cookie)"), ("Content-Type", "application/json")],
        auth: false),
      body: ByteBuffer(string: #"{"title":"x"}"#)
    ) { XCTAssertEqual($0.status, .forbidden) }
    try await app.test(.GET, "auth?code=wrong", headers: headers(auth: false)) {
      XCTAssertEqual($0.status, .unauthorized)
    }
    // The token itself is no longer a sign-in URL; only a single-use code from the CLI is.
    try await app.test(.GET, "auth?token=\(token)", headers: headers(auth: false)) {
      XCTAssertEqual($0.status, .unauthorized)
    }
    let signIn = try await code(app)
    try await app.test(.GET, "auth?code=\(signIn)", headers: headers(auth: false)) {
      XCTAssertEqual($0.status, .seeOther)
      let cookie = $0.headers.first(name: .setCookie) ?? ""
      XCTAssertTrue(cookie.contains("HttpOnly") && cookie.contains("SameSite=Strict"))
      XCTAssertFalse(cookie.contains(token), "the cookie never carries the server token")
    }
    try await app.test(.GET, "auth?code=\(signIn)", headers: headers(auth: false)) {
      XCTAssertEqual($0.status, .unauthorized, "a sign-in code works once")
    }
    try await app.test(.GET, "api/v1/health", headers: headers()) { res in
      XCTAssertEqual(res.status, .ok)
      XCTAssertTrue(res.body.string.contains(store.binding.id))
      XCTAssertFalse(res.body.string.contains("mongodb://"))
      XCTAssertNotNil(res.headers.first(name: "Content-Security-Policy"))
    }
  }

  func testRuntimeRoutesDedupAndWorkspaceAuth() async throws {
    let (app, store) = try await app()
    let event = RuntimeEventInput(
      source: "test_adapter", provider: "codex", externalSessionID: "runtime1",
      eventType: "prompt.received")
    let body = ByteBuffer(data: try JSONEncoder().encode(event))
    let jsonHeaders = headers([("Content-Type", "application/json")])
    try await app.test(.POST, "api/runtime/events", headers: headers(auth: false), body: body) {
      XCTAssertEqual($0.status, .unauthorized)
    }
    try await app.test(.POST, "api/runtime/events", headers: jsonHeaders, body: body) {
      XCTAssertEqual($0.status, .accepted)
      let result = try $0.content.decode(IngestResult.self)
      XCTAssertTrue(result.accepted)
      XCTAssertFalse(result.duplicate)
      XCTAssertEqual(result.status, "working")
    }
    try await app.test(.POST, "api/runtime/events", headers: jsonHeaders, body: body) {
      XCTAssertEqual($0.status, .ok)
      XCTAssertTrue(try $0.content.decode(IngestResult.self).duplicate)
    }
    for route in ["sessions", "tasks", "health"] {
      try await app.test(.GET, "api/runtime/\(route)", headers: headers(auth: false)) {
        XCTAssertEqual($0.status, .unauthorized)
      }
      try await app.test(.GET, "api/runtime/\(route)", headers: headers()) {
        XCTAssertEqual($0.status, .ok)
      }
    }
    try await app.test(.GET, "api/runtime/sessions", headers: headers()) {
      XCTAssertTrue($0.body.string.contains(store.binding.id))
      XCTAssertTrue($0.body.string.contains("working"))
    }
    for route in ["sessions", "tasks"] {
      try await app.test(.GET, "api/runtime/\(route)?workspace_id=foreign", headers: headers()) {
        XCTAssertEqual($0.status, .forbidden)
      }
    }
    var foreign = event
    foreign.eventID = UUID().uuidString
    foreign.workspaceID = "foreign"
    try await app.test(.POST, "api/runtime/events", headers: jsonHeaders,
      body: ByteBuffer(data: try JSONEncoder().encode(foreign))) {
      XCTAssertEqual($0.status, .forbidden)
    }
    let cookie = try await session(app)
    try await app.test(.POST, "api/runtime/events",
      headers: headers([("Cookie", "omnimemo_session=\(cookie)"), ("Content-Type", "application/json")], auth: false),
      body: body) {
      XCTAssertEqual($0.status, .forbidden, "cookie writes require an Origin")
    }
  }

  func testTaskLifecycleRequiresRevision() async throws {
    let (app, _) = try await app()
    var id = ""
    try await app.test(
      .POST, "api/v1/tasks",
      headers: headers([
        ("Origin", "http://127.0.0.1:8787"), ("Content-Type", "application/json"),
      ]),
      body: ByteBuffer(string: #"{"title":"Ship the vertical slice","idempotency_key":"vs"}"#)
    ) { res in
      XCTAssertEqual(res.status, .created)
      id = try res.content.decode(TaskRecord.self).id
    }
    let patch = ByteBuffer(string: #"{"status":"doing"}"#)
    let json = ("Content-Type", "application/json")
    try await app.test(.PATCH, "api/v1/tasks/\(id)", headers: headers([json]), body: patch) {
      XCTAssertEqual($0.status, .preconditionRequired)
    }
    try await app.test(
      .PATCH, "api/v1/tasks/\(id)", headers: headers([json, ("If-Match", "1")]), body: patch
    ) { XCTAssertEqual($0.status, .ok) }
    try await app.test(
      .PATCH, "api/v1/tasks/\(id)", headers: headers([json, ("If-Match", "1")]), body: patch
    ) { XCTAssertEqual($0.status, .conflict) }
    try await app.test(.GET, "api/v1/events?after=0", headers: headers()) { res in
      let events = try res.content.decode([RuntimeEvent].self)
      XCTAssertEqual(events.map(\.revision), [1, 2])
    }
  }

  func testApprovalDecisionsOnlyFromBrowserSession() async throws {
    let (app, store) = try await app()
    let request = try await store.requestApproval(
      action: "Push main to origin", reason: "release", agent: "codex")
    let path = "api/v1/approvals/\(request.id)/decision"
    let body = ByteBuffer(string: #"{"decision":"approved"}"#)
    let json = ("Content-Type", "application/json")
    let origin = ("Origin", "http://127.0.0.1:8787")
    // Agents and CLIs hold the bearer token: they may never decide.
    try await app.test(.POST, path, headers: headers([json, origin]), body: body) {
      XCTAssertEqual($0.status, .forbidden)
    }
    // The server token itself is not a browser session, even when sent as the cookie.
    let forged = headers([json, origin, ("Cookie", "omnimemo_session=\(token)")], auth: false)
    try await app.test(.POST, path, headers: forged, body: body) {
      XCTAssertEqual($0.status, .unauthorized)
    }
    let signedIn = try await session(app)
    let browser = headers([json, origin, ("Cookie", "omnimemo_session=\(signedIn)")], auth: false)
    try await app.test(.POST, path, headers: browser, body: body) { res in
      XCTAssertEqual(res.status, .ok)
      XCTAssertEqual(try res.content.decode(ApprovalRecord.self).status, "approved")
    }
    try await app.test(.POST, path, headers: browser, body: body) {
      XCTAssertEqual($0.status, .conflict, "a request is decided once")
    }
    let events = try await store.events(after: 0).map(\.type)
    XCTAssertEqual(events, ["approval.requested", "approval.decided"])
  }

  /// A browser session is not enough to approve: the owner check at the Mac must pass too.
  func testApprovalNeedsPresenceButDenialDoesNot() async throws {
    let (app, store) = try await app(present: false)
    let request = try await store.requestApproval(action: "Push main", reason: "release", agent: "codex")
    let path = "api/v1/approvals/\(request.id)/decision"
    let signedIn = try await session(app)
    let browser = headers(
      [("Content-Type", "application/json"), ("Origin", "http://127.0.0.1:8787"), ("Cookie", "omnimemo_session=\(signedIn)")],
      auth: false)
    try await app.test(.POST, path, headers: browser, body: ByteBuffer(string: #"{"decision":"approved"}"#)) {
      XCTAssertEqual($0.status, .forbidden)
    }
    let still = try await store.listApprovals().first { $0.id == request.id }
    XCTAssertEqual(still?.status, "pending")
    try await app.test(.POST, path, headers: browser, body: ByteBuffer(string: #"{"decision":"denied"}"#)) {
      XCTAssertEqual($0.status, .ok)
    }
  }

  func testSpaFallbackNeverSwallowsApi() async throws {
    let dist = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try privateDirectory(dist)
    try Data("<div id=root></div>".utf8).write(to: dist.appendingPathComponent("index.html"))
    addTeardownBlock { try? FileManager.default.removeItem(at: dist) }
    let (app, _) = try await app(dist: dist.path)
    try await app.test(.GET, "office/agents", headers: headers(auth: false)) {
      XCTAssertEqual($0.status, .ok)
      XCTAssertTrue($0.body.string.contains("root"))
    }
    try await app.test(.GET, "api/v1/missing", headers: headers()) {
      XCTAssertEqual($0.status, .notFound)
      XCTAssertFalse($0.body.string.contains("root"))
    }
  }
}

import Foundation
import MCP
import OmniMemoCore

struct GetInput: Codable { var id: String }
struct ContextInput: Codable {
  enum CodingKeys: String, CodingKey {
    case task
    case maxTokens = "max_tokens"
  }

  var task: String
  var maxTokens: Int?
}

/// MCP first use is a verified presence signal: the client named itself in `initialize`.
actor MCPPresence {
  let store: MemoryStore
  let session = "mcp-" + UUID().uuidString.lowercased().prefix(12)
  private(set) var agent: String?
  init(store: MemoryStore) { self.store = store }
  func connected(_ clientName: String) async {
    agent = MemoryStore.provider(clientName)
    _ = try? await store.wake(agent: agent!, session: session, status: "waiting", source: "mcp")
  }
  func used() async {
    guard let agent else { return }
    _ = try? await store.wake(agent: agent, session: session, status: "working", source: "mcp")
  }
  func closed() async {
    guard let agent else { return }
    await store.autoCheckpoint(agent: agent, session: session, reason: "mcp disconnect")
    _ = try? await store.wake(agent: agent, session: session, status: "offline", source: "mcp")
  }
}

enum MCPService {
  static func serve(store: MemoryStore, agent: String) async throws {
    let presence = MCPPresence(store: store)
    // An explicit --agent label wins; otherwise attribute writes to the client's provider.
    let label: @Sendable () async -> String = {
      agent == "cli" ? (await presence.agent ?? agent) : agent
    }
    let server = Server(
      name: "OmniMemo", version: "0.3.0", capabilities: .init(tools: .init(listChanged: false)))
    await server.withMethodHandler(ListTools.self) { _ in .init(tools: tools) }
    await server.withMethodHandler(CallTool.self) { params in
      await presence.used()
      do {
        let arguments = params.arguments ?? [:]
        let data = try JSONEncoder().encode(arguments)
        guard data.count <= 48 * 1024 else { throw MemoError.invalid("request too large") }
        let allowed: Set<String>
        switch params.name {
        case "memory_save":
          allowed = [
            "kind", "title", "content", "sources", "tags", "idempotency_key", "subject",
            "predicate",
          ]
        case "memory_checkpoint":
          allowed = [
            "title", "done", "next", "blocked", "tests", "changed_files", "idempotency_key",
          ]
        case "memory_get": allowed = ["id"]
        case "memory_context": allowed = ["task", "max_tokens"]
        default: throw MemoError.invalid("unknown tool")
        }
        guard Set(arguments.keys).isSubset(of: allowed) else { throw MemoError.denied }
        let output: Data
        switch params.name {
        case "memory_save":
          let input = try JSONDecoder().decode(SaveInput.self, from: data)
          output = try encodeJSON(await store.save(input, agent: await label()))
        case "memory_checkpoint":
          let input = try JSONDecoder().decode(CheckpointInput.self, from: data)
          output = try encodeJSON(await store.checkpoint(input, agent: await label()))
        case "memory_get":
          output = try encodeJSON(
            await store.get(JSONDecoder().decode(GetInput.self, from: data).id))
        default:
          let input = try JSONDecoder().decode(ContextInput.self, from: data)
          output = try await store.context(task: input.task, maxTokens: input.maxTokens ?? 500)
        }
        return .init(
          content: [
            .text(text: String(decoding: output, as: UTF8.self), annotations: nil, _meta: nil)
          ], isError: false)
      } catch {
        let message: String
        if let e = error as? MemoError {
          message = e.localizedDescription
        } else if error is DecodingError {
          message = "invalid_request: malformed tool arguments"
        } else {
          message = "operation_failed: memory unavailable; continue from repository"
        }
        return .init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
      }
    }
    // Hosts usually stop MCP servers with a signal; record the disconnect before exiting.
    var watchers: [DispatchSourceSignal] = []
    for code in [SIGTERM, SIGINT, SIGHUP] {
      signal(code, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: code, queue: .global())
      source.setEventHandler {
        Task {
          await presence.closed()
          exit(0)
        }
      }
      source.resume()
      watchers.append(source)
    }
    defer { watchers.forEach { $0.cancel() } }
    let transport = StdioTransport()
    try await server.start(transport: transport) { client, _ in
      await presence.connected(client.name)
    }
    await server.waitUntilCompleted()
    await presence.closed()
    await store.close()
  }
  static func schema(_ properties: [String: Value], required: [String]) -> Value {
    .object([
      "type": .string("object"), "properties": .object(properties),
      "required": .array(required.map { .string($0) }), "additionalProperties": .bool(false),
    ])
  }
  static let string: Value = .object(["type": .string("string")])
  static let strings: Value = .object([
    "type": .string("array"), "items": .object(["type": .string("string")]), "maxItems": .int(32),
  ])
  static var tools: [Tool] {
    [
      Tool(
        name: "memory_save",
        description:
          "Save scoped project knowledge with optional source paths. Never include secrets or raw chat.",
        inputSchema: schema(
          [
            "kind": string, "title": string, "content": string, "sources": strings, "tags": strings,
            "idempotency_key": string, "subject": string, "predicate": string,
          ], required: ["kind", "title", "content"])),
      Tool(
        name: "memory_get",
        description:
          "Read one memory in the authorized project, including source freshness warnings.",
        inputSchema: schema(["id": string], required: ["id"])),
      Tool(
        name: "memory_context",
        description:
          "Retrieve a brief for the current task. max_tokens includes a conservative MCP-envelope allowance; minimum 256.",
        inputSchema: schema(
          [
            "task": string,
            "max_tokens": .object([
              "type": .string("integer"), "minimum": .int(256), "maximum": .int(16384),
            ]),
          ], required: ["task"])),
      Tool(
        name: "memory_checkpoint",
        description:
          "Save done/next/blocked/tests and existing changed_files for another agent. Test claims remain observations.",
        inputSchema: schema(
          [
            "title": string, "done": strings, "next": strings, "blocked": strings, "tests": strings,
            "changed_files": strings, "idempotency_key": string,
          ], required: [])),
    ]
  }
}

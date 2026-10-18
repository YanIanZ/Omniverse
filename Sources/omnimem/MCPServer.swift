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

enum MCPService {
  static func serve(store: MongoStore, agent: String) async throws {
    let server = Server(
      name: "OmniMemo", version: "0.1.0", capabilities: .init(tools: .init(listChanged: false)))
    await server.withMethodHandler(ListTools.self) { _ in .init(tools: tools) }
    await server.withMethodHandler(CallTool.self) { params in
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
          output = try encodeJSON(await store.save(input, agent: agent))
        case "memory_checkpoint":
          let input = try JSONDecoder().decode(CheckpointInput.self, from: data)
          output = try encodeJSON(await store.checkpoint(input, agent: agent))
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
    let transport = StdioTransport()
    try await server.start(transport: transport)
    await server.waitUntilCompleted()
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

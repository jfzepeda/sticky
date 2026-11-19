import Foundation
@testable import StickyCore
@testable import StickyMCP

final class TempStore {
    let dir: URL
    var url: URL { dir.appendingPathComponent("notes.json") }

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StickyMCPTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }
}

struct Harness {
    let temp: TempStore
    let repository: NotesRepository
    let server: MCPServer

    init(now: @escaping @Sendable () -> Date = { Date() }) throws {
        temp = try TempStore()
        repository = NotesRepository(fileURL: temp.url)
        server = MCPServer(tools: StickyTools(repository: repository, now: now), log: StderrLog(enabled: false))
    }

    /// Sends a raw line and decodes the response.
    func send(_ json: String) async throws -> JSONValue? {
        guard let data = await server.handle(Data(json.utf8)) else { return nil }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func call(_ tool: String, _ arguments: JSONValue = [:], id: Int64 = 1) async throws -> JSONValue {
        let request: JSONValue = [
            "jsonrpc": "2.0", "id": .int(id), "method": "tools/call",
            "params": ["name": .string(tool), "arguments": arguments],
        ]
        let line = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let response = try await send(line)
        return response?["result"] ?? .null
    }
}

extension JSONValue {
    var isError: Bool { self["isError"] == .bool(true) }
    var structured: JSONValue { self["structuredContent"] ?? .null }
    var errorText: String { structured["error"]?.stringValue ?? "" }
    var arrayValue: [JSONValue] { if case .array(let a) = self { return a } else { return [] } }
}

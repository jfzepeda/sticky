import Foundation
import StickyCore

/// JSON-RPC 2.0 / MCP message handling, independent of the transport.
/// Surface: `initialize`, `notifications/initialized`, `ping`, `tools/list`, `tools/call`.
public actor MCPServer {
    public static let serverName = "stickydesk"
    public static let serverVersion = "1.0.0"
    public static let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    enum ErrorCode {
        static let parseError: Int64 = -32700
        static let invalidRequest: Int64 = -32600
        static let methodNotFound: Int64 = -32601
        static let invalidParams: Int64 = -32602
        static let internalError: Int64 = -32603
    }

    private let tools: StickyTools
    private let log: StderrLog

    public init(tools: StickyTools, log: StderrLog = StderrLog()) {
        self.tools = tools
        self.log = log
    }

    /// Handles one framed message. Returns the encoded response line, or `nil` for notifications.
    public func handle(_ line: Data) async -> Data? {
        let message: JSONValue
        do {
            message = try JSONLine.decode(line)
        } catch {
            return JSONLine.encode(Self.error(id: .null, code: ErrorCode.parseError, message: "Parse error"))
        }

        guard case .object(let object) = message else {
            // Batches were removed from MCP (2025-06-18); reject arrays and scalars alike.
            return JSONLine.encode(Self.error(id: .null, code: ErrorCode.invalidRequest, message: "Invalid Request"))
        }

        let id = object["id"]
        let validID: Bool = switch id {
        case .string, .int: true
        case nil: true
        default: false
        }
        guard object["jsonrpc"] == .string("2.0"), validID else {
            return JSONLine.encode(Self.error(id: id ?? .null, code: ErrorCode.invalidRequest, message: "Invalid Request"))
        }

        guard case .string(let method)? = object["method"] else {
            // A response from the client (we never send requests) — ignore.
            if object["result"] != nil || object["error"] != nil { return nil }
            return JSONLine.encode(Self.error(id: id ?? .null, code: ErrorCode.invalidRequest, message: "Invalid Request"))
        }

        let params = object["params"]
        guard let id else {
            handleNotification(method)
            return nil
        }

        let response = await handleRequest(method: method, params: params, id: id)
        return JSONLine.encode(response)
    }

    // MARK: Dispatch

    /// `notifications/initialized`, `notifications/cancelled`, … need no action: every request
    /// is answered before the next is read. Unknown notifications are ignored per JSON-RPC.
    private func handleNotification(_ method: String) {}

    private func handleRequest(method: String, params: JSONValue?, id: JSONValue) async -> JSONValue {
        if let params, params.objectValue == nil {
            return Self.error(id: id, code: ErrorCode.invalidParams, message: "params must be an object")
        }

        switch method {
        case "initialize":
            return Self.result(id: id, initializeResult(params))
        case "ping":
            return Self.result(id: id, [:])
        case "tools/list":
            return Self.result(id: id, ["tools": .array(StickyTools.definitions)])
        case "tools/call":
            return await callTool(params: params, id: id)
        default:
            log.info("Unknown method requested")
            return Self.error(id: id, code: ErrorCode.methodNotFound, message: "Method not found: \(method.prefix(64))")
        }
    }

    private func callTool(params: JSONValue?, id: JSONValue) async -> JSONValue {
        guard case .string(let name)? = params?["name"] else {
            return Self.error(id: id, code: ErrorCode.invalidParams, message: "Missing tool name")
        }
        guard StickyTools.names.contains(name) else {
            return Self.error(id: id, code: ErrorCode.invalidParams, message: "Unknown tool: \(name.prefix(64))")
        }
        log.info("tools/call \(name)")
        let outcome = await tools.call(name: name, arguments: params?["arguments"])
        return Self.result(id: id, outcome.json)
    }

    private func initializeResult(_ params: JSONValue?) -> JSONValue {
        let requested = params?["protocolVersion"]?.stringValue
        let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
            ?? Self.supportedProtocolVersions[0]
        return [
            "protocolVersion": .string(version),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": .string(Self.serverName), "version": .string(Self.serverVersion)],
            "instructions": "Crea y consulta notas post-it de StickyDesk. Solo puedes borrar notas creadas por agentes.",
        ]
    }

    // MARK: Envelopes

    static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: JSONValue, code: Int64, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .int(code), "message": .string(message)]]
    }
}

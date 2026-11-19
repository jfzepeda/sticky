import Foundation

/// Logs go to stderr only. stdout is reserved for protocol messages.
public struct StderrLog: Sendable {
    public var enabled: Bool

    public init(enabled: Bool = true) { self.enabled = enabled }

    public func info(_ message: String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data("[stickydesk-mcp] \(message)\n".utf8))
    }
}

/// Newline-delimited JSON-RPC over stdin/stdout (MCP stdio transport).
public struct StdioTransport: Sendable {
    /// Messages larger than this are rejected without being buffered further.
    public static let maxMessageBytes = 1 << 20

    public init() {}

    /// Reads `input` until EOF, writing one response line per request to `output`.
    public func run(server: MCPServer, input: FileHandle, output: FileHandle, log: StderrLog) async {
        var buffer = Data()
        var discarding = false

        do {
            for try await byte in input.bytes {
                if byte == UInt8(ascii: "\n") {
                    if discarding {
                        discarding = false
                        write(Self.tooLargeError, to: output)
                    } else if let line = Self.trimmed(buffer) {
                        if let response = await server.handle(line) {
                            write(response, to: output)
                        }
                    }
                    buffer.removeAll(keepingCapacity: true)
                    continue
                }
                guard !discarding else { continue }
                buffer.append(byte)
                if buffer.count > Self.maxMessageBytes {
                    log.info("Message exceeds \(Self.maxMessageBytes) bytes; discarding")
                    buffer.removeAll()
                    discarding = true
                }
            }
        } catch {
            log.info("stdin read error: \(error.localizedDescription)")
        }

        // Trailing message without a final newline.
        if !discarding, let line = Self.trimmed(buffer), let response = await server.handle(line) {
            write(response, to: output)
        }
    }

    private func write(_ data: Data, to output: FileHandle) {
        var line = data
        line.append(UInt8(ascii: "\n"))
        output.write(line)
    }

    private static func trimmed(_ data: Data) -> Data? {
        var slice = data[...]
        while let last = slice.last, last == UInt8(ascii: "\r") || last == UInt8(ascii: " ") { slice = slice.dropLast() }
        while let first = slice.first, first == UInt8(ascii: " ") || first == UInt8(ascii: "\t") { slice = slice.dropFirst() }
        return slice.isEmpty ? nil : Data(slice)
    }

    private static let tooLargeError = JSONLine.encode(
        MCPServer.error(id: .null, code: MCPServer.ErrorCode.invalidRequest, message: "Message too large")
    )
}

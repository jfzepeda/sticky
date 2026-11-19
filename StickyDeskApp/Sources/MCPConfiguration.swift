import Foundation

/// Builds copy-paste configuration for MCP clients pointing at the bundled helper.
enum MCPConfiguration {
    static let serverName = "stickydesk"

    static var helperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("stickydesk-mcp", isDirectory: false)
    }

    static var isHelperInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: helperURL.path)
    }

    /// `claude mcp add stickydesk -- '<path>'` — single-quoted so spaces and `$` are literal.
    static func claudeCodeCommand(path: String = helperURL.path) -> String {
        "claude mcp add \(serverName) -- \(shellQuoted(path))"
    }

    /// `{"mcpServers": {"stickydesk": {"command": "<path>", "args": []}}}`
    static func claudeDesktopJSON(path: String = helperURL.path) -> String {
        let object: [String: Any] = [
            "mcpServers": [serverName: ["command": path, "args": [String]()]],
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

import Foundation
import Testing
@testable import StickyCore
@testable import StickyMCP

@Suite("JSON-RPC protocol")
struct ProtocolTests {
    @Test func initializeListAndCall() async throws {
        let h = try Harness()
        let initResponse = try #require(try await h.send(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#))
        #expect(initResponse["id"] == 1)
        #expect(initResponse["result"]?["protocolVersion"] == "2025-06-18")
        #expect(initResponse["result"]?["serverInfo"]?["name"] == "stickydesk")
        #expect(initResponse["result"]?["capabilities"]?["tools"] != nil)

        #expect(try await h.send(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)

        let list = try #require(try await h.send(#"{"jsonrpc":"2.0","id":"two","method":"tools/list"}"#))
        #expect(list["id"] == "two")
        let names = Set((list["result"]?["tools"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue })
        #expect(names == ["create_note", "list_projects", "list_notes", "delete_note"])

        let call = try await h.call("create_note", ["text": "desde el protocolo"])
        #expect(!call.isError)
        #expect(call["content"]?.arrayValue.first?["type"] == "text")
    }

    @Test func unknownVersionNegotiatesLatest() async throws {
        let h = try Harness()
        let response = try await h.send(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        #expect(response?["result"]?["protocolVersion"] == .string(MCPServer.supportedProtocolVersions[0]))
    }

    @Test func errorCodes() async throws {
        let h = try Harness()
        #expect(try await h.send("{nope")?["error"]?["code"] == -32700)
        #expect(try await h.send("[1,2]")?["error"]?["code"] == -32600)
        #expect(try await h.send(#"{"jsonrpc":"1.0","id":1,"method":"ping"}"#)?["error"]?["code"] == -32600)
        #expect(try await h.send(#"{"jsonrpc":"2.0","id":{"x":1},"method":"ping"}"#)?["error"]?["code"] == -32600)
        #expect(try await h.send(#"{"jsonrpc":"2.0","id":1,"method":"resources/list"}"#)?["error"]?["code"] == -32601)
        #expect(try await h.send(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"rm_rf"}}"#)?["error"]?["code"] == -32602)
        #expect(try await h.send(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":[1]}"#)?["error"]?["code"] == -32602)
        #expect(try await h.send(#"{"jsonrpc":"2.0","id":7,"method":"ping"}"#)?["result"] == [:])
        // Unknown notifications get no response.
        #expect(try await h.send(#"{"jsonrpc":"2.0","method":"notifications/whatever"}"#) == nil)
    }
}

/// Spawns the real `stickydesk-mcp` binary and talks to it over pipes.
@Suite("stdio end-to-end")
struct StdioTests {
    /// `<package>/.build/debug/stickydesk-mcp`, built by `swift build` / `swift test`.
    static var binaryURL: URL? {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // StickyMCPTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
        var candidates = [packageRoot.appendingPathComponent(".build/debug/stickydesk-mcp")]
        candidates += Bundle.allBundles
            .filter { $0.bundlePath.hasSuffix(".xctest") }
            .map { $0.bundleURL.deletingLastPathComponent().appendingPathComponent("stickydesk-mcp") }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    @Test(.enabled(if: StdioTests.binaryURL != nil, "Build the stickydesk-mcp product first (swift build)"))
    func stdoutContainsOnlyJSONRPC() async throws {
        let binary = try #require(Self.binaryURL)
        let temp = try TempStore()

        let process = Process()
        process.executableURL = binary
        process.environment = ["STICKYDESK_STORE_PATH": temp.url.path]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"create_note","arguments":{"text":"hola\nmundo"}}}"#,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_notes","arguments":{}}}"#,
        ]
        stdin.fileHandleForWriting.write(Data((requests.joined(separator: "\n") + "\n").utf8))
        try stdin.fileHandleForWriting.close()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errors = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(!errors.isEmpty, "Logs should go to stderr")

        let lines = String(decoding: output, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.last == "", "Output must end with a newline")
        let messages = lines.dropLast()
        #expect(messages.count == 4, "One response per request, none for the notification")

        var ids: [JSONValue] = []
        for line in messages {
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))
            #expect(value["jsonrpc"] == "2.0")
            #expect(value["result"] != nil || value["error"] != nil)
            ids.append(value["id"] ?? .null)
        }
        #expect(ids == [1, 2, 3, 4])

        let last = try JSONDecoder().decode(JSONValue.self, from: Data(messages[3].utf8))
        let notes = last["result"]?["structuredContent"]?["notes"]?.arrayValue ?? []
        #expect(notes.first?["text"] == "hola\nmundo")
    }

    /// Real cross-process contention: the MCP binary and an in-process "app" repository
    /// write to the same file at the same time; no write may be lost.
    @Test(.enabled(if: StdioTests.binaryURL != nil, "Build the stickydesk-mcp product first (swift build)"))
    func concurrentAppAndMCPWritesAreNotLost() async throws {
        let binary = try #require(Self.binaryURL)
        let temp = try TempStore()
        let count = 25  // below the 30/min agent rate limit

        let process = Process()
        process.executableURL = binary
        process.environment = ["STICKYDESK_STORE_PATH": temp.url.path]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()

        let lines = (0..<count).map { i in
            #"{"jsonrpc":"2.0","id":\#(i),"method":"tools/call","params":{"name":"create_note","arguments":{"text":"mcp \#(i)"}}}"#
        }
        let app = NotesRepository(fileURL: temp.url)
        async let appWrites: Void = {
            for i in 0..<count {
                try await app.update { store in try store.addNote(text: "app \(i)", projectID: nil) }
            }
        }()
        stdin.fileHandleForWriting.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        try stdin.fileHandleForWriting.close()
        try await appWrites

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let responses = String(decoding: output, as: UTF8.self).split(separator: "\n")
        #expect(responses.count == count)
        #expect(!responses.contains { $0.contains("\"isError\":true") })

        let final = await app.load()
        #expect(final.notes.count == count * 2)
        #expect(final.notes.filter(\.isAgentNote).count == count)
    }
}

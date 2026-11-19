import Foundation
import Testing
@testable import StickyCore
@testable import StickyMCP

@Suite("MCP tools")
struct ToolTests {
    @Test func createNoteValidatesLengthAndEmptyText() async throws {
        let h = try Harness()
        #expect(try await h.call("create_note", ["text": "   "]).isError)
        #expect(try await h.call("create_note", ["text": .string(String(repeating: "a", count: 501))]).isError)
        #expect(try await h.call("create_note", [:]).isError)
        #expect(try await h.call("create_note", ["text": 42]).isError)
        #expect(try await h.call("create_note", ["text": "ok", "evil": true]).isError)

        let ok = try await h.call("create_note", ["text": "  Hola\u{0007}  "])
        #expect(!ok.isError)
        #expect(ok.structured["text"] == "Hola")
        #expect(ok.structured["project"] == .null)
        let stored = await h.repository.load()
        #expect(stored.notes.count == 1)
        #expect(stored.notes[0].createdBy == "agent")
    }

    @Test func createNoteResolvesProjectCaseInsensitively() async throws {
        let h = try Harness()
        try await h.repository.update { try $0.addProject(name: "Trabajo", color: .vanilla) }
        let result = try await h.call("create_note", ["text": "x", "project": "TRABAJO"])
        #expect(!result.isError)
        #expect(result.structured["project"] == "Trabajo")
    }

    @Test func missingProjectErrorListsValidProjects() async throws {
        let h = try Harness()
        try await h.repository.update { store in
            try store.addProject(name: "Trabajo", color: .vanilla)
            try store.addProject(name: "Casa", color: .vanilla)
        }
        let result = try await h.call("create_note", ["text": "x", "project": "Viajes"])
        #expect(result.isError)
        #expect(result.errorText.contains("Casa, Trabajo"))
        #expect(await h.repository.load().notes.isEmpty)
    }

    @Test func createProjectIfMissingCreatesIt() async throws {
        let h = try Harness()
        let result = try await h.call("create_note",
                                      ["text": "x", "project": "Viajes", "create_project_if_missing": true])
        #expect(!result.isError)
        let store = await h.repository.load()
        #expect(store.projects.map(\.name) == ["Viajes"])
        #expect(store.projects[0].color == Palette.color(forProjectIndex: 0))
    }

    @Test func idempotencyKeyDoesNotDuplicate() async throws {
        let h = try Harness()
        let a = try await h.call("create_note", ["text": "x", "idempotency_key": "abc"])
        let b = try await h.call("create_note", ["text": "x", "idempotency_key": "abc"])
        #expect(a.structured["id"] == b.structured["id"])
        #expect(b.structured["reused"] == true)
        #expect(await h.repository.load().notes.count == 1)
    }

    @Test func deleteNoteRejectsNonAgentNotes() async throws {
        let h = try Harness()
        let (_, user) = try await h.repository.update { try $0.addNote(text: "Usuario", projectID: nil) }
        let denied = try await h.call("delete_note", ["id": .string(user.id.uuidString)])
        #expect(denied.isError)
        #expect(denied.errorText.contains("Permiso denegado"))

        let created = try await h.call("create_note", ["text": "Agente"])
        let id = try #require(created.structured["id"])
        let deleted = try await h.call("delete_note", ["id": id])
        #expect(!deleted.isError)
        #expect(await h.repository.load().notes.map(\.text) == ["Usuario"])

        #expect(try await h.call("delete_note", ["id": "nope"]).isError)
    }

    @Test func rateLimitAndQuota() async throws {
        let clock = TestClock()
        let h = try Harness(now: { clock.now })
        for i in 0..<30 {
            #expect(!(try await h.call("create_note", ["text": .string("n\(i)")])).isError)
        }
        let limited = try await h.call("create_note", ["text": "extra"])
        #expect(limited.isError)
        #expect(limited.errorText.contains("30 notas por minuto"))

        for i in 30..<200 {
            if i % 30 == 0 { clock.advance(61) }
            #expect(!(try await h.call("create_note", ["text": .string("n\(i)")])).isError)
        }
        clock.advance(61)
        let capped = try await h.call("create_note", ["text": "extra"])
        #expect(capped.isError)
        #expect(capped.errorText.contains("200"))
    }

    @Test func disabledSettingIsRespected() async throws {
        let h = try Harness()
        try await h.repository.update { $0.settings.allowAgentNotes = false }
        let result = try await h.call("create_note", ["text": "x"])
        #expect(result.isError)
        #expect(await h.repository.load().notes.isEmpty)
    }

    @Test func listProjectsAndNotes() async throws {
        let h = try Harness()
        try await h.repository.update { store in
            let p = try store.addProject(name: "Casa", color: RGBA(hex: "#FF0000") ?? .vanilla)
            for i in 0..<60 {
                try store.addNote(text: "n\(i)", projectID: i.isMultiple(of: 2) ? p.id : nil,
                                  now: Date(timeIntervalSince1970: Double(i)))
            }
        }
        let projects = try await h.call("list_projects").structured["projects"]?.arrayValue ?? []
        #expect(projects == [["name": "Casa", "color": "#FF0000"]])

        let defaultList = try await h.call("list_notes").structured["notes"]?.arrayValue ?? []
        #expect(defaultList.count == 20)
        #expect(defaultList.first?["text"] == "n59")

        let filtered = try await h.call("list_notes", ["project": "casa", "limit": 50]).structured["notes"]?.arrayValue ?? []
        #expect(filtered.count == 30)
        #expect(filtered.allSatisfy { $0["project"] == "Casa" })

        #expect(try await h.call("list_notes", ["limit": 51]).isError)
        #expect(try await h.call("list_notes", ["limit": 0]).isError)
        #expect(try await h.call("list_notes", ["limit": "5"]).isError)
        #expect(try await h.call("list_notes", ["project": "nope"]).isError)
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

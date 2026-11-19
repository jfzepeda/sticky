import Foundation
import Testing
@testable import StickyCore

@Suite("AgentOperations")
struct AgentOperationsTests {
    @Test func validatesLengthAndRejectsEmpty() {
        var store = NotesStore()
        #expect(throws: AgentError.emptyText) {
            try AgentOperations.createNote(AgentNoteRequest(text: "  \u{0007} "), in: &store)
        }
        #expect(throws: AgentError.textTooLong(max: 500)) {
            try AgentOperations.createNote(AgentNoteRequest(text: String(repeating: "x", count: 501)), in: &store)
        }
        let ok = try? AgentOperations.createNote(AgentNoteRequest(text: String(repeating: "x", count: 500)), in: &store)
        #expect(ok != nil)
        #expect(ok?.note.createdBy == "agent")
    }

    @Test func resolvesProjectCaseInsensitively() throws {
        var store = NotesStore()
        try store.addProject(name: "Trabajo", color: .vanilla)
        let result = try AgentOperations.createNote(AgentNoteRequest(text: "x", project: "tRABAJO"), in: &store)
        #expect(result.projectName == "Trabajo")
        #expect(store.projects.count == 1)
    }

    @Test func missingProjectErrorListsValidProjects() throws {
        var store = NotesStore()
        try store.addProject(name: "Trabajo", color: .vanilla)
        try store.addProject(name: "Casa", color: .vanilla)
        #expect(throws: AgentError.projectNotFound(name: "Viajes", available: ["Casa", "Trabajo"])) {
            try AgentOperations.createNote(AgentNoteRequest(text: "x", project: "Viajes"), in: &store)
        }
        #expect(store.notes.isEmpty)
    }

    @Test func createProjectIfMissingUsesPaletteColor() throws {
        var store = NotesStore()
        let result = try AgentOperations.createNote(
            AgentNoteRequest(text: "x", project: "Viajes", createProjectIfMissing: true), in: &store)
        #expect(result.projectName == "Viajes")
        #expect(store.projects.count == 1)
        #expect(store.projects[0].color == Palette.color(forProjectIndex: 0))
    }

    @Test func idempotencyKeyDoesNotDuplicate() throws {
        var store = NotesStore()
        let a = try AgentOperations.createNote(AgentNoteRequest(text: "x", idempotencyKey: "k-1"), in: &store)
        let b = try AgentOperations.createNote(AgentNoteRequest(text: "otro", idempotencyKey: "k-1"), in: &store)
        #expect(a.note.id == b.note.id)
        #expect(b.reused)
        #expect(store.notes.count == 1)
        #expect(store.notes[0].text == "x")
    }

    @Test func deleteRejectsNonAgentNotes() throws {
        var store = NotesStore()
        let user = try store.addNote(text: "Usuario", projectID: nil)
        ReminderMerger.merge([reminder("r", "Importada")], into: &store, removeOrphans: false)
        let imported = try #require(store.notes.first { $0.sourceID == "r" })
        let agent = try AgentOperations.createNote(AgentNoteRequest(text: "Agente"), in: &store).note

        #expect(throws: AgentError.permissionDenied) { try AgentOperations.deleteNote(id: user.id, in: &store) }
        #expect(throws: AgentError.permissionDenied) { try AgentOperations.deleteNote(id: imported.id, in: &store) }
        #expect(throws: AgentError.noteNotFound) { try AgentOperations.deleteNote(id: UUID(), in: &store) }
        try AgentOperations.deleteNote(id: agent.id, in: &store)
        #expect(store.notes.count == 2)
    }

    @Test func rateLimitThirtyPerMinute() throws {
        var store = NotesStore()
        let now = Date()
        for i in 0..<30 {
            _ = try AgentOperations.createNote(AgentNoteRequest(text: "n\(i)"), in: &store, now: now)
        }
        #expect(throws: AgentError.rateLimited(perMinute: 30)) {
            try AgentOperations.createNote(AgentNoteRequest(text: "extra"), in: &store, now: now)
        }
        // Deleting notes does not reset the window.
        store.deleteAllAgentNotes()
        #expect(throws: AgentError.rateLimited(perMinute: 30)) {
            try AgentOperations.createNote(AgentNoteRequest(text: "extra"), in: &store, now: now)
        }
        // After the window passes it works again.
        _ = try AgentOperations.createNote(AgentNoteRequest(text: "later"), in: &store, now: now.addingTimeInterval(61))
    }

    @Test func totalQuotaOfTwoHundred() throws {
        var store = NotesStore()
        var now = Date()
        for i in 0..<200 {
            if i % 30 == 0 { now = now.addingTimeInterval(61) }
            _ = try AgentOperations.createNote(AgentNoteRequest(text: "n\(i)"), in: &store, now: now)
        }
        now = now.addingTimeInterval(61)
        #expect(throws: AgentError.quotaExceeded(max: 200)) {
            try AgentOperations.createNote(AgentNoteRequest(text: "extra"), in: &store, now: now)
        }
        // User notes don't count toward the agent quota.
        try store.addNote(text: "user", projectID: nil)
        #expect(store.notes.count == 201)
    }

    @Test func disabledSettingBlocksCreation() {
        var store = NotesStore(settings: StoreSettings(allowAgentNotes: false))
        #expect(throws: AgentError.agentNotesDisabled) {
            try AgentOperations.createNote(AgentNoteRequest(text: "x"), in: &store)
        }
    }
}

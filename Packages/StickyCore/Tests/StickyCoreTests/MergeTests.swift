import Foundation
import Testing
@testable import StickyCore

@Suite("ReminderMerger")
struct MergeTests {
    @Test func createsProjectOnlyOnce() {
        var store = NotesStore()
        let batch = [reminder("a", "Uno"), reminder("b", "Dos")]
        let first = ReminderMerger.merge(batch, into: &store, removeOrphans: false)
        let second = ReminderMerger.merge(batch, into: &store, removeOrphans: false)

        #expect(first.projectsCreated == 1)
        #expect(second.projectsCreated == 0)
        #expect(store.projects.count == 1)
        #expect(store.projects[0].sourceID == "L1")
        #expect(store.projects[0].name == "Trabajo")
        #expect(store.projects[0].color == RGBA(r: 1, g: 0, b: 0))
    }

    @Test func doesNotOverwriteEditedProjectNameOrColor() throws {
        var store = NotesStore()
        ReminderMerger.merge([reminder("a", "Uno")], into: &store, removeOrphans: false)
        let id = store.projects[0].id
        try store.updateProject(id: id, name: "Mi trabajo", color: .vanilla)

        ReminderMerger.merge([reminder("a", "Uno", listName: "Otro nombre", color: .black)],
                             into: &store, removeOrphans: false)

        #expect(store.projects.count == 1)
        #expect(store.projects[0].name == "Mi trabajo")
        #expect(store.projects[0].color == .vanilla)
    }

    @Test func doesNotDuplicateNotes() {
        var store = NotesStore()
        ReminderMerger.merge([reminder("a", "Uno")], into: &store, removeOrphans: false)
        ReminderMerger.merge([reminder("a", "Uno"), reminder("a", "Uno")], into: &store, removeOrphans: false)
        #expect(store.notes.count == 1)
    }

    @Test func updatesTextAndProject() {
        var store = NotesStore()
        ReminderMerger.merge([reminder("a", "Viejo")], into: &store, removeOrphans: false)
        let tilt = store.notes[0].tilt
        let summary = ReminderMerger.merge([reminder("a", "Nuevo", list: "L2", listName: "Casa")],
                                           into: &store, removeOrphans: false)

        #expect(summary.notesUpdated == 1)
        #expect(store.notes.count == 1)
        #expect(store.notes[0].text == "Nuevo")
        #expect(store.project(for: store.notes[0])?.sourceID == "L2")
        #expect(store.notes[0].tilt == tilt, "Tilt must be stable across re-imports")
    }

    @Test func removesOrphansButNeverManualNotes() throws {
        var store = NotesStore()
        try store.addNote(text: "Manual", projectID: nil)
        ReminderMerger.merge([reminder("a", "Uno"), reminder("b", "Dos")], into: &store, removeOrphans: false)

        let summary = ReminderMerger.merge([reminder("a", "Uno")], into: &store, removeOrphans: true)

        #expect(summary.notesRemoved == 1)
        #expect(store.notes.map(\.text).sorted() == ["Manual", "Uno"])
        #expect(store.notes.contains { $0.sourceID == nil })
    }

    @Test func keepsOrphansWhenOptionDisabled() {
        var store = NotesStore()
        ReminderMerger.merge([reminder("a", "Uno"), reminder("b", "Dos")], into: &store, removeOrphans: false)
        ReminderMerger.merge([reminder("a", "Uno")], into: &store, removeOrphans: false)
        #expect(store.notes.count == 2)
    }

    @Test func emptyImportWithCleanupKeepsManualNotes() throws {
        var store = NotesStore()
        try store.addNote(text: "Manual", projectID: nil)
        ReminderMerger.merge([reminder("a", "Uno")], into: &store, removeOrphans: false)
        ReminderMerger.merge([], into: &store, removeOrphans: true)
        #expect(store.notes.map(\.text) == ["Manual"])
    }

    @Test func sanitizesImportedText() {
        var store = NotesStore()
        ReminderMerger.merge([reminder("a", "  Hola\u{202E}mundo\u{0007}  ")], into: &store, removeOrphans: false)
        #expect(store.notes[0].text == "Holamundo")
    }
}

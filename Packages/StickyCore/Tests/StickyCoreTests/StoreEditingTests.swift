import CoreGraphics
import Foundation
import Testing
@testable import StickyCore

@Suite("Store editing")
struct StoreEditingTests {
    @Test func deletingProjectKeepsItsNotesWithoutProject() throws {
        var store = NotesStore()
        let project = try store.addProject(name: "Casa", color: .vanilla)
        let other = try store.addProject(name: "Trabajo", color: .black)
        try store.addNote(text: "A", projectID: project.id)
        try store.addNote(text: "B", projectID: project.id)
        try store.addNote(text: "C", projectID: other.id)

        store.deleteProject(id: project.id)

        #expect(store.notes.count == 3)
        #expect(store.notes.filter { $0.projectID == nil }.map(\.text).sorted() == ["A", "B"])
        #expect(store.notes.first { $0.text == "C" }?.projectID == other.id)
        #expect(store.projects.map(\.name) == ["Trabajo"])
    }

    @Test func rejectsEmptyAndOverlongNotes() {
        var store = NotesStore()
        #expect(throws: NotesStore.EditError.emptyText) { try store.addNote(text: " \n\t ", projectID: nil) }
        #expect(throws: NotesStore.EditError.textTooLong(max: 500)) {
            try store.addNote(text: String(repeating: "a", count: 501), projectID: nil)
        }
        #expect(throws: NotesStore.EditError.unknownProject) { try store.addNote(text: "x", projectID: UUID()) }
    }

    @Test func deleteAllAgentNotesKeepsOthers() throws {
        var store = NotesStore()
        try store.addNote(text: "Usuario", projectID: nil)
        _ = try AgentOperations.createNote(AgentNoteRequest(text: "Agente"), in: &store)
        #expect(store.deleteAllAgentNotes() == 1)
        #expect(store.notes.map(\.text) == ["Usuario"])
    }
}

@Suite("Support")
struct SupportTests {
    @Test func deepLinkRoundTrip() {
        let id = UUID()
        let url = DeepLink.noteURL(for: id)
        #expect(url.absoluteString == "stickydesk://note/\(id.uuidString)")
        #expect(DeepLink.noteID(from: url) == id)
    }

    @Test(arguments: [
        "https://note/6F9619FF-8B86-D011-B42D-00CF4FC964FF",
        "stickydesk://other/6F9619FF-8B86-D011-B42D-00CF4FC964FF",
        "stickydesk://note/not-a-uuid",
        "stickydesk://note/6F9619FF-8B86-D011-B42D-00CF4FC964FF/extra",
        "stickydesk://note/6F9619FF-8B86-D011-B42D-00CF4FC964FF?x=1",
    ])
    func deepLinkRejectsMalformed(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(DeepLink.noteID(from: url) == nil)
    }

    @Test func rgbaHelpers() throws {
        #expect(RGBA.vanilla.hexString == "#F3E5AB")
        #expect(RGBA(hex: "#F3E5AB") == RGBA.vanilla)
        let mixed = RGBA.black.postItRGBA
        #expect(abs(mixed.r - 0.55) < 0.0001)
        let fromCG = try #require(RGBA(cgColor: CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)))
        #expect(abs(fromCG.g - 0.5) < 0.001)
        #expect(RGBA(r: 2, g: -1, b: .nan).r == 1)
    }

    @Test func sanitizerStripsControlAndBidiButKeepsNewlinesAndEmoji() {
        let input = "  hola\u{0000}\u{202E}\r\nmundo 👩‍💻\u{200B}  "
        #expect(TextSanitizer.sanitize(input, allowNewlines: true) == "hola\nmundo 👩‍💻")
        #expect(TextSanitizer.sanitize("a\nb", allowNewlines: false) == "a b")
    }

    @Test func paletteIsDeterministic() {
        #expect(Palette.color(forProjectIndex: 0) == Palette.color(forProjectIndex: Palette.colors.count))
    }
}

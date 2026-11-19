import Foundation
import Testing
@testable import StickyCore

@Suite("Persistence")
struct PersistenceTests {
    @Test func jsonRoundTrip() throws {
        let project = Project(name: "Casa", color: RGBA(r: 0.2, g: 0.4, b: 0.6), sourceID: "L1")
        let note = Note(text: "Hola\nmundo", tilt: 2.5, projectID: project.id, sourceID: "r1",
                        createdBy: "agent", idempotencyKey: "k1",
                        createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let store = NotesStore(notes: [note], projects: [project],
                               settings: StoreSettings(allowAgentNotes: false))

        let decoded = try StoreCodec.decode(try StoreCodec.encode(store))
        #expect(decoded == store)
    }

    @Test func repositoryRoundTripPreservesTilt() async throws {
        let dir = try TempDir()
        let repo = NotesRepository(fileURL: dir.storeURL)
        let note = Note(text: "Inclinada", tilt: -3.25)
        try await repo.save(NotesStore(notes: [note]))

        let reloaded = await NotesRepository(fileURL: dir.storeURL).load()
        #expect(reloaded.notes.count == 1)
        #expect(reloaded.notes[0].tilt == -3.25)
        #expect(reloaded.notes[0].id == note.id)
    }

    @Test func tiltIsGeneratedInRangeAndClampedOnDecode() throws {
        for _ in 0..<200 {
            #expect(Note.tiltRange.contains(Note(text: "x").tilt))
        }
        let json = #"{"notes":[{"id":"\#(UUID().uuidString)","text":"x","tilt":99}]}"#
        let store = try StoreCodec.decode(Data(json.utf8))
        #expect(store.notes[0].tilt == 4)
    }

    @Test func missingFileYieldsEmptyStore() async throws {
        let dir = try TempDir()
        let store = await NotesRepository(fileURL: dir.storeURL).load()
        #expect(store == .empty)
        if case .missing = StoreCodec.load(from: dir.storeURL) {} else {
            Issue.record("Expected .missing")
        }
    }

    @Test func corruptFileYieldsEmptyStoreWithoutCrashing() async throws {
        let dir = try TempDir()
        try FileManager.default.createDirectory(at: dir.storeURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("{ not json ]".utf8).write(to: dir.storeURL)

        let repo = NotesRepository(fileURL: dir.storeURL)
        #expect(await repo.load() == .empty)
        if case .corrupt = StoreCodec.load(from: dir.storeURL) {} else {
            Issue.record("Expected .corrupt")
        }
    }

    @Test func corruptFileIsBackedUpBeforeBeingOverwritten() async throws {
        let dir = try TempDir()
        let folder = dir.storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: dir.storeURL)

        let repo = NotesRepository(fileURL: dir.storeURL)
        try await repo.update { store in try store.addNote(text: "Nueva", projectID: nil) }

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.contains { $0.contains("corrupt-") })
        #expect(await repo.load().notes.map(\.text) == ["Nueva"])
    }

    @Test func decodesLegacyJSONWithoutNewFields() throws {
        // A file written before createdBy / idempotencyKey / createdAt / settings existed.
        let id = UUID().uuidString
        let pid = UUID().uuidString
        let legacy = """
        {
          "notes": [{ "id": "\(id)", "text": "Vieja", "tilt": 1.5, "projectID": "\(pid)" }],
          "projects": [{ "id": "\(pid)", "name": "P", "color": { "r": 1, "g": 1, "b": 0, "a": 1 } }]
        }
        """
        let store = try StoreCodec.decode(Data(legacy.utf8))
        #expect(store.notes.count == 1)
        #expect(store.notes[0].createdBy == nil)
        #expect(store.notes[0].idempotencyKey == nil)
        #expect(store.notes[0].isAgentNote == false)
        #expect(store.settings.allowAgentNotes == true)
        #expect(store.agentCreationLog.isEmpty)
        #expect(store.project(for: store.notes[0])?.name == "P")
    }

    @Test func failingUpdateDoesNotWrite() async throws {
        let dir = try TempDir()
        let repo = NotesRepository(fileURL: dir.storeURL)
        try await repo.update { store in try store.addNote(text: "A", projectID: nil) }
        await #expect(throws: NotesStore.EditError.self) {
            try await repo.update { store in
                try store.addNote(text: "B", projectID: nil)
                try store.addNote(text: "   ", projectID: nil)
            }
        }
        #expect(await repo.load().notes.map(\.text) == ["A"])
    }

    @Test func didSaveIsCalledAfterEachSave() async throws {
        let dir = try TempDir()
        let counter = Counter()
        let repo = NotesRepository(fileURL: dir.storeURL) { counter.increment() }
        try await repo.update { store in try store.addNote(text: "A", projectID: nil) }
        try await repo.update { store in try store.addNote(text: "B", projectID: nil) }
        #expect(counter.value == 2)
        // A no-op update does not rewrite the file or trigger a reload.
        try await repo.update { _ in }
        #expect(counter.value == 2)
    }

    @Test func concurrentWritersDoNotLoseData() async throws {
        let dir = try TempDir()
        // Two independent repositories = two independent flock file descriptions,
        // the same situation as the app and the MCP helper writing concurrently.
        let app = NotesRepository(fileURL: dir.storeURL)
        let mcp = NotesRepository(fileURL: dir.storeURL)
        let perWriter = 60

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<perWriter {
                    try await app.update { store in try store.addNote(text: "app \(i)", projectID: nil) }
                }
            }
            group.addTask {
                for i in 0..<perWriter {
                    try await mcp.update { store in
                        _ = try AgentOperations.createNote(
                            AgentNoteRequest(text: "mcp \(i)"), in: &store,
                            now: Date().addingTimeInterval(Double(i) * 10)) // stay under the rate limit
                    }
                }
            }
            try await group.waitForAll()
        }

        let final = await app.load()
        #expect(final.notes.count == perWriter * 2)
        #expect(final.notes.filter(\.isAgentNote).count == perWriter)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}

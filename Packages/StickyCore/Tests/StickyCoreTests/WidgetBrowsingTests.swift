import Foundation
import Testing
@testable import StickyCore

@Suite("Widget grouping and browsing")
struct WidgetBrowsingTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func note(_ text: String, _ seconds: Double, _ project: Project? = nil) -> Note {
        Note(text: text, tilt: 0, projectID: project?.id, createdAt: base.addingTimeInterval(seconds))
    }

    private func sampleStore() -> (NotesStore, Project, Project) {
        let work = Project(name: "Trabajo", color: .vanilla)
        let home = Project(name: "Casa", color: .black)
        let notes = [
            note("w1", 1, work),
            note("loose1", 2),
            note("h1", 3, home),
            note("w2", 4, work),
            note("w3", 5, work),
            Note(text: "orphan", tilt: 0, projectID: UUID(), createdAt: base), // dangling project
        ]
        return (NotesStore(notes: notes, projects: [work, home]), work, home)
    }

    @Test func groupsByProjectOrderedByNewestNote() {
        let (store, work, home) = sampleStore()
        let groups = store.noteGroups

        #expect(groups.map(\.id) == [work.id.uuidString, home.id.uuidString, NoteGroup.unassignedID])
        #expect(groups[0].notes.map(\.text) == ["w3", "w2", "w1"])
        #expect(groups[0].project == work)
        #expect(groups[1].notes.map(\.text) == ["h1"])
        // Notes whose project is gone join the unassigned stack.
        #expect(groups[2].project == nil)
        #expect(groups[2].notes.map(\.text) == ["loose1", "orphan"])
    }

    @Test func pagingClampsAndReportsNeighbours() {
        let items = Array(1...5)
        let first = Paged(items, page: -3, pageSize: 2)
        #expect(first.items == [1, 2] && first.page == 0 && first.pageCount == 3)
        #expect(!first.hasPrevious && first.hasNext)

        let last = Paged(items, page: 99, pageSize: 2)
        #expect(last.items == [5] && last.page == 2 && !last.hasNext)

        let empty = Paged([Int](), page: 0, pageSize: 4)
        #expect(empty.items.isEmpty && empty.pageCount == 1)
    }

    @Test func presentationFollowsBrowseState() {
        let (store, work, _) = sampleStore()
        var state = WidgetBrowseState()

        guard case .overview(let overview) = WidgetPresentation(store: store, state: state["small"], slotCount: 1)
        else { Issue.record("expected overview"); return }
        #expect(overview.items.count == 1 && overview.pageCount == 3)

        // Large shows all three stacks, leaving one dashed slot.
        if case .overview(let large) = WidgetPresentation(store: store, state: state["large"], slotCount: 4) {
            #expect(large.items.count == 3)
        } else {
            Issue.record("expected overview")
        }

        state.open(groupID: work.id.uuidString, family: "medium")
        state.setPage(1, family: "medium", inGroup: true)
        guard case .group(let group, let page) = WidgetPresentation(store: store, state: state["medium"], slotCount: 2)
        else { Issue.record("expected group"); return }
        #expect(group.id == work.id.uuidString)
        #expect(page.items.map(\.text) == ["w1"] && page.page == 1)
        // Other sizes are untouched.
        #expect(state["large"].openGroupID == nil)

        state.close(family: "medium")
        #expect(state["medium"] == WidgetBrowseState.Slot())
    }

    @Test func staleSelectionFallsBackToOverviewAndEmptyStoreIsEmpty() {
        let (store, _, _) = sampleStore()
        var state = WidgetBrowseState()
        state.open(groupID: UUID().uuidString, family: "small")

        if case .overview = WidgetPresentation(store: store, state: state["small"], slotCount: 1) {} else {
            Issue.record("stale group should fall back to overview")
        }
        #expect(WidgetPresentation(store: NotesStore(), state: state["small"], slotCount: 1) == .empty)
    }

    @Test func pinnedProjectShowsOnlyItsNotesEvenWhenEmpty() {
        var (store, work, _) = sampleStore()
        let empty = Project(name: "Vacío", color: .vanilla)
        store.projects.append(empty)
        var state = WidgetBrowseState()
        let key = WidgetBrowseState.key(family: "medium", pinnedProjectID: work.id)
        #expect(key != "medium")
        state.setPage(1, family: key, inGroup: true)

        guard case .pinned(let group, let page) = WidgetPresentation(
            store: store, state: state[key], slotCount: 2, pinnedProjectID: work.id
        ) else { Issue.record("expected pinned"); return }
        #expect(group.project == work && page.items.map(\.text) == ["w1"])

        if case .pinned(let g, let p) = WidgetPresentation(
            store: store, state: WidgetBrowseState.Slot(), slotCount: 4, pinnedProjectID: empty.id
        ) {
            #expect(g.notes.isEmpty && p.items.isEmpty)
        } else {
            Issue.record("empty pinned project should still be pinned")
        }

        // Deleted project → all projects.
        if case .overview = WidgetPresentation(
            store: store, state: WidgetBrowseState.Slot(), slotCount: 4, pinnedProjectID: UUID()
        ) {} else {
            Issue.record("missing pinned project should fall back to overview")
        }
    }

    @Test func widgetHidesCompletedNotes() throws {
        var (store, work, home) = sampleStore()
        let w3 = try #require(store.notes.first { $0.text == "w3" })
        let h1 = try #require(store.notes.first { $0.text == "h1" })
        try store.setNoteCompleted(id: w3.id, true)
        try store.setNoteCompleted(id: h1.id, true)

        // "Casa" only had h1, so its stack is gone; Trabajo keeps w2, w1.
        guard case .overview(let overview) = WidgetPresentation(
            store: store, state: WidgetBrowseState.Slot(), slotCount: 4
        ) else { Issue.record("expected overview"); return }
        #expect(!overview.items.contains { $0.id == home.id.uuidString })
        #expect(overview.items.first { $0.id == work.id.uuidString }?.notes.map(\.text) == ["w2", "w1"])

        // An open stack whose notes are all done falls back to the overview.
        var state = WidgetBrowseState()
        state.open(groupID: home.id.uuidString, family: "large")
        if case .overview = WidgetPresentation(store: store, state: state["large"], slotCount: 4) {} else {
            Issue.record("fully completed stack should close")
        }

        // Pinned project with only completed notes shows empty (dashed) slots.
        if case .pinned(_, let page) = WidgetPresentation(
            store: store, state: WidgetBrowseState.Slot(), slotCount: 2, pinnedProjectID: home.id
        ) {
            #expect(page.items.isEmpty)
        } else {
            Issue.record("expected pinned")
        }

        // Everything done → empty state.
        for note in store.notes { try store.setNoteCompleted(id: note.id, true) }
        #expect(WidgetPresentation(store: store, state: WidgetBrowseState.Slot(), slotCount: 1) == .empty)
    }

    @Test func noteFilterSplitsPendingAndCompleted() throws {
        var (store, _, _) = sampleStore()
        let w2 = try #require(store.notes.first { $0.text == "w2" })
        try store.setNoteCompleted(id: w2.id, true)

        #expect(store.notes(matching: .completed).map(\.text) == ["w2"])
        #expect(!store.notes(matching: .pending).contains { $0.text == "w2" })
        #expect(store.notes(matching: .all).count == store.notes.count)
        #expect(store.notes(matching: .all).first?.text == "w3") // newest first
        #expect(store.filtered(.pending).projects == store.projects)

        let before = store.notes.count
        #expect(store.deleteCompletedNotes() == 1)
        #expect(store.notes.count == before - 1 && store.notes(matching: .completed).isEmpty)
        #expect(store.deleteCompletedNotes() == 0)
    }

    @Test func browseStateRoundTripsAndToleratesGarbage() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("StickyDesk/\(WidgetBrowseStore.fileName)")

        #expect(WidgetBrowseStore.load(from: url) == WidgetBrowseState())

        try WidgetBrowseStore.update(at: url) { $0.open(groupID: "abc", family: "large") }
        #expect(WidgetBrowseStore.load(from: url)["large"].openGroupID == "abc")

        try Data("{not json".utf8).write(to: url)
        #expect(WidgetBrowseStore.load(from: url) == WidgetBrowseState())

        try Data(#"{"slots":{"small":{"page":-4}}}"#.utf8).write(to: url)
        #expect(WidgetBrowseStore.load(from: url)["small"].page == 0)
    }
}

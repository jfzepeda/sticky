import Foundation
import StickyCore
import WidgetKit

struct StickyEntry: TimelineEntry {
    let date: Date
    let store: NotesStore

    /// Notes to display for a family, newest first.
    func notes(limit: Int) -> [Note] {
        Array(store.notesNewestFirst.prefix(limit))
    }
}

/// Reads the shared store from the App Group. The widget never writes and never uses EventKit.
struct StickyProvider: TimelineProvider {
    static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> StickyEntry {
        StickyEntry(date: Date(), store: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (StickyEntry) -> Void) {
        let store = loadStore()
        // In the widget gallery show something representative even with no notes yet.
        let shown = (context.isPreview && store.notes.isEmpty) ? NotesStore.sample : store
        completion(StickyEntry(date: Date(), store: shown))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StickyEntry>) -> Void) {
        let now = Date()
        let entry = StickyEntry(date: now, store: loadStore())
        // Immediate refreshes come from the app calling reloadAllTimelines(); this is the fallback.
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(Self.refreshInterval))))
    }

    private func loadStore() -> NotesStore {
        guard let url = try? AppGroup.storeURL() else { return .empty }
        return StoreCodec.loadStore(from: url)
    }
}

extension NotesStore {
    /// Fixed sample data for placeholders and the widget gallery.
    static let sample: NotesStore = {
        let work = Project(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            name: "Trabajo",
            color: RGBA(hex: "#5AC8FA") ?? .vanilla
        )
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let notes = [
            Note(text: "Llamar a Ana a las 5", tilt: -2.2, createdAt: base.addingTimeInterval(6)),
            Note(text: "Revisar el PR de login", tilt: 1.8, projectID: work.id, createdAt: base.addingTimeInterval(5)),
            Note(text: "Comprar café ☕️", tilt: -0.8, createdAt: base.addingTimeInterval(4)),
            Note(text: "Preparar demo del viernes", tilt: 2.6, projectID: work.id, createdAt: base.addingTimeInterval(3)),
            Note(text: "Regar las plantas", tilt: -3.1, createdAt: base.addingTimeInterval(2)),
            Note(text: "Leer capítulo 4", tilt: 0.9, createdAt: base.addingTimeInterval(1)),
        ]
        return NotesStore(notes: notes, projects: [work])
    }()
}

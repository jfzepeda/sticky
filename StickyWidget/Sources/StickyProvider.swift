import Foundation
import StickyCore
import WidgetKit

struct StickyEntry: TimelineEntry {
    let date: Date
    let store: NotesStore
    var browse = WidgetBrowseState()
    /// From the widget's configuration; `nil` = all projects.
    var pinnedProjectID: UUID?
}

/// Reads the shared store from the App Group. The widget never writes the notes store and
/// never uses EventKit; its intents only write the browse-state file.
struct StickyProvider: AppIntentTimelineProvider {
    static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> StickyEntry {
        StickyEntry(date: Date(), store: .sample)
    }

    func snapshot(for configuration: StickyConfigurationIntent, in context: Context) async -> StickyEntry {
        let store = loadStore()
        // In the widget gallery show something representative even with no notes yet.
        if context.isPreview && store.notes.isEmpty {
            return StickyEntry(date: Date(), store: .sample)
        }
        return entry(for: configuration, store: store, date: Date())
    }

    func timeline(for configuration: StickyConfigurationIntent, in context: Context) async -> Timeline<StickyEntry> {
        let now = Date()
        let entry = entry(for: configuration, store: loadStore(), date: now)
        // Immediate refreshes come from the app calling reloadAllTimelines(); this is the fallback.
        return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(Self.refreshInterval)))
    }

    private func entry(for configuration: StickyConfigurationIntent, store: NotesStore, date: Date) -> StickyEntry {
        StickyEntry(date: date, store: store, browse: loadBrowseState(), pinnedProjectID: configuration.pinnedProjectID)
    }

    private func loadStore() -> NotesStore {
        guard let url = try? AppGroup.storeURL() else { return .empty }
        return StoreCodec.loadStore(from: url)
    }

    private func loadBrowseState() -> WidgetBrowseState {
        guard let url = try? WidgetBrowseStore.url() else { return WidgetBrowseState() }
        return WidgetBrowseStore.load(from: url)
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
        let home = Project(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID(),
            name: "Casa",
            color: RGBA(hex: "#34C759") ?? .vanilla
        )
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let notes = [
            Note(text: "Llamar a Ana a las 5", tilt: -2.2, createdAt: base.addingTimeInterval(6)),
            Note(text: "Revisar el PR de login", tilt: 1.8, projectID: work.id, createdAt: base.addingTimeInterval(5)),
            Note(text: "Comprar café ☕️", tilt: -0.8, createdAt: base.addingTimeInterval(4)),
            Note(text: "Preparar demo del viernes", tilt: 2.6, projectID: work.id, createdAt: base.addingTimeInterval(3)),
            Note(text: "Regar las plantas", tilt: -3.1, projectID: home.id, createdAt: base.addingTimeInterval(2)),
            Note(text: "Leer capítulo 4", tilt: 0.9, createdAt: base.addingTimeInterval(1)),
        ]
        return NotesStore(notes: notes, projects: [work, home])
    }()
}

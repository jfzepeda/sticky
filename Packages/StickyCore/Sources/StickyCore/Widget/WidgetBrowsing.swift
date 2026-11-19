import Foundation

/// What the user has "opened" in the widget, per widget size. This is UI state, not data:
/// it lives in its own small file next to the notes store, and it is the only thing the
/// widget extension ever writes. All instances of the same size share it (WidgetKit gives
/// a static widget no per-instance identity).
public struct WidgetBrowseState: Codable, Equatable, Sendable {
    public struct Slot: Codable, Equatable, Sendable {
        /// `NoteGroup.id` of the open stack, or `nil` for the overview.
        public var openGroupID: String?
        /// Page inside the open group.
        public var page: Int
        /// Page of the overview (when there are more groups than slots).
        public var overviewPage: Int

        public init(openGroupID: String? = nil, page: Int = 0, overviewPage: Int = 0) {
            self.openGroupID = openGroupID
            self.page = page
            self.overviewPage = overviewPage
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            openGroupID = try c.decodeIfPresent(String.self, forKey: .openGroupID)
            page = max(0, try c.decodeIfPresent(Int.self, forKey: .page) ?? 0)
            overviewPage = max(0, try c.decodeIfPresent(Int.self, forKey: .overviewPage) ?? 0)
        }

        private enum CodingKeys: String, CodingKey { case openGroupID, page, overviewPage }
    }

    public var slots: [String: Slot]

    public init(slots: [String: Slot] = [:]) {
        self.slots = slots
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slots = try c.decodeIfPresent([String: Slot].self, forKey: .slots) ?? [:]
    }

    private enum CodingKeys: String, CodingKey { case slots }

    public subscript(family: String) -> Slot {
        get { slots[family] ?? Slot() }
        set { slots[family] = newValue }
    }

    // MARK: Transitions (pure)

    public mutating func open(groupID: String, family: String) {
        self[family].openGroupID = groupID
        self[family].page = 0
    }

    public mutating func close(family: String) {
        self[family].openGroupID = nil
        self[family].page = 0
    }

    /// Shows `page` of a group (`inGroup`, also used by pinned widgets) or of the overview.
    /// Callers pass the neighbour of the page they rendered; presenting clamps it.
    public mutating func setPage(_ page: Int, family: String, inGroup: Bool) {
        if inGroup {
            self[family].page = max(0, page)
        } else {
            self[family].overviewPage = max(0, page)
        }
    }

    /// Key into `slots`: one per widget size, plus one per size and pinned project, so a
    /// widget configured for a project keeps its own page.
    public static func key(family: String, pinnedProjectID: UUID?) -> String {
        guard let pinnedProjectID else { return family }
        return family + ":" + pinnedProjectID.uuidString
    }
}

/// What a widget of `slotCount` slots should draw for a store and browse state.
public enum WidgetPresentation: Equatable, Sendable {
    /// No notes at all.
    case empty
    /// One stack per project; `slotCount - groups.items.count` dashed placeholders.
    case overview(Paged<NoteGroup>)
    /// The notes of one opened stack.
    case group(NoteGroup, Paged<Note>)
    /// The widget is configured for a single project; the group may have no notes.
    case pinned(NoteGroup, Paged<Note>)

    /// `pinnedProjectID` comes from the widget's configuration (`nil` = all projects). A
    /// pinned project that no longer exists falls back to showing all projects.
    public init(store: NotesStore, state: WidgetBrowseState.Slot, slotCount: Int, pinnedProjectID: UUID? = nil) {
        if let pinnedProjectID, let project = store.project(id: pinnedProjectID) {
            let notes = store.notes.filter { $0.projectID == project.id }.sorted(by: NotesStore.newestFirst)
            let group = NoteGroup(id: project.id.uuidString, project: project, notes: notes)
            self = .pinned(group, Paged(notes, page: state.page, pageSize: slotCount))
            return
        }
        let groups = store.noteGroups
        guard !groups.isEmpty else {
            self = .empty
            return
        }
        // A stale selection (project deleted, notes gone) falls back to the overview.
        if let id = state.openGroupID, let group = groups.first(where: { $0.id == id }) {
            self = .group(group, Paged(group.notes, page: state.page, pageSize: slotCount))
        } else {
            self = .overview(Paged(groups, page: state.overviewPage, pageSize: slotCount))
        }
    }
}

/// Synchronous load/save of `WidgetBrowseState`. Never throws on load.
public enum WidgetBrowseStore {
    public static let fileName = "widget-state.json"
    public static let maxFileSize = 64 * 1024

    public static func url(appGroupID: String? = AppGroup.identifier) throws -> URL {
        try AppGroup.storeURL(appGroupID: appGroupID)
            .deletingLastPathComponent()
            .appendingPathComponent(fileName, isDirectory: false)
    }

    public static func load(from url: URL) -> WidgetBrowseState {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber, size.intValue <= maxFileSize,
            let data = try? Data(contentsOf: url),
            let state = try? JSONDecoder().decode(WidgetBrowseState.self, from: data)
        else { return WidgetBrowseState() }
        return state
    }

    public static func save(_ state: WidgetBrowseState, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Read-modify-write. Last writer wins; this is throwaway UI state, so no lock.
    public static func update(at url: URL, _ body: (inout WidgetBrowseState) -> Void) throws {
        var state = load(from: url)
        body(&state)
        try save(state, to: url)
    }
}

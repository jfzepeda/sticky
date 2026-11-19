import Foundation

/// The notes of one project (or of no project), as the widget shows them: a stack.
public struct NoteGroup: Identifiable, Equatable, Sendable {
    /// Stable key: the project's UUID string, or `NoteGroup.unassignedID`.
    public let id: String
    public let project: Project?
    /// Newest first. Never empty in `noteGroups`; may be empty for a pinned project.
    public let notes: [Note]

    public static let unassignedID = "none"

    public var newest: Note? { notes.first }
}

extension NotesStore {
    /// Notes grouped by project, newest first inside each group, groups ordered by their
    /// newest note. Notes without a project — or whose project no longer exists — share
    /// one "unassigned" group. Ties are broken by id so the order is deterministic.
    public var noteGroups: [NoteGroup] {
        let sorted = notes.sorted(by: Self.newestFirst)
        var order: [String] = []
        var buckets: [String: [Note]] = [:]
        var projectsByKey: [String: Project] = [:]

        for note in sorted {
            let project = project(for: note)
            let key = project?.id.uuidString ?? NoteGroup.unassignedID
            if buckets[key] == nil {
                order.append(key)
                if let project { projectsByKey[key] = project }
            }
            buckets[key, default: []].append(note)
        }

        return order.compactMap { key in
            guard let notes = buckets[key], !notes.isEmpty else { return nil }
            return NoteGroup(id: key, project: projectsByKey[key], notes: notes)
        }
    }

    static func newestFirst(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// A page of items plus where it sits. `page` is always clamped into range.
public struct Paged<Item: Sendable>: Sendable {
    public let items: [Item]
    public let page: Int
    public let pageCount: Int

    public init(_ all: [Item], page requested: Int, pageSize: Int) {
        let size = max(1, pageSize)
        let count = max(1, (all.count + size - 1) / size)
        let page = min(max(0, requested), count - 1)
        let start = page * size
        self.items = Array(all[min(start, all.count)..<min(start + size, all.count)])
        self.page = page
        self.pageCount = count
    }

    public var hasPrevious: Bool { page > 0 }
    public var hasNext: Bool { page < pageCount - 1 }
}

extension Paged: Equatable where Item: Equatable {}

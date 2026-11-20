import Foundation

/// Which notes a list shows. The menu bar defaults to `.pending`; the widget always
/// shows pending notes only.
public enum NoteFilter: String, CaseIterable, Identifiable, Sendable {
    case pending
    case all
    case completed

    public var id: Self { self }

    public var title: String {
        switch self {
        case .pending: "Pendientes"
        case .all: "Todas"
        case .completed: "Completadas"
        }
    }

    public func includes(_ note: Note) -> Bool {
        switch self {
        case .pending: !note.isCompleted
        case .all: true
        case .completed: note.isCompleted
        }
    }
}

extension NotesStore {
    /// Notes passing `filter`, newest first (ties broken by id).
    public func notes(matching filter: NoteFilter) -> [Note] {
        notes.filter(filter.includes).sorted(by: Self.newestFirst)
    }

    /// A copy without the notes that `filter` excludes (projects and settings untouched).
    public func filtered(_ filter: NoteFilter) -> NotesStore {
        var copy = self
        copy.notes.removeAll { !filter.includes($0) }
        return copy
    }
}

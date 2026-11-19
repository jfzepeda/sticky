import Foundation

/// A reminder copied out of EventKit into a `Sendable` value (EKReminder is not Sendable).
public struct ImportedReminder: Hashable, Sendable {
    public var id: String
    public var title: String
    public var listID: String
    public var listName: String
    public var listColor: RGBA

    public init(id: String, title: String, listID: String, listName: String, listColor: RGBA) {
        self.id = id
        self.title = title
        self.listID = listID
        self.listName = listName
        self.listColor = listColor
    }
}

/// A Reminders list, as offered in the import picker.
public struct ReminderList: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var color: RGBA

    public init(id: String, name: String, color: RGBA) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public struct MergeSummary: Equatable, Sendable {
    public var projectsCreated = 0
    public var notesCreated = 0
    public var notesUpdated = 0
    public var notesRemoved = 0
    public init() {}
}

/// One-way merge Reminders → store. Pure function: no I/O, fully testable.
public enum ReminderMerger {
    /// - Projects are matched by `sourceID == listID`. Missing ones are created with the list's
    ///   name and color; existing ones keep the user's name and color.
    /// - Notes are upserted by `sourceID` (text and project are refreshed; never duplicated).
    /// - `removeOrphans`: imported notes whose `sourceID` is absent from `reminders` are removed.
    ///   Manual notes (`sourceID == nil`) are never touched.
    @discardableResult
    public static func merge(
        _ reminders: [ImportedReminder],
        into store: inout NotesStore,
        removeOrphans: Bool,
        now: Date = Date()
    ) -> MergeSummary {
        var summary = MergeSummary()

        // Projects: one per list, created once.
        var projectIDByList: [String: UUID] = [:]
        for project in store.projects {
            if let source = project.sourceID { projectIDByList[source] = project.id }
        }
        for reminder in reminders where projectIDByList[reminder.listID] == nil {
            let name = TextSanitizer.sanitize(reminder.listName, allowNewlines: false)
            let project = Project(
                name: name.isEmpty ? "Recordatorios" : String(name.prefix(NotesStore.maxProjectNameLength)),
                color: reminder.listColor,
                sourceID: reminder.listID
            )
            store.projects.append(project)
            projectIDByList[reminder.listID] = project.id
            summary.projectsCreated += 1
        }

        // Notes: upsert by sourceID. Deduplicate the input itself (last one wins).
        var latestByID: [String: ImportedReminder] = [:]
        var order: [String] = []
        for reminder in reminders {
            if latestByID[reminder.id] == nil { order.append(reminder.id) }
            latestByID[reminder.id] = reminder
        }

        var indexBySource: [String: Int] = [:]
        for (index, note) in store.notes.enumerated() {
            if let source = note.sourceID, indexBySource[source] == nil { indexBySource[source] = index }
        }

        for id in order {
            guard let reminder = latestByID[id] else { continue }
            var text = TextSanitizer.sanitize(reminder.title, allowNewlines: true)
            if text.isEmpty { text = "(sin título)" }
            text = String(text.prefix(NotesStore.maxNoteLength))
            let projectID = projectIDByList[reminder.listID]

            if let index = indexBySource[id] {
                if store.notes[index].text != text || store.notes[index].projectID != projectID {
                    store.notes[index].text = text
                    store.notes[index].projectID = projectID
                    summary.notesUpdated += 1
                }
            } else {
                store.notes.append(Note(text: text, projectID: projectID, sourceID: id, createdAt: now))
                indexBySource[id] = store.notes.count - 1
                summary.notesCreated += 1
            }
        }

        if removeOrphans {
            let alive = Set(latestByID.keys)
            let before = store.notes.count
            store.notes.removeAll { note in
                guard let source = note.sourceID else { return false }
                return !alive.contains(source)
            }
            summary.notesRemoved = before - store.notes.count
        }

        // Also collapse pre-existing duplicates by sourceID, keeping the first.
        var seen = Set<String>()
        store.notes.removeAll { note in
            guard let source = note.sourceID else { return false }
            return !seen.insert(source).inserted
        }

        return summary
    }
}

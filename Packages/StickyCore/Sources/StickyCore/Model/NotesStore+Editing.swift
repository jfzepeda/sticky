import Foundation

/// User-driven edits. Pure value mutations so they're easy to test and to run
/// inside `NotesRepository.update` (read-modify-write under the file lock).
extension NotesStore {
    public enum EditError: Error, Equatable, Sendable {
        case emptyText
        case textTooLong(max: Int)
        case emptyProjectName
        case unknownProject
        case unknownNote
    }

    public static let maxNoteLength = 500
    public static let maxProjectNameLength = 60

    @discardableResult
    public mutating func addNote(text: String, projectID: UUID?, now: Date = Date()) throws -> Note {
        let clean = try Self.validatedNoteText(text)
        if let projectID, project(id: projectID) == nil { throw EditError.unknownProject }
        let note = Note(text: clean, projectID: projectID, createdAt: now)
        notes.append(note)
        return note
    }

    public mutating func updateNote(id: UUID, text: String, projectID: UUID?) throws {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { throw EditError.unknownNote }
        let clean = try Self.validatedNoteText(text)
        if let projectID, project(id: projectID) == nil { throw EditError.unknownProject }
        notes[index].text = clean
        notes[index].projectID = projectID
    }

    public mutating func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
    }

    @discardableResult
    public mutating func addProject(name: String, color: RGBA, sourceID: String? = nil) throws -> Project {
        let clean = try Self.validatedProjectName(name)
        let project = Project(name: clean, color: color, sourceID: sourceID)
        projects.append(project)
        return project
    }

    public mutating func updateProject(id: UUID, name: String, color: RGBA) throws {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { throw EditError.unknownProject }
        projects[index].name = try Self.validatedProjectName(name)
        projects[index].color = color
    }

    /// Removes a project. Its notes are kept and become project-less (vanilla).
    public mutating func deleteProject(id: UUID) {
        projects.removeAll { $0.id == id }
        for index in notes.indices where notes[index].projectID == id {
            notes[index].projectID = nil
        }
    }

    /// Removes every note created by an agent. Returns how many were removed.
    @discardableResult
    public mutating func deleteAllAgentNotes() -> Int {
        let before = notes.count
        notes.removeAll { $0.isAgentNote }
        return before - notes.count
    }

    static func validatedNoteText(_ text: String) throws -> String {
        let clean = TextSanitizer.sanitize(text, allowNewlines: true)
        guard !clean.isEmpty else { throw EditError.emptyText }
        guard clean.count <= maxNoteLength else { throw EditError.textTooLong(max: maxNoteLength) }
        return clean
    }

    static func validatedProjectName(_ name: String) throws -> String {
        let clean = TextSanitizer.sanitize(name, allowNewlines: false)
        guard !clean.isEmpty else { throw EditError.emptyProjectName }
        return String(clean.prefix(maxProjectNameLength))
    }
}

extension NotesStore.EditError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyText: "La nota no puede estar vacía."
        case .textTooLong(let max): "La nota supera los \(max) caracteres."
        case .emptyProjectName: "El proyecto necesita un nombre."
        case .unknownProject: "El proyecto ya no existe."
        case .unknownNote: "La nota ya no existe."
        }
    }
}

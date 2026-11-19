import Foundation

/// Limits applied to everything coming from agents (MCP).
public struct AgentLimits: Sendable {
    public var maxTextLength = 500
    public var maxProjectNameLength = 60
    public var maxIdempotencyKeyLength = 128
    public var maxCreationsPerWindow = 30
    public var rateWindow: TimeInterval = 60
    public var maxAgentNotes = 200

    public init() {}
    public static let standard = AgentLimits()
}

public enum AgentError: Error, Equatable, Sendable {
    case agentNotesDisabled
    case emptyText
    case textTooLong(max: Int)
    case invalidProjectName
    case invalidIdempotencyKey
    case projectNotFound(name: String, available: [String])
    case rateLimited(perMinute: Int)
    case quotaExceeded(max: Int)
    case noteNotFound
    case permissionDenied
}

extension AgentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .agentNotesDisabled:
            return "El usuario desactivó las notas de agentes en StickyDesk."
        case .emptyText:
            return "`text` no puede estar vacío."
        case .textTooLong(let max):
            return "`text` supera el máximo de \(max) caracteres."
        case .invalidProjectName:
            return "`project` no es un nombre de proyecto válido."
        case .invalidIdempotencyKey:
            return "`idempotency_key` debe tener entre 1 y 128 caracteres imprimibles."
        case .projectNotFound(let name, let available):
            let list = available.isEmpty ? "(no hay proyectos)" : available.joined(separator: ", ")
            return "El proyecto \"\(name)\" no existe. Proyectos válidos: \(list). "
                + "Usa create_project_if_missing=true para crearlo."
        case .rateLimited(let perMinute):
            return "Límite de frecuencia alcanzado: máximo \(perMinute) notas por minuto. Espera e inténtalo de nuevo."
        case .quotaExceeded(let max):
            return "Se alcanzó el tope de \(max) notas creadas por agentes. Borra notas de agentes antes de crear más."
        case .noteNotFound:
            return "No existe una nota con ese id."
        case .permissionDenied:
            return "Permiso denegado: solo se pueden borrar notas creadas por agentes."
        }
    }
}

public struct AgentNoteRequest: Sendable {
    public var text: String
    public var project: String?
    public var createProjectIfMissing: Bool
    public var idempotencyKey: String?

    public init(text: String, project: String? = nil, createProjectIfMissing: Bool = false, idempotencyKey: String? = nil) {
        self.text = text
        self.project = project
        self.createProjectIfMissing = createProjectIfMissing
        self.idempotencyKey = idempotencyKey
    }
}

public struct AgentNoteResult: Equatable, Sendable {
    public var note: Note
    public var projectName: String?
    /// `true` when the idempotency key matched an existing note.
    public var reused: Bool
}

/// Pure store operations for agents. They run inside `NotesRepository.update`, so every
/// check (idempotency, rate, quota) sees the latest on-disk state across processes.
public enum AgentOperations {
    public static func createNote(
        _ request: AgentNoteRequest,
        in store: inout NotesStore,
        now: Date = Date(),
        limits: AgentLimits = .standard
    ) throws -> AgentNoteResult {
        guard store.settings.allowAgentNotes else { throw AgentError.agentNotesDisabled }

        // Validate everything before touching the store.
        let text = TextSanitizer.sanitize(request.text, allowNewlines: true)
        guard !text.isEmpty else { throw AgentError.emptyText }
        guard text.count <= limits.maxTextLength else { throw AgentError.textTooLong(max: limits.maxTextLength) }

        var key: String?
        if let rawKey = request.idempotencyKey {
            let clean = TextSanitizer.sanitize(rawKey, allowNewlines: false)
            guard !clean.isEmpty, clean.count <= limits.maxIdempotencyKeyLength, clean == rawKey else {
                throw AgentError.invalidIdempotencyKey
            }
            key = clean
        }

        var projectName: String?
        if let rawProject = request.project {
            let clean = TextSanitizer.sanitize(rawProject, allowNewlines: false)
            guard !clean.isEmpty, clean.count <= limits.maxProjectNameLength else {
                throw AgentError.invalidProjectName
            }
            projectName = clean
        }

        // Idempotency: return the existing note instead of creating a duplicate.
        if let key, let existing = store.notes.first(where: { $0.isAgentNote && $0.idempotencyKey == key }) {
            return AgentNoteResult(note: existing, projectName: store.project(for: existing)?.name, reused: true)
        }

        // Rate limit (sliding window, persisted in the store so it holds across processes).
        let windowStart = now.addingTimeInterval(-limits.rateWindow)
        store.agentCreationLog.removeAll { $0 <= windowStart || $0 > now.addingTimeInterval(limits.rateWindow) }
        guard store.agentCreationLog.count < limits.maxCreationsPerWindow else {
            throw AgentError.rateLimited(perMinute: limits.maxCreationsPerWindow)
        }

        // Total quota.
        guard store.notes.filter(\.isAgentNote).count < limits.maxAgentNotes else {
            throw AgentError.quotaExceeded(max: limits.maxAgentNotes)
        }

        // Resolve project (case-insensitive).
        var projectID: UUID?
        if let requestedName = projectName {
            if let match = findProject(named: requestedName, in: store) {
                projectID = match.id
                projectName = match.name
            } else if request.createProjectIfMissing {
                let project = Project(
                    name: requestedName,
                    color: Palette.color(forProjectIndex: store.projects.count)
                )
                store.projects.append(project)
                projectID = project.id
            } else {
                throw AgentError.projectNotFound(
                    name: requestedName,
                    available: store.projects.map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                )
            }
        }

        let note = Note(
            text: text,
            projectID: projectID,
            createdBy: Note.agentCreator,
            idempotencyKey: key,
            createdAt: now
        )
        store.notes.append(note)
        store.agentCreationLog.append(now)
        return AgentNoteResult(note: note, projectName: projectName, reused: false)
    }

    /// Deletes a note only if it was created by an agent.
    public static func deleteNote(id: UUID, in store: inout NotesStore) throws {
        guard let note = store.note(id: id) else { throw AgentError.noteNotFound }
        guard note.isAgentNote else { throw AgentError.permissionDenied }
        store.deleteNote(id: id)
    }

    public static func findProject(named name: String, in store: NotesStore) -> Project? {
        let target = name.folding(options: [.caseInsensitive], locale: nil)
        return store.projects.first {
            $0.name.folding(options: [.caseInsensitive], locale: nil) == target
        }
    }
}

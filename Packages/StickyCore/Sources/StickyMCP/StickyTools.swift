import Foundation
import StickyCore

/// Result of a `tools/call`. Tool failures are reported in-band (`isError: true`) so the
/// agent can read the message and correct itself, as recommended by MCP.
public struct ToolOutcome: Sendable {
    public var structured: JSONValue
    public var isError: Bool

    static func success(_ value: JSONValue) -> ToolOutcome { ToolOutcome(structured: value, isError: false) }
    static func failure(_ message: String) -> ToolOutcome {
        ToolOutcome(structured: ["error": .string(message)], isError: true)
    }

    var json: JSONValue {
        let text: String
        if isError, case .string(let message)? = structured["error"] {
            text = message
        } else {
            text = String(decoding: JSONLine.encode(structured), as: UTF8.self)
        }
        return [
            "content": [["type": "text", "text": .string(text)]],
            "structuredContent": structured,
            "isError": .bool(isError),
        ]
    }
}

/// The four tools exposed to agents. Editing user notes/projects, importing Reminders
/// and EventKit access are deliberately not exposed.
public struct StickyTools: Sendable {
    public static let names: Set<String> = ["create_note", "list_projects", "list_notes", "delete_note"]
    public static let maxListLimit = 50
    public static let defaultListLimit = 20

    private let repository: NotesRepository
    private let limits: AgentLimits
    private let now: @Sendable () -> Date

    public init(
        repository: NotesRepository,
        limits: AgentLimits = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.limits = limits
        self.now = now
    }

    public func call(name: String, arguments: JSONValue?) async -> ToolOutcome {
        do {
            let args = try Arguments(arguments)
            switch name {
            case "create_note": return try await createNote(args)
            case "list_projects": return try await listProjects(args)
            case "list_notes": return try await listNotes(args)
            case "delete_note": return try await deleteNote(args)
            default: return .failure("Herramienta desconocida.")
            }
        } catch let error as ArgumentError {
            return .failure(error.message)
        } catch let error as AgentError {
            return .failure(error.localizedDescription)
        } catch let error as RepositoryError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure("Error interno.")
        }
    }

    // MARK: Tools

    private func createNote(_ args: Arguments) async throws -> ToolOutcome {
        try args.allowOnly(["text", "project", "create_project_if_missing", "idempotency_key"])
        let request = AgentNoteRequest(
            text: try args.requiredString("text", maxLength: limits.maxTextLength * 4),
            project: try args.optionalString("project", maxLength: limits.maxProjectNameLength * 4),
            createProjectIfMissing: try args.optionalBool("create_project_if_missing") ?? false,
            idempotencyKey: try args.optionalString("idempotency_key", maxLength: limits.maxIdempotencyKeyLength * 4)
        )
        let limits = limits
        let timestamp = now()
        let (_, result) = try await repository.update { store in
            try AgentOperations.createNote(request, in: &store, now: timestamp, limits: limits)
        }
        return .success([
            "id": .string(result.note.id.uuidString),
            "text": .string(result.note.text),
            "project": result.projectName.map(JSONValue.string) ?? .null,
            "reused": .bool(result.reused),
        ])
    }

    private func listProjects(_ args: Arguments) async throws -> ToolOutcome {
        try args.allowOnly([])
        let store = await repository.load()
        let projects: [JSONValue] = store.projects.map { project in
            ["name": .string(project.name), "color": .string(project.color.hexString)]
        }
        return .success(["projects": .array(projects)])
    }

    private func listNotes(_ args: Arguments) async throws -> ToolOutcome {
        try args.allowOnly(["project", "limit"])
        let projectName = try args.optionalString("project", maxLength: limits.maxProjectNameLength * 4)
        let limit = try args.optionalInt("limit", range: 1...Self.maxListLimit) ?? Self.defaultListLimit

        let store = await repository.load()
        var notes = store.notesNewestFirst
        if let projectName {
            let clean = TextSanitizer.sanitize(projectName, allowNewlines: false)
            guard let project = AgentOperations.findProject(named: clean, in: store) else {
                throw AgentError.projectNotFound(name: clean, available: store.projects.map(\.name).sorted())
            }
            notes = notes.filter { $0.projectID == project.id }
        }
        let items: [JSONValue] = notes.prefix(limit).map { note in
            [
                "id": .string(note.id.uuidString),
                "text": .string(note.text),
                "project": store.project(for: note).map { .string($0.name) } ?? .null,
                "created_by_agent": .bool(note.isAgentNote),
            ]
        }
        return .success(["notes": .array(items)])
    }

    private func deleteNote(_ args: Arguments) async throws -> ToolOutcome {
        try args.allowOnly(["id"])
        let raw = try args.requiredString("id", maxLength: 64)
        guard let id = UUID(uuidString: raw.trimmingCharacters(in: .whitespaces)) else {
            throw ArgumentError("`id` debe ser un UUID.")
        }
        try await repository.update { store in try AgentOperations.deleteNote(id: id, in: &store) }
        return .success(["deleted": .string(id.uuidString)])
    }

    // MARK: Schemas

    public static let definitions: [JSONValue] = [
        [
            "name": "create_note",
            "title": "Crear nota",
            "description": "Crea una nota post-it en StickyDesk. Si `project` no existe y `create_project_if_missing` es false, devuelve la lista de proyectos válidos. Usa `idempotency_key` para reintentos seguros.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "minLength": 1, "maxLength": 500, "description": "Texto de la nota."],
                    "project": ["type": "string", "minLength": 1, "maxLength": 60, "description": "Nombre del proyecto (sin distinguir mayúsculas)."],
                    "create_project_if_missing": ["type": "boolean", "default": false],
                    "idempotency_key": ["type": "string", "minLength": 1, "maxLength": 128],
                ],
                "required": ["text"],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false],
        ],
        [
            "name": "list_projects",
            "title": "Listar proyectos",
            "description": "Devuelve los proyectos con su nombre y color en hex.",
            "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "list_notes",
            "title": "Listar notas",
            "description": "Devuelve las notas más recientes (id, texto, proyecto). Filtro opcional por proyecto.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "project": ["type": "string", "minLength": 1, "maxLength": 60],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 50, "default": 20],
                ],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "delete_note",
            "title": "Borrar nota de agente",
            "description": "Borra una nota creada por un agente. Las notas del usuario o importadas no se pueden borrar.",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "UUID de la nota."]],
                "required": ["id"],
                "additionalProperties": false,
            ],
            "annotations": ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": true, "openWorldHint": false],
        ],
    ]
}

// MARK: - Argument validation

struct ArgumentError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Strict reader for untrusted tool arguments: exact types, bounded sizes, no unknown keys.
struct Arguments {
    private let values: [String: JSONValue]

    init(_ raw: JSONValue?) throws {
        switch raw {
        case nil, .null?: values = [:]
        case .object(let object)?: values = object
        default: throw ArgumentError("`arguments` debe ser un objeto.")
        }
    }

    func allowOnly(_ keys: Set<String>) throws {
        let unknown = Set(values.keys).subtracting(keys)
        guard unknown.isEmpty else {
            let list = unknown.sorted().map { String($0.prefix(32)) }.joined(separator: ", ")
            throw ArgumentError("Parámetros no permitidos: \(list).")
        }
    }

    func requiredString(_ key: String, maxLength: Int) throws -> String {
        guard let value = try optionalString(key, maxLength: maxLength) else {
            throw ArgumentError("Falta el parámetro obligatorio `\(key)`.")
        }
        return value
    }

    /// `maxLength` is a coarse pre-sanitization bound to reject absurd payloads early;
    /// the precise limits are enforced after sanitization by `AgentOperations`.
    func optionalString(_ key: String, maxLength: Int) throws -> String? {
        switch values[key] {
        case nil, .null?: return nil
        case .string(let s)?:
            guard s.count <= maxLength else { throw ArgumentError("`\(key)` es demasiado largo.") }
            return s
        default: throw ArgumentError("`\(key)` debe ser un string.")
        }
    }

    func optionalBool(_ key: String) throws -> Bool? {
        switch values[key] {
        case nil, .null?: return nil
        case .bool(let b)?: return b
        default: throw ArgumentError("`\(key)` debe ser booleano.")
        }
    }

    func optionalInt(_ key: String, range: ClosedRange<Int>) throws -> Int? {
        let value: Int
        switch values[key] {
        case nil, .null?: return nil
        case .int(let i)?:
            guard let v = Int(exactly: i) else { throw ArgumentError("`\(key)` fuera de rango.") }
            value = v
        case .double(let d)? where d.rounded() == d && abs(d) < 1e9:
            value = Int(d)
        default:
            throw ArgumentError("`\(key)` debe ser un entero.")
        }
        guard range.contains(value) else {
            throw ArgumentError("`\(key)` debe estar entre \(range.lowerBound) y \(range.upperBound).")
        }
        return value
    }
}

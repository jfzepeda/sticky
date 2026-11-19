import Foundation

/// Shared settings that both the app and the MCP helper must see.
public struct StoreSettings: Codable, Hashable, Sendable {
    /// When `false`, the MCP server refuses to create notes.
    public var allowAgentNotes: Bool

    public init(allowAgentNotes: Bool = true) {
        self.allowAgentNotes = allowAgentNotes
    }

    private enum CodingKeys: String, CodingKey { case allowAgentNotes }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        allowAgentNotes = try c.decodeIfPresent(Bool.self, forKey: .allowAgentNotes) ?? true
    }
}

/// The whole persisted document. One JSON file in the App Group container.
public struct NotesStore: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var notes: [Note]
    public var projects: [Project]
    public var settings: StoreSettings
    /// Timestamps of recent agent note creations, used for cross-process rate limiting.
    /// Pruned on every agent write; never grows beyond the rate-limit window.
    public var agentCreationLog: [Date]

    public init(
        notes: [Note] = [],
        projects: [Project] = [],
        settings: StoreSettings = StoreSettings(),
        agentCreationLog: [Date] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.notes = notes
        self.projects = projects
        self.settings = settings
        self.agentCreationLog = agentCreationLog
    }

    public static let empty = NotesStore()

    public func project(for note: Note) -> Project? {
        guard let id = note.projectID else { return nil }
        return projects.first { $0.id == id }
    }

    public func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    public func note(id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    /// Notes ordered newest first (what the widget shows).
    public var notesNewestFirst: [Note] {
        notes.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Codable — tolerant of older files.

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, notes, projects, settings, agentCreationLog
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        settings = try c.decodeIfPresent(StoreSettings.self, forKey: .settings) ?? StoreSettings()
        agentCreationLog = try c.decodeIfPresent([Date].self, forKey: .agentCreationLog) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(notes, forKey: .notes)
        try c.encode(projects, forKey: .projects)
        try c.encode(settings, forKey: .settings)
        try c.encode(agentCreationLog, forKey: .agentCreationLog)
    }
}

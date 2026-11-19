import Foundation

/// A single sticky note.
public struct Note: Identifiable, Codable, Hashable, Sendable {
    public static let tiltRange: ClosedRange<Double> = -4...4
    /// Value of `createdBy` for notes created through the MCP server.
    public static let agentCreator = "agent"

    public var id: UUID
    public var text: String
    /// Rotation in degrees. Generated once at creation and persisted so the note
    /// keeps the same angle across renders and launches.
    public var tilt: Double
    public var projectID: UUID?
    /// Reminder `calendarItemIdentifier` when imported from Reminders.
    public var sourceID: String?
    /// `nil` = created by the user, `"agent"` = created through MCP.
    public var createdBy: String?
    /// Idempotency key supplied by an agent, used to avoid duplicates on retries.
    public var idempotencyKey: String?
    public var createdAt: Date
    /// When the note was marked as done; `nil` = pending. Added after schema v2 (optional).
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        text: String,
        tilt: Double = Note.randomTilt(),
        projectID: UUID? = nil,
        sourceID: String? = nil,
        createdBy: String? = nil,
        idempotencyKey: String? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.tilt = Self.clampTilt(tilt)
        self.projectID = projectID
        self.sourceID = sourceID
        self.createdBy = createdBy
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    public var isCompleted: Bool { completedAt != nil }
    public var isAgentNote: Bool { createdBy == Self.agentCreator }
    public var isImported: Bool { sourceID != nil }

    public static func randomTilt() -> Double {
        var rng = SystemRandomNumberGenerator()
        return randomTilt(using: &rng)
    }

    public static func randomTilt<G: RandomNumberGenerator>(using rng: inout G) -> Double {
        Double.random(in: tiltRange, using: &rng)
    }

    static func clampTilt(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, tiltRange.lowerBound), tiltRange.upperBound)
    }

    // MARK: Codable — tolerant of files written by older versions.

    private enum CodingKeys: String, CodingKey {
        case id, text, tilt, projectID, sourceID, createdBy, idempotencyKey, createdAt, completedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        tilt = Self.clampTilt(try c.decodeIfPresent(Double.self, forKey: .tilt) ?? 0)
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        sourceID = try c.decodeIfPresent(String.self, forKey: .sourceID)
        createdBy = try c.decodeIfPresent(String.self, forKey: .createdBy)
        idempotencyKey = try c.decodeIfPresent(String.self, forKey: .idempotencyKey)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(tilt, forKey: .tilt)
        try c.encodeIfPresent(projectID, forKey: .projectID)
        try c.encodeIfPresent(sourceID, forKey: .sourceID)
        try c.encodeIfPresent(createdBy, forKey: .createdBy)
        try c.encodeIfPresent(idempotencyKey, forKey: .idempotencyKey)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
    }
}

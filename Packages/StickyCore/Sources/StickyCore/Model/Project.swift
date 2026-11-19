import Foundation

/// A group of notes with a shared color. Imported Reminders lists become projects.
public struct Project: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var color: RGBA
    /// `calendarIdentifier` of the Reminders list this project was imported from, if any.
    public var sourceID: String?

    public init(id: UUID = UUID(), name: String, color: RGBA, sourceID: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.sourceID = sourceID
    }
}

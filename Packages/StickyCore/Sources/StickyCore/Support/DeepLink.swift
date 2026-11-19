import Foundation

/// App URLs used by the widget:
/// - `stickydesk://note/<uuid>` — open a note in the editor
/// - `stickydesk://new-note` / `stickydesk://new-note?project=<uuid>` — create a note
/// - `stickydesk://new-project` — create a project
public enum DeepLink {
    public static let scheme = "stickydesk"
    public static let noteHost = "note"
    public static let newNoteHost = "new-note"
    public static let newProjectHost = "new-project"
    static let projectQueryItem = "project"

    public enum Action: Equatable, Sendable {
        case openNote(UUID)
        case newNote(projectID: UUID?)
        case newProject
    }

    public static func noteURL(for id: UUID) -> URL {
        url(host: noteHost, path: "/" + id.uuidString)
    }

    public static func newNoteURL(projectID: UUID?) -> URL {
        url(host: newNoteHost, query: projectID.map { [URLQueryItem(name: projectQueryItem, value: $0.uuidString)] })
    }

    public static var newProjectURL: URL {
        url(host: newProjectHost)
    }

    /// Strictly parses any app URL; anything unexpected returns `nil`.
    public static func action(from url: URL) -> Action? {
        guard url.scheme?.lowercased() == scheme, url.fragment == nil,
              let host = url.host?.lowercased()
        else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }

        switch host {
        case noteHost:
            guard url.query == nil, parts.count == 1, let id = UUID(uuidString: parts[0]) else { return nil }
            return .openNote(id)
        case newNoteHost:
            guard parts.isEmpty else { return nil }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if items.isEmpty { return .newNote(projectID: nil) }
            guard items.count == 1, items[0].name == projectQueryItem,
                  let value = items[0].value, let id = UUID(uuidString: value)
            else { return nil }
            return .newNote(projectID: id)
        case newProjectHost:
            guard parts.isEmpty, url.query == nil else { return nil }
            return .newProject
        default:
            return nil
        }
    }

    /// Strictly parses a note deep link; anything unexpected returns `nil`.
    public static func noteID(from url: URL) -> UUID? {
        if case .openNote(let id) = action(from: url) { return id }
        return nil
    }

    private static func url(host: String, path: String = "", query: [URLQueryItem]? = nil) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.queryItems = query
        // URLComponents with these fixed parts always yields a URL; fall back rather than trap.
        return components.url ?? URL(fileURLWithPath: "/")
    }
}

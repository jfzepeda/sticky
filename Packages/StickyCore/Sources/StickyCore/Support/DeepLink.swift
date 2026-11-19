import Foundation

/// `stickydesk://note/<uuid>`
public enum DeepLink {
    public static let scheme = "stickydesk"
    public static let noteHost = "note"

    public static func noteURL(for id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = noteHost
        components.path = "/" + id.uuidString
        // Force-unwrap-free: URLComponents with these fixed parts always yields a URL,
        // but fall back to a safe value rather than trapping.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// Strictly parses a note deep link; anything unexpected returns `nil`.
    public static func noteID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == noteHost,
              url.query == nil, url.fragment == nil
        else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1 else { return nil }
        return UUID(uuidString: parts[0])
    }
}

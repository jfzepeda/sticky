import Foundation
import WidgetKit

public enum WidgetReloader {
    public static let widgetKind = "StickyWidget"

    /// Asks WidgetKit to refresh every StickyDesk timeline. The system decides when it
    /// actually happens; this is a request, not a guarantee.
    public static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

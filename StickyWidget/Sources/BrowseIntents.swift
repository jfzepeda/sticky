import AppIntents
import StickyCore
import WidgetKit

// Interactive-widget intents. They run in the widget extension and only touch the small
// browse-state file (never the notes store); WidgetKit reloads the timeline afterwards.

struct OpenStackIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir proyecto"
    static let isDiscoverable = false

    @Parameter(title: "Grupo") var groupID: String
    @Parameter(title: "Widget") var family: String

    init() {}

    init(groupID: String, family: String) {
        self.groupID = groupID
        self.family = family
    }

    func perform() async throws -> some IntentResult {
        try WidgetBrowseStore.update(at: WidgetBrowseStore.url()) { $0.open(groupID: groupID, family: family) }
        return .result()
    }
}

struct CloseStackIntent: AppIntent {
    static let title: LocalizedStringResource = "Volver a los proyectos"
    static let isDiscoverable = false

    @Parameter(title: "Widget") var family: String

    init() {}

    init(family: String) {
        self.family = family
    }

    func perform() async throws -> some IntentResult {
        try WidgetBrowseStore.update(at: WidgetBrowseStore.url()) { $0.close(family: family) }
        return .result()
    }
}

struct ShowPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Cambiar de página"
    static let isDiscoverable = false

    @Parameter(title: "Widget") var family: String
    @Parameter(title: "Página") var page: Int
    @Parameter(title: "Dentro de un proyecto") var inGroup: Bool

    init() {}

    init(family: String, page: Int, inGroup: Bool) {
        self.family = family
        self.page = page
        self.inGroup = inGroup
    }

    func perform() async throws -> some IntentResult {
        try WidgetBrowseStore.update(at: WidgetBrowseStore.url()) {
            $0.setPage(page, family: family, inGroup: inGroup)
        }
        return .result()
    }
}

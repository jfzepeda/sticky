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

/// The only widget intent that writes the notes store: it goes through `NotesRepository`
/// (cross-process lock + atomic write) and posts the Darwin notification so the app reloads.
struct ToggleNoteCompletedIntent: AppIntent {
    static let title: LocalizedStringResource = "Marcar nota como completada"
    static let isDiscoverable = false

    @Parameter(title: "Nota") var noteID: String

    init() {}

    init(noteID: String) {
        self.noteID = noteID
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: noteID) else { return .result() }
        let repository = try NotesRepository.shared(didSave: {
            DarwinNotifier.post()
            WidgetReloader.reloadAll()
        })
        try await repository.update { try $0.toggleNoteCompleted(id: id) }
        return .result()
    }
}

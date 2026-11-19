import AppIntents
import StickyCore
import WidgetKit

/// "Edit widget" options: all projects (default) or one specific project.
struct StickyConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Notas"
    static let description = IntentDescription("Elige si el widget muestra todos los proyectos o solo uno.")

    @Parameter(title: "Proyecto")
    var project: ProjectEntity?

    init() {}

    init(project: ProjectEntity?) {
        self.project = project
    }

    /// `nil` for "Todos" (or nothing chosen yet).
    var pinnedProjectID: UUID? {
        project.flatMap { UUID(uuidString: $0.id) }
    }
}

/// A project as the widget editor lists it. `ProjectEntity.all` is the "Todos" choice.
struct ProjectEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Proyecto"
    static let defaultQuery = ProjectQuery()

    static let allID = "all"
    static let all = ProjectEntity(id: allID, name: "Todos los proyectos")

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ProjectQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        let available = Self.available()
        return identifiers.compactMap { id in available.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [ProjectEntity] {
        Self.available()
    }

    func defaultResult() async -> ProjectEntity? {
        .all
    }

    /// "Todos" first, then the projects in the store, alphabetically.
    private static func available() -> [ProjectEntity] {
        let store = (try? AppGroup.storeURL()).map(StoreCodec.loadStore(from:)) ?? .empty
        let projects = store.projects
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { ProjectEntity(id: $0.id.uuidString, name: $0.name) }
        return [.all] + projects
    }
}

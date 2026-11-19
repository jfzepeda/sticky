import AppKit
import StickyCore
import SwiftUI

@main
struct StickyDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("StickyDesk", systemImage: "note.text") {
            MenuContentView()
                .environment(appDelegate.model)
                .environment(appDelegate.panels)
                .environment(appDelegate.importer)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns long-lived state and receives `stickydesk://` URLs (MenuBarExtra scenes
/// don't reliably get `onOpenURL`, so we use the delegate).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    lazy var panels = PanelPresenter(model: model)
    lazy var importer = RemindersImportController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        importer.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let action = DeepLink.action(from: url) else { continue }
            Task { @MainActor in
                await model.reloadFromDisk()
                switch action {
                case .openNote(let id):
                    if model.store.note(id: id) != nil {
                        panels.showNoteEditor(noteID: id)
                    } else {
                        model.errorMessage = "La nota ya no existe."
                    }
                case .newNote(let projectID):
                    // A project deleted since the widget rendered → create without project.
                    let existing = projectID.flatMap { model.store.project(id: $0)?.id }
                    panels.showNoteEditor(noteID: nil, projectID: existing)
                case .newProject:
                    panels.showProjectEditor()
                }
            }
        }
    }
}

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
            guard let id = DeepLink.noteID(from: url) else { continue }
            Task { @MainActor in
                await model.reloadFromDisk()
                if model.store.note(id: id) != nil {
                    panels.showNoteEditor(noteID: id)
                } else {
                    model.errorMessage = "La nota ya no existe."
                }
            }
        }
    }
}

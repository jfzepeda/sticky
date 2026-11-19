import AppKit
import Observation
import SwiftUI

/// Shows editors in standalone floating panels. The MenuBarExtra popover closes when it
/// loses focus (e.g. when the color panel opens), so editing happens outside it.
@MainActor
@Observable
final class PanelPresenter {
    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private var panels: [String: NSPanel] = [:]

    init(model: AppModel) {
        self.model = model
    }

    func showNoteEditor(noteID: UUID?) {
        let key = "note-\(noteID?.uuidString ?? "new")"
        show(key: key, title: noteID == nil ? "Nueva nota" : "Editar nota") { [model] close in
            NoteEditorView(noteID: noteID, onClose: close)
                .environment(model)
        }
    }

    func showProjectEditor(projectID: UUID?) {
        let key = "project-\(projectID?.uuidString ?? "new")"
        show(key: key, title: projectID == nil ? "Nuevo proyecto" : "Editar proyecto") { [model] close in
            ProjectEditorView(projectID: projectID, onClose: close)
                .environment(model)
        }
    }

    private func show<Content: View>(
        key: String,
        title: String,
        @ViewBuilder content: (@escaping () -> Void) -> Content
    ) {
        if let existing = panels[key] {
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false

        let close: () -> Void = { [weak self, weak panel] in
            panel?.close()
            self?.panels[key] = nil
        }
        panel.contentViewController = NSHostingController(rootView: content(close))
        panel.center()

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panels[key] = nil }
        }

        panels[key] = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }
}

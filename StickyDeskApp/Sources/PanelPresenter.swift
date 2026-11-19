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

    /// `projectID` preselects the project for a new note (ignored when editing).
    func showNoteEditor(noteID: UUID?, projectID: UUID? = nil) {
        // New-note panels are per project so a "+" from another stack isn't swallowed.
        let key = noteID.map { "note-\($0.uuidString)" } ?? "note-new-\(projectID?.uuidString ?? "none")"
        show(key: key, title: noteID == nil ? "Nueva nota" : "Editar nota") { [model] close in
            NoteEditorView(noteID: noteID, initialProjectID: projectID, onClose: close)
                .environment(model)
        }
    }

    /// New project from the widget's "+" (the menu bar window can't be opened programmatically,
    /// so this reuses the inline editor in a panel; swatches need no color panel).
    func showProjectEditor() {
        show(key: "project-new", title: "Nuevo proyecto") { [model] close in
            ProjectEditorForm(projectID: nil, onClose: close)
                .padding(12)
                .frame(width: 360)
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
            styleMask: [.titled, .closable],
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
        // Size the panel to the SwiftUI content so it never opens collapsed or clipped.
        let hosting = NSHostingController(rootView: content(close))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting
        let fitting = hosting.view.fittingSize
        if fitting.width > 0, fitting.height > 0 {
            panel.setContentSize(fitting)
        }
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

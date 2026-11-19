import StickyCore
import SwiftUI

/// Create (`noteID == nil`) or edit a note. Shown in its own panel.
struct NoteEditorView: View {
    let noteID: UUID?
    var initialProjectID: UUID?
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var projectID: UUID?
    @State private var loaded = false

    private var note: Note? { noteID.flatMap { model.store.note(id: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if noteID != nil && note == nil {
                ContentUnavailableView("La nota ya no existe", systemImage: "questionmark.square.dashed")
                HStack { Spacer(); Button("Cerrar", action: onClose) }
            } else {
                if let note, note.isImported {
                    Label("Importada de Recordatorios: la próxima importación puede sobrescribir el texto.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextEditor(text: $text)
                    .font(.system(size: 14, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background((model.store.project(id: projectID ?? UUID())?.color.postItRGBA ?? .vanilla).solid,
                                in: RoundedRectangle(cornerRadius: 4))
                    .frame(minHeight: 140)
                Text("\(text.count)/\(NotesStore.maxNoteLength)")
                    .font(.caption2)
                    .foregroundStyle(text.count > NotesStore.maxNoteLength ? .red : .secondary)
                HStack {
                    ProjectPicker(selection: $projectID)
                    if let note {
                        Toggle("Completada", isOn: Binding(
                            get: { note.isCompleted },
                            set: { done in Task { await model.setNoteCompleted(id: note.id, done) } }
                        ))
                        .toggleStyle(.checkbox)
                    }
                    Spacer()
                    if let noteID {
                        Button("Borrar", role: .destructive) {
                            Task { await model.deleteNote(id: noteID); onClose() }
                        }
                    }
                    Button("Cancelar", action: onClose).keyboardShortcut(.cancelAction)
                    Button("Guardar", action: save).keyboardShortcut(.defaultAction)
                }
                if let error = model.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .onAppear(perform: loadOnce)
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        if let note {
            text = note.text
            projectID = note.projectID
        } else {
            projectID = initialProjectID
        }
    }

    private func save() {
        let text = text
        let projectID = projectID
        Task {
            let ok: Bool
            if let noteID {
                ok = await model.updateNote(id: noteID, text: text, projectID: projectID)
            } else {
                ok = await model.addNote(text: text, projectID: projectID)
            }
            if ok { onClose() }
        }
    }
}

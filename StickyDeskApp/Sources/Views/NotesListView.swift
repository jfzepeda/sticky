import StickyCore
import SwiftUI

struct NotesListView: View {
    @Environment(AppModel.self) private var model
    @Environment(PanelPresenter.self) private var panels

    @State private var draft = ""
    @State private var draftProjectID: UUID?
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            newNoteForm
            Divider()
            if model.store.notes.isEmpty {
                ContentUnavailableView("Sin notas", systemImage: "note.text",
                                       description: Text("Escribe una arriba o importa desde Recordatorios."))
            } else {
                List {
                    ForEach(model.store.notesNewestFirst) { note in
                        NoteRow(note: note, project: model.store.project(for: note))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { panels.showNoteEditor(noteID: note.id) }
                            .contextMenu {
                                Button("Editar…") { panels.showNoteEditor(noteID: note.id) }
                                Button("Borrar", role: .destructive) {
                                    Task { await model.deleteNote(id: note.id) }
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var newNoteForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Nueva nota…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($draftFocused)
                .onSubmit(addDraft)
            HStack {
                ProjectPicker(selection: $draftProjectID)
                Spacer()
                Button("Añadir", action: addDraft)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addDraft() {
        let text = draft
        let projectID = draftProjectID
        Task {
            if await model.addNote(text: text, projectID: projectID) {
                draft = ""
                draftFocused = true
            }
        }
    }
}

struct NoteRow: View {
    let note: Note
    let project: Project?
    @Environment(AppModel.self) private var model
    @Environment(PanelPresenter.self) private var panels

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ProjectSwatch(color: project?.color)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.text).lineLimit(3)
                HStack(spacing: 4) {
                    if let project {
                        Text(project.name.uppercased())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if note.isImported {
                        Image(systemName: "checklist")
                            .help("Importada de Recordatorios")
                    }
                    if note.isAgentNote {
                        Image(systemName: "cpu")
                            .help("Creada por un agente (MCP)")
                            .accessibilityLabel("Creada por un agente")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            Button { panels.showNoteEditor(noteID: note.id) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Editar nota")
            Button(role: .destructive) {
                Task { await model.deleteNote(id: note.id) }
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Borrar nota")
        }
        .padding(.vertical, 2)
    }
}

struct ProjectPicker: View {
    @Binding var selection: UUID?
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker("Proyecto", selection: $selection) {
            Text("Sin proyecto").tag(UUID?.none)
            ForEach(model.store.projects) { project in
                Text(project.name).tag(UUID?.some(project.id))
            }
        }
        .fixedSize()
    }
}

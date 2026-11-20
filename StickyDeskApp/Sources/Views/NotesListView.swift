import StickyCore
import SwiftUI

struct NotesListView: View {
    @Environment(AppModel.self) private var model
    @Environment(PanelPresenter.self) private var panels

    @State private var draft = ""
    @State private var draftProjectID: UUID?
    @State private var filter: NoteFilter = .pending
    @State private var confirmingDeleteCompleted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            newNoteForm
            Divider()
            filterBar
            let notes = model.store.notes(matching: filter)
            if notes.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(notes) { note in
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

    private var completedCount: Int {
        model.store.notes.count { $0.isCompleted }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Picker("Mostrar", selection: $filter) {
                ForEach(NoteFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .onChange(of: filter) { confirmingDeleteCompleted = false }
            Spacer(minLength: 0)
            if completedCount > 0 {
                if confirmingDeleteCompleted {
                    Text("¿Borrar \(completedCount)?").font(.caption)
                    Button("Sí", role: .destructive) {
                        confirmingDeleteCompleted = false
                        Task { await model.deleteCompletedNotes() }
                    }
                    Button("No") { confirmingDeleteCompleted = false }
                } else {
                    Button(role: .destructive) { confirmingDeleteCompleted = true } label: {
                        Label("Borrar completadas", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Borrar las \(completedCount) notas completadas")
                    .accessibilityLabel("Borrar todas las completadas")
                }
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch filter {
        case .pending where !model.store.notes.isEmpty:
            ContentUnavailableView("Todo listo", systemImage: "checkmark.circle",
                                   description: Text("No hay notas pendientes."))
        case .completed:
            ContentUnavailableView("Sin completadas", systemImage: "checkmark.circle",
                                   description: Text("Marca una nota con la palomita para verla aquí."))
        default:
            ContentUnavailableView("Sin notas", systemImage: "note.text",
                                   description: Text("Escribe una arriba o importa desde Recordatorios."))
        }
    }

    private var newNoteForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            ListTextEditor(text: $draft, placeholder: "Nueva nota…  (\"- \" viñetas, \"1 \" numerada)")
                .padding(4)
                .frame(height: 76)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
            HStack {
                ProjectPicker(selection: $draftProjectID)
                Spacer()
                // Return adds lines / list items inside the box, so adding is ⌘↩.
                Button("Añadir", action: addDraft)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Añadir (⌘↩)")
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addDraft() {
        let text = ListFormatting.trimmingEmptyTrailingItems(draft)
        let projectID = draftProjectID
        Task {
            if await model.addNote(text: text, projectID: projectID) {
                draft = ""
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
            Button {
                Task { await model.setNoteCompleted(id: note.id, !note.isCompleted) }
            } label: {
                Image(systemName: note.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(note.isCompleted ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(note.isCompleted ? "Marcar como pendiente" : "Marcar como completada")
            ProjectSwatch(color: project?.color)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.text).lineLimit(3)
                    .strikethrough(note.isCompleted)
                    .foregroundStyle(note.isCompleted ? .secondary : .primary)
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

import StickyCore
import SwiftUI

struct ProjectsView: View {
    /// What the inline editor is working on.
    enum EditTarget: Equatable {
        case new
        case existing(UUID)
    }

    @Environment(AppModel.self) private var model
    @State private var pendingDelete: UUID?
    @State private var editing: EditTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Proyectos").font(.headline)
                Spacer()
                if editing == nil {
                    Button { startEditing(.new) } label: {
                        Label("Nuevo proyecto", systemImage: "plus")
                    }
                }
            }

            if editing == .new {
                ProjectEditorForm(projectID: nil, onClose: { editing = nil })
            }

            if model.store.projects.isEmpty {
                if editing == nil {
                    ContentUnavailableView("Sin proyectos", systemImage: "folder",
                                           description: Text("Las notas sin proyecto usan color vainilla."))
                }
            } else {
                List(model.store.projects) { project in
                    if editing == .existing(project.id) {
                        ProjectEditorForm(projectID: project.id, onClose: { editing = nil })
                            .listRowSeparator(.hidden)
                    } else {
                        row(project)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .animation(.snappy(duration: 0.2), value: editing)
    }

    private func startEditing(_ target: EditTarget) {
        pendingDelete = nil
        model.errorMessage = nil
        editing = target
    }

    @ViewBuilder
    private func row(_ project: Project) -> some View {
        let count = model.store.notes.filter { $0.projectID == project.id }.count
        HStack {
            ProjectSwatch(color: project.color)
            VStack(alignment: .leading) {
                Text(project.name)
                Text(project.sourceID == nil ? "\(count) notas" : "\(count) notas · Recordatorios")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if pendingDelete == project.id {
                Text("¿Borrar?").font(.caption)
                Button("Sí", role: .destructive) {
                    pendingDelete = nil
                    Task { await model.deleteProject(id: project.id) }
                }
                Button("No") { pendingDelete = nil }
            } else {
                Button { startEditing(.existing(project.id)) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Editar proyecto")
                Button(role: .destructive) { pendingDelete = project.id } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Borrar proyecto")
                    .help("Las notas del proyecto se conservan sin proyecto.")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { startEditing(.existing(project.id)) }
    }
}

/// Create (`projectID == nil`) or edit a project directly inside the menu bar window
/// (also hosted in a panel when the widget's "+" asks for a new project).
/// Colors come from a fixed swatch row instead of `ColorPicker`: the system color panel
/// steals focus and the MenuBarExtra window closes as soon as it loses it.
struct ProjectEditorForm: View {
    let projectID: UUID?
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var color: RGBA = Palette.colors[0]
    @State private var loaded = false
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    /// Vanilla + the fixed palette, plus the project's current color if it's custom
    /// (e.g. imported from a Reminders list) so editing never silently changes it.
    private var swatches: [RGBA] {
        var colors = [RGBA.vanilla] + Palette.colors
        if !colors.contains(color) { colors.append(color) }
        return colors
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.postItColor)
                    .frame(width: 30, height: 30)
                    .shadow(radius: 1, y: 1)
                TextField(projectID == nil ? "Nombre del nuevo proyecto" : "Nombre del proyecto", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(save)
                    .onExitCommand(perform: onClose)
            }
            HStack(spacing: 6) {
                ForEach(swatches, id: \.self) { swatch in
                    let isSelected = swatch == color
                    Button { color = swatch } label: {
                        Circle()
                            .fill(swatch.postItColor)
                            .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                            .padding(isSelected ? 3 : 0)
                            .overlay(Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
                            .frame(width: 22, height: 22)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(swatch.hexString)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancelar", action: onClose)
                Button(projectID == nil ? "Crear" : "Guardar", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .onAppear(perform: loadOnce)
    }

    private func loadOnce() {
        guard !loaded else { return }
        loaded = true
        if let projectID, let project = model.store.project(id: projectID) {
            name = project.name
            color = project.color
        } else {
            // Suggest the next palette color, same rule agents use.
            color = Palette.color(forProjectIndex: model.store.projects.count)
        }
        nameFocused = true
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        let name = name
        let color = color
        Task {
            defer { isSaving = false }
            let ok: Bool
            if let projectID {
                ok = await model.updateProject(id: projectID, name: name, color: color)
            } else {
                ok = await model.addProject(name: name, color: color)
            }
            if ok { onClose() }
        }
    }
}

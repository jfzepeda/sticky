import StickyCore
import SwiftUI

struct ProjectsView: View {
    @Environment(AppModel.self) private var model
    @Environment(PanelPresenter.self) private var panels
    @State private var pendingDelete: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Proyectos").font(.headline)
                Spacer()
                Button { panels.showProjectEditor(projectID: nil) } label: {
                    Label("Nuevo proyecto", systemImage: "plus")
                }
            }
            if model.store.projects.isEmpty {
                ContentUnavailableView("Sin proyectos", systemImage: "folder",
                                       description: Text("Las notas sin proyecto usan color vainilla."))
            } else {
                List(model.store.projects) { project in
                    row(project)
                }
                .listStyle(.plain)
            }
        }
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
                Button { panels.showProjectEditor(projectID: project.id) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Editar proyecto")
                Button(role: .destructive) { pendingDelete = project.id } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Borrar proyecto")
                    .help("Las notas del proyecto se conservan sin proyecto.")
            }
        }
    }
}

struct ProjectEditorView: View {
    let projectID: UUID?
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var color: Color = RGBA.vanilla.solid
    @State private var loaded = false

    var body: some View {
        Form {
            TextField("Nombre", text: $name)
            ColorPicker("Color", selection: $color, supportsOpacity: false)
            HStack {
                Text("Vista previa").foregroundStyle(.secondary)
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill((RGBA(color: color) ?? .vanilla).postItColor)
                    .frame(width: 44, height: 44)
                    .shadow(radius: 1, y: 1)
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancelar", action: onClose).keyboardShortcut(.cancelAction)
                Button("Guardar", action: save).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let projectID, let project = model.store.project(id: projectID) {
                name = project.name
                color = project.color.solid
            }
        }
    }

    private func save() {
        let name = name
        let rgba = RGBA(color: color) ?? .vanilla
        Task {
            let ok: Bool
            if let projectID {
                ok = await model.updateProject(id: projectID, name: name, color: rgba)
            } else {
                ok = await model.addProject(name: name, color: rgba)
            }
            if ok { onClose() }
        }
    }
}

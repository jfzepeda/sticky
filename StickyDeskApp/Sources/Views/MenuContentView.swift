import StickyCore
import SwiftUI

struct MenuContentView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case notes = "Notas"
        case projects = "Proyectos"
        case reminders = "Recordatorios"
        case settings = "Ajustes"
        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .notes

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Sección", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
            }

            Group {
                switch tab {
                case .notes: NotesListView()
                case .projects: ProjectsView()
                case .reminders: RemindersImportView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            HStack {
                Text("\(model.store.notes.count) notas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Salir") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 380, height: 500)
        .task { await model.reloadFromDisk() }
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Cerrar aviso")
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Small colored dot for a project (vanilla for none).
struct ProjectSwatch: View {
    let color: RGBA?
    var body: some View {
        Circle()
            .fill((color?.postItRGBA ?? .vanilla).solid)
            .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
            .frame(width: 12, height: 12)
    }
}

import StickyCore
import SwiftUI

struct MenuContentView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case notes = "Notas"
        case projects = "Proyectos"
        case reminders = "Recordatorios"
        case settings = "Ajustes"
        var id: Self { self }

        var symbol: String {
            switch self {
            case .notes: "note.text"
            case .projects: "folder"
            case .reminders: "checklist"
            case .settings: "gearshape"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .notes

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A segmented Picker can't shrink below its intrinsic width; with four Spanish
            // labels it was wider than the 380 pt window and pushed every section off-screen.
            TabBar(selection: $tab)

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

private struct TabBar: View {
    @Binding var selection: MenuContentView.Tab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MenuContentView.Tab.allCases) { tab in
                let isSelected = tab == selection
                Button { selection = tab } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.symbol).font(.system(size: 14, weight: .medium))
                        Text(tab.rawValue).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(isSelected ? Color.accentColor.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
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

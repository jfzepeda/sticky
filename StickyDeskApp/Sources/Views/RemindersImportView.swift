import AppKit
import StickyCore
import SwiftUI

struct RemindersImportView: View {
    @Environment(RemindersImportController.self) private var importer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch importer.access {
            case .notDetermined:
                Text("StickyDesk puede mostrar tus recordatorios pendientes como notas. "
                     + "La importación es de solo lectura.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Permitir acceso a Recordatorios…") {
                    Task { await importer.requestAccess() }
                }
            case .denied, .restricted, .writeOnly:
                deniedHelp
            case .granted:
                listPicker
            }
        }
    }

    private var deniedHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sin acceso a Recordatorios", systemImage: "lock.fill").font(.headline)
            Text("Para importar, abre **Ajustes del Sistema → Privacidad y seguridad → Recordatorios** "
                 + "y activa StickyDesk con acceso completo. Después vuelve a abrir esta sección.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Abrir Ajustes del Sistema…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    @ViewBuilder
    private var listPicker: some View {
        @Bindable var importer = importer
        Text("Listas a importar").font(.headline)
        if importer.lists.isEmpty {
            Text("No hay listas de Recordatorios.").foregroundStyle(.secondary)
        } else {
            List(importer.lists) { list in
                Toggle(isOn: Binding(
                    get: { importer.selectedListIDs.contains(list.id) },
                    set: { _ in importer.toggle(list) }
                )) {
                    HStack {
                        Circle().fill(list.color.solid).frame(width: 10, height: 10)
                        Text(list.name)
                    }
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 120)
        }
        Toggle("Limpiar huérfanas (borra notas importadas que ya no están pendientes)",
               isOn: $importer.removeOrphans)
            .font(.callout)
        HStack {
            Button {
                Task { await importer.importNow() }
            } label: {
                if importer.isImporting { ProgressView().controlSize(.small) } else { Text("Importar ahora") }
            }
            .disabled(importer.selectedListIDs.isEmpty || importer.isImporting)
            Spacer()
            if let summary = importer.lastSummary {
                Text("+\(summary.notesCreated) · ✎\(summary.notesUpdated) · −\(summary.notesRemoved)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Creadas · actualizadas · eliminadas")
            }
        }
        Text("Se reimporta automáticamente cuando cambian tus Recordatorios mientras la app está abierta.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

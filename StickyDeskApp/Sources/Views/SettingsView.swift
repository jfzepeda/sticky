import AppKit
import ServiceManagement
import StickyCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var loginItem = LoginItemController()
    @State private var confirmDeleteAgents = false
    @State private var copiedMessage: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Abrir al iniciar sesión", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.requiresApproval {
                    Button("Aprobar en Ajustes del Sistema…") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let error = loginItem.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Agentes (MCP)") {
                Toggle("Permitir notas de agentes", isOn: Binding(
                    get: { model.store.settings.allowAgentNotes },
                    set: { value in Task { await model.setAllowAgentNotes(value) } }
                ))
                let agentCount = model.store.notes.filter(\.isAgentNote).count
                if confirmDeleteAgents {
                    HStack {
                        Text("¿Borrar \(agentCount) notas de agentes?")
                        Spacer()
                        Button("Borrar", role: .destructive) {
                            confirmDeleteAgents = false
                            Task { _ = await model.deleteAllAgentNotes() }
                        }
                        Button("Cancelar") { confirmDeleteAgents = false }
                    }
                } else {
                    Button("Borrar todas las notas de agentes (\(agentCount))", role: .destructive) {
                        confirmDeleteAgents = true
                    }
                    .disabled(agentCount == 0)
                }

                if MCPConfiguration.isHelperInstalled {
                    Button("Copiar configuración para Claude Code") {
                        copy(MCPConfiguration.claudeCodeCommand(), label: "Comando copiado")
                    }
                    Button("Copiar configuración para Claude Desktop") {
                        copy(MCPConfiguration.claudeDesktopJSON(), label: "JSON copiado")
                    }
                } else {
                    Text("No se encontró stickydesk-mcp dentro de la app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let copiedMessage {
                    Text(copiedMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }

    private func copy(_ string: String, label: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        copiedMessage = label
    }
}

import Observation
import ServiceManagement

/// Wraps `SMAppService.mainApp` for the "open at login" toggle.
@MainActor
@Observable
final class LoginItemController {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = "No se pudo cambiar el inicio automático: \(error.localizedDescription)"
        }
        refresh()
    }
}

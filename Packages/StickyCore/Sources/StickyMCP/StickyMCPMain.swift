import Foundation
import StickyCore

/// Entry point shared by the SwiftPM executable and the Xcode `stickydesk-mcp` target.
public enum StickyMCPMain {
    /// Debug-only override so tests can point the server at a temporary file.
    /// Compiled out of Release builds: production always uses the App Group container.
    static let storePathEnvironmentKey = "STICKYDESK_STORE_PATH"

    public static func run() async -> Int32 {
        let log = StderrLog()
        let repository: NotesRepository
        do {
            repository = try makeRepository()
        } catch {
            log.info("Cannot open store: \(error.localizedDescription)")
            return 1
        }

        let server = MCPServer(tools: StickyTools(repository: repository), log: log)
        log.info("ready (stdio)")
        await StdioTransport().run(
            server: server,
            input: .standardInput,
            output: .standardOutput,
            log: log
        )
        return 0
    }

    static func makeRepository() throws -> NotesRepository {
        let didSave: @Sendable () -> Void = {
            // The app (if running) reloads on this and refreshes the widget immediately.
            DarwinNotifier.post()
            // Best effort from a CLI process; if WidgetKit ignores it, the widget refreshes on
            // its next timeline reload (≤ 30 min). See README.
            WidgetReloader.reloadAll()
        }
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment[storePathEnvironmentKey], !path.isEmpty {
            return NotesRepository(fileURL: URL(fileURLWithPath: path), didSave: didSave)
        }
        #endif
        return try NotesRepository.shared(didSave: didSave)
    }
}

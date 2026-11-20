import Foundation
import Observation
import StickyCore
import os

/// Main-actor view model. All writes go through `NotesRepository.update`, so they are
/// read-modify-write under the cross-process lock and never clobber MCP writes.
@MainActor
@Observable
final class AppModel {
    private(set) var store: NotesStore = .empty
    var errorMessage: String?

    @ObservationIgnored private let repository: NotesRepository?
    @ObservationIgnored private var storeObservation: DarwinObservation?
    @ObservationIgnored private let logger = Logger(subsystem: "com.jfzepeda.stickydesk", category: "app")

    init(repository: NotesRepository? = nil) {
        if let repository {
            self.repository = repository
        } else {
            do {
                self.repository = try NotesRepository.shared()
            } catch {
                self.repository = nil
                self.errorMessage = error.localizedDescription
                logger.error("Repository unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }

        // The MCP helper posts this after writing; reload and refresh the widget.
        storeObservation = DarwinObservation { [weak self] in
            Task { @MainActor [weak self] in
                await self?.reloadFromDisk()
                WidgetReloader.reloadAll()
            }
        }

        Task { await reloadFromDisk() }
    }

    var isAvailable: Bool { repository != nil }

    func reloadFromDisk() async {
        guard let repository else { return }
        store = await repository.load()
    }

    /// Runs a mutation under the file lock and publishes the result. Returns the body's
    /// result, or `nil` after surfacing the error to the UI.
    @discardableResult
    func perform<T: Sendable>(_ body: @escaping @Sendable (inout NotesStore) throws -> T) async -> T? {
        guard let repository else {
            errorMessage = RepositoryError.appGroupNotConfigured.localizedDescription
            return nil
        }
        do {
            let (newStore, result) = try await repository.update(body)
            store = newStore
            errorMessage = nil
            return result
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Notes

    @discardableResult
    func addNote(text: String, projectID: UUID?) async -> Bool {
        await perform { try $0.addNote(text: text, projectID: projectID) } != nil
    }

    @discardableResult
    func updateNote(id: UUID, text: String, projectID: UUID?) async -> Bool {
        await perform { try $0.updateNote(id: id, text: text, projectID: projectID) } != nil
    }

    func setNoteCompleted(id: UUID, _ completed: Bool) async {
        await perform { try $0.setNoteCompleted(id: id, completed) }
    }

    func deleteCompletedNotes() async -> Int {
        await perform { $0.deleteCompletedNotes() } ?? 0
    }

    func deleteNote(id: UUID) async {
        await perform { $0.deleteNote(id: id) }
    }

    // MARK: Projects

    @discardableResult
    func addProject(name: String, color: RGBA) async -> Bool {
        await perform { try $0.addProject(name: name, color: color) } != nil
    }

    @discardableResult
    func updateProject(id: UUID, name: String, color: RGBA) async -> Bool {
        await perform { try $0.updateProject(id: id, name: name, color: color) } != nil
    }

    func deleteProject(id: UUID) async {
        await perform { $0.deleteProject(id: id) }
    }

    // MARK: Agents

    func setAllowAgentNotes(_ allowed: Bool) async {
        await perform { $0.settings.allowAgentNotes = allowed }
    }

    func deleteAllAgentNotes() async -> Int {
        await perform { $0.deleteAllAgentNotes() } ?? 0
    }
}

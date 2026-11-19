import Foundation
import os

public enum RepositoryError: Error, Equatable, Sendable {
    case appGroupNotConfigured
    case containerUnavailable(String)
    case lockFailed(errno: Int32)
    case lockTimeout
    case encodingFailed(String)
    case writeFailed(String)
}

extension RepositoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .appGroupNotConfigured:
            "Falta la clave StickyAppGroupID en Info.plist."
        case .containerUnavailable(let id):
            "No se pudo acceder al contenedor del App Group \(id). Revisa la firma y los entitlements."
        case .lockFailed(let code):
            "No se pudo bloquear el archivo de notas (errno \(code))."
        case .lockTimeout:
            "El archivo de notas está ocupado por otro proceso. Inténtalo de nuevo."
        case .encodingFailed(let detail):
            "No se pudieron codificar las notas: \(detail)"
        case .writeFailed(let detail):
            "No se pudieron guardar las notas: \(detail)"
        }
    }
}

/// Owns the shared JSON file. Every mutation is a read-modify-write performed while
/// holding a cross-process `flock`, followed by an atomic replace of the file.
public actor NotesRepository {
    public nonisolated let fileURL: URL
    private nonisolated let lockURL: URL
    private let didSave: @Sendable () -> Void
    private let logger = Logger(subsystem: "com.jfzepeda.stickydesk", category: "repository")

    /// - Parameters:
    ///   - fileURL: Location of `notes.json`. A sibling `notes.lock` is created next to it.
    ///   - didSave: Called after every successful save (e.g. reload widgets, post a Darwin notification).
    public init(fileURL: URL, didSave: @escaping @Sendable () -> Void = {}) {
        self.fileURL = fileURL
        self.lockURL = fileURL.deletingPathExtension().appendingPathExtension("lock")
        self.didSave = didSave
    }

    /// Repository backed by the App Group container named in `Info.plist` (`StickyAppGroupID`).
    /// The default `didSave` reloads all widget timelines.
    public static func shared(
        appGroupID: String? = AppGroup.identifier,
        didSave: @escaping @Sendable () -> Void = { WidgetReloader.reloadAll() }
    ) throws -> NotesRepository {
        NotesRepository(fileURL: try AppGroup.storeURL(appGroupID: appGroupID), didSave: didSave)
    }

    /// Lock-free read. Missing or corrupt files yield an empty store.
    public func load() -> NotesStore {
        let outcome = StoreCodec.load(from: fileURL)
        if case .corrupt(let reason) = outcome {
            logger.error("Store is corrupt, using empty store: \(reason, privacy: .public)")
        }
        return outcome.store
    }

    /// Replaces the whole store (under the lock).
    public func save(_ store: NotesStore) async throws {
        _ = try await update { $0 = store }
    }

    /// Read-modify-write under an exclusive cross-process lock.
    /// The body always sees the latest version on disk. If it throws, nothing is written.
    @discardableResult
    public func update<T: Sendable>(
        _ body: @Sendable (inout NotesStore) throws -> T
    ) async throws -> (store: NotesStore, result: T) {
        try ensureDirectory()
        let lock = try await FileLock.acquire(at: lockURL)
        defer { lock.unlock() }

        var store: NotesStore
        var fileExists = true
        switch StoreCodec.load(from: fileURL) {
        case .loaded(let current):
            store = current
        case .missing:
            store = .empty
            fileExists = false
        case .corrupt(let reason):
            // Never silently overwrite unreadable user data: keep a copy aside first.
            logger.error("Store is corrupt, backing it up: \(reason, privacy: .public)")
            backUpCorruptFile()
            store = .empty
            fileExists = false
        }

        let original = store
        let result = try body(&store)
        // Skip no-op writes (e.g. an idempotent retry) to avoid needless widget reloads.
        guard store != original || !fileExists else { return (store, result) }
        try write(store)
        didSave()
        return (store, result)
    }

    // MARK: Private

    private func write(_ store: NotesStore) throws {
        let data: Data
        do {
            data = try StoreCodec.encode(store)
        } catch {
            throw RepositoryError.encodingFailed(String(describing: error))
        }
        do {
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            throw RepositoryError.writeFailed(error.localizedDescription)
        }
    }

    private func ensureDirectory() throws {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw RepositoryError.writeFailed(error.localizedDescription)
        }
    }

    private func backUpCorruptFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: backup)
        } catch {
            logger.error("Could not back up corrupt store: \(error.localizedDescription, privacy: .public)")
        }
    }
}

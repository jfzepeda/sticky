import Foundation

/// Encoding/decoding of `NotesStore` to bytes, plus a synchronous, lock-free reader
/// (the file is always replaced atomically, so readers never see a partial write).
public enum StoreCodec {
    /// Upper bound for the file we are willing to parse; anything larger is treated as corrupt.
    public static let maxFileSize = 8 * 1024 * 1024

    public enum LoadOutcome: Sendable {
        case loaded(NotesStore)
        case missing
        case corrupt(String)

        public var store: NotesStore {
            if case .loaded(let store) = self { return store }
            return .empty
        }
    }

    public static func encode(_ store: NotesStore) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(store)
    }

    public static func decode(_ data: Data) throws -> NotesStore {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NotesStore.self, from: data)
    }

    /// Reads the store at `url`. Never throws: a missing or unreadable file yields an outcome
    /// whose `store` is empty.
    public static func load(from url: URL) -> LoadOutcome {
        let data: Data
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.intValue > maxFileSize {
                return .corrupt("El archivo supera \(maxFileSize) bytes")
            }
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .missing
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) { return .missing }
            return .corrupt(error.localizedDescription)
        }
        do {
            return .loaded(try decode(data))
        } catch {
            return .corrupt(String(describing: error))
        }
    }

    /// Convenience used by the widget: always returns a store, empty on any problem.
    public static func loadStore(from url: URL) -> NotesStore {
        load(from: url).store
    }
}

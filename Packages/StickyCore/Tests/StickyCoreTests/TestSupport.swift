import Foundation
@testable import StickyCore

/// A unique temporary directory per test, removed on deinit.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StickyCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var storeURL: URL { url.appendingPathComponent("StickyDesk/notes.json") }

    deinit { try? FileManager.default.removeItem(at: url) }
}

func reminder(_ id: String, _ title: String, list: String = "L1", listName: String = "Trabajo",
              color: RGBA = RGBA(r: 1, g: 0, b: 0)) -> ImportedReminder {
    ImportedReminder(id: id, title: title, listID: list, listName: listName, listColor: color)
}

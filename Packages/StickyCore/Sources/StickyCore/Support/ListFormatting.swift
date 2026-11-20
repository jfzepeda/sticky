import Foundation

/// Plain-text list editing for notes: "- " starts a bullet list ("• "), "1 " starts a
/// numbered list ("1. "), Return continues the list and Return on an empty item ends it.
/// Lists are stored as plain text, so the widget and MCP need no special rendering.
public enum ListFormatting {
    public static let bullet = "• "

    /// A list marker at the start of a line (after optional indentation).
    public enum Marker: Equatable, Sendable {
        case bullet
        case number(Int)

        var text: String {
            switch self {
            case .bullet: ListFormatting.bullet
            case .number(let n): "\(n). "
            }
        }

        var next: Marker {
            switch self {
            case .bullet: .bullet
            case .number(let n): .number(n + 1)
            }
        }
    }

    /// What Return should do at the end of a line.
    public enum NewlineAction: Equatable, Sendable {
        /// Not a list line: insert a plain newline.
        case plain
        /// Insert this text (newline + indentation + next marker).
        case insert(String)
        /// The item is empty: drop the marker (its UTF-16 length from the line start), ending the list.
        case endList(markerLength: Int)
    }

    /// Called when the user types a space. `linePrefix` is the current line up to the cursor,
    /// *without* the space being typed. Returns the replacement for the whole prefix (including
    /// the space), or `nil` to insert the space normally.
    public static func replacementOnSpace(linePrefix: String) -> String? {
        let indent = String(linePrefix.prefix { $0 == " " })
        let token = linePrefix.dropFirst(indent.count)
        switch token {
        case "-", "*": return indent + bullet
        case "1": return indent + "1. "
        default: return nil
        }
    }

    /// Called on Return. `line` is the current line up to the cursor.
    public static func newlineAction(line: String) -> NewlineAction {
        guard let (indent, marker, content) = parse(line) else { return .plain }
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            return .endList(markerLength: (indent + marker.text).utf16.count)
        }
        return .insert("\n" + indent + marker.next.text)
    }

    /// Drops trailing lines that are only a list marker (left behind when saving mid-list).
    public static func trimmingEmptyTrailingItems(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last,
              last.trimmingCharacters(in: .whitespaces).isEmpty
                || parse(last).map({ $0.content.trimmingCharacters(in: .whitespaces).isEmpty }) == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// Splits a line into indentation, marker and content. Recognizes "• ", "- ", "* " and "N. ".
    static func parse(_ line: String) -> (indent: String, marker: Marker, content: Substring)? {
        let indent = String(line.prefix { $0 == " " })
        let rest = line.dropFirst(indent.count)
        for prefix in [bullet, "- ", "* "] where rest.hasPrefix(prefix) {
            // "- " lines (pasted or from agents) continue as "• ".
            return (indent, .bullet, rest.dropFirst(prefix.count))
        }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 4, let n = Int(digits) else { return nil }
        let afterDigits = rest.dropFirst(digits.count)
        guard afterDigits.hasPrefix(". ") else { return nil }
        return (indent, .number(n), afterDigits.dropFirst(2))
    }
}

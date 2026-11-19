import Foundation

/// Normalizes untrusted text before it reaches the store.
public enum TextSanitizer {
    /// - Removes control (Cc) and format (Cf) characters — including bidi overrides
    ///   and zero-width characters — except `\n` when `allowNewlines` is true.
    /// - Normalizes `\r\n` / `\r` to `\n`, tabs to spaces, and trims surrounding whitespace.
    /// - Collapses runs of more than two blank lines.
    public static func sanitize(_ input: String, allowNewlines: Bool) -> String {
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: " ")

        var scalars = String.UnicodeScalarView()
        for scalar in normalized.unicodeScalars {
            if scalar == "\n" {
                scalars.append(allowNewlines ? scalar : " ")
                continue
            }
            // Keep ZERO WIDTH JOINER so emoji sequences (👩‍💻) survive.
            if scalar.value == 0x200D {
                scalars.append(scalar)
                continue
            }
            switch scalar.properties.generalCategory {
            case .control, .format, .surrogate, .privateUse, .unassigned,
                 .lineSeparator, .paragraphSeparator:
                continue
            default:
                scalars.append(scalar)
            }
        }

        var result = String(scalars)
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

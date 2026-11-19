import Foundation

/// Fixed palette for projects created without an explicit color (e.g. by agents).
/// Selection is deterministic: it depends only on how many projects already exist.
public enum Palette {
    public static let colors: [RGBA] = [
        RGBA(hex: "#F6C445") ?? .vanilla,  // amber
        RGBA(hex: "#5AC8FA") ?? .vanilla,  // sky
        RGBA(hex: "#34C759") ?? .vanilla,  // green
        RGBA(hex: "#FF9F0A") ?? .vanilla,  // orange
        RGBA(hex: "#AF52DE") ?? .vanilla,  // purple
        RGBA(hex: "#FF6482") ?? .vanilla,  // pink
        RGBA(hex: "#64D2FF") ?? .vanilla,  // cyan
        RGBA(hex: "#A2845E") ?? .vanilla,  // brown
    ]

    public static func color(forProjectIndex index: Int) -> RGBA {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}

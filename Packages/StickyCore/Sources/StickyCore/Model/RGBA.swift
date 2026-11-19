import AppKit
import CoreGraphics
import SwiftUI

/// A color stored as sRGB components in `0...1`. Codable so it can live in the shared JSON store.
public struct RGBA: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = Self.clamp(r)
        self.g = Self.clamp(g)
        self.b = Self.clamp(b)
        self.a = Self.clamp(a)
    }

    /// Classic post-it vanilla, ≈ #F3E5AB.
    public static let vanilla = RGBA(r: 243 / 255, g: 229 / 255, b: 171 / 255)

    /// Converts any `CGColor` to sRGB. Returns `nil` if the color space can't be converted (e.g. patterns).
    public init?(cgColor: CGColor) {
        guard
            let srgb = CGColorSpace(name: CGColorSpace.sRGB),
            let converted = cgColor.converted(to: srgb, intent: .defaultIntent, options: nil),
            let c = converted.components, c.count >= 3
        else { return nil }
        self.init(r: Double(c[0]), g: Double(c[1]), b: Double(c[2]), a: Double(c.count >= 4 ? c[3] : 1))
    }

    /// Converts a SwiftUI `Color` through `NSColor` into sRGB.
    public init?(color: Color) {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(
            r: Double(ns.redComponent),
            g: Double(ns.greenComponent),
            b: Double(ns.blueComponent),
            a: Double(ns.alphaComponent)
        )
    }

    /// Parses `#RRGGBB` or `RRGGBB`.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            r: Double((value >> 16) & 0xFF) / 255,
            g: Double((value >> 8) & 0xFF) / 255,
            b: Double(value & 0xFF) / 255
        )
    }

    /// `#RRGGBB` (alpha ignored).
    public var hexString: String {
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    /// Linear blend towards `other`. `amount` 0 = self, 1 = other.
    public func mixed(with other: RGBA, amount: Double) -> RGBA {
        let t = Self.clamp(amount)
        return RGBA(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t,
            a: a + (other.a - a) * t
        )
    }

    public static let white = RGBA(r: 1, g: 1, b: 1)
    public static let black = RGBA(r: 0, g: 0, b: 0)

    /// The color as-is.
    public var solid: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    /// Project color softened for paper: 55% blend with white.
    public var postItRGBA: RGBA { mixed(with: .white, amount: 0.55) }
    public var postItColor: Color { postItRGBA.solid }

    // MARK: Codable (clamp untrusted values from disk)

    private enum CodingKeys: String, CodingKey { case r, g, b, a }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            r: try c.decode(Double.self, forKey: .r),
            g: try c.decode(Double.self, forKey: .g),
            b: try c.decode(Double.self, forKey: .b),
            a: try c.decodeIfPresent(Double.self, forKey: .a) ?? 1
        )
    }

    private static func clamp(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(max(v, 0), 1)
    }
}

import SwiftUI
import WidgetKit

/// Empty state: a small white notebook sheet hanging from a spiral binding,
/// with a torn bottom edge. Static, deterministic, no animation.
struct NotebookSheetView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let width = min(side * 0.62, 150)
            let height = width * 1.05
            let ringCount = max(4, Int(width / 16))

            ZStack(alignment: .top) {
                TornPaper(toothWidth: 7, depth: 4)
                    .fill(Color.white)
                    .overlay {
                        TornPaper(toothWidth: 7, depth: 4)
                            .stroke(Color.black.opacity(renderingMode == .accented ? 0.5 : 0.08), lineWidth: 0.5)
                    }
                    .overlay(alignment: .top) {
                        SheetHoles(count: ringCount, inset: 7, diameter: 4.5)
                            .fill(Color.black.opacity(0.12))
                            .frame(height: 12)
                    }
                    .overlay {
                        Text("Sin notas")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }

                SpiralRings(count: ringCount, inset: 7)
                    .stroke(
                        LinearGradient(
                            colors: [Color(white: 0.92), Color(white: 0.55), Color(white: 0.8), Color(white: 0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                    )
                    .frame(height: 18)
                    .offset(y: -9)
            }
            .frame(width: width, height: height)
            .compositingGroup()
            .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
            .rotationEffect(.degrees(-2))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 6)
        }
        .accessibilityLabel("Sin notas")
    }
}

/// Rectangle with a deterministic zigzag ("torn") bottom edge.
struct TornPaper: Shape {
    var toothWidth: CGFloat
    var depth: CGFloat

    /// Fixed pattern of relative tooth depths so every render is identical.
    private static let pattern: [CGFloat] = [1.0, 0.55, 0.85, 0.4, 0.95, 0.6, 0.75, 0.35, 0.9, 0.5]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.maxY - depth
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: baseline))

        let teeth = max(1, Int((rect.width / toothWidth).rounded()))
        let step = rect.width / CGFloat(teeth)
        for i in 0..<teeth {
            let xRight = rect.maxX - CGFloat(i) * step
            let tip = CGPoint(x: xRight - step / 2, y: baseline + depth * Self.pattern[i % Self.pattern.count])
            let next = CGPoint(x: xRight - step, y: baseline - depth * 0.25 * Self.pattern[(i + 3) % Self.pattern.count])
            path.addLine(to: tip)
            path.addLine(to: next)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: baseline))
        path.closeSubpath()
        return path
    }
}

/// Metal spiral loops crossing the sheet's top edge.
struct SpiralRings: Shape {
    var count: Int
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard count > 0 else { return path }
        let usable = rect.width - inset * 2
        let step = count > 1 ? usable / CGFloat(count - 1) : 0
        let loopWidth: CGFloat = 3.2
        for i in 0..<count {
            let x = rect.minX + inset + CGFloat(i) * step
            let loop = CGRect(x: x - loopWidth / 2, y: rect.minY, width: loopWidth, height: rect.height)
            path.addRoundedRect(in: loop, cornerSize: CGSize(width: loopWidth / 2, height: loopWidth / 2))
        }
        return path
    }
}

/// Faint punched holes where the rings pass through the paper.
struct SheetHoles: Shape {
    var count: Int
    var inset: CGFloat
    var diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard count > 0 else { return path }
        let usable = rect.width - inset * 2
        let step = count > 1 ? usable / CGFloat(count - 1) : 0
        for i in 0..<count {
            let x = rect.minX + inset + CGFloat(i) * step
            path.addEllipse(in: CGRect(x: x - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter))
        }
        return path
    }
}

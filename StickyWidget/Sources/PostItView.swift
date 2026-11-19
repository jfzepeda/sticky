import StickyCore
import SwiftUI
import WidgetKit

/// A square post-it. Vanilla by default, or the project's color softened for paper.
struct PostItView: View {
    let note: Note
    let project: Project?

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var paper: RGBA { project?.color.postItRGBA ?? .vanilla }

    var body: some View {
        ZStack {
            // Paper with a subtle vertical gradient.
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            paper.mixed(with: .white, amount: 0.18).solid,
                            paper.solid,
                            paper.mixed(with: .black, amount: 0.04).solid,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 0) {
                // Adhesive band.
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: 12)

                Text(note.text)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, project == nil ? 8 : 18)
            }

            if let project {
                Text(project.name.uppercased())
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(Color.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 80, alignment: .trailing)
                    .padding(.trailing, 6)
                    .padding(.bottom, 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .overlay {
            if renderingMode == .accented {
                // Tinted modes flatten colors; a hairline keeps notes distinguishable.
                Rectangle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 0.75)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 2)
        .rotationEffect(.degrees(note.tilt))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(project.map { "\(note.text). Proyecto \($0.name)" } ?? note.text)
    }
}

import AppIntents
import StickyCore
import SwiftUI
import WidgetKit

/// Post-its are 9:8 (a bit wider than tall) so the header row above the grid doesn't
/// squeeze them.
enum PostItMetrics {
    static let aspectRatio: CGFloat = 9.0 / 8.0
    static let bandHeight: CGFloat = 16
}

/// The paper itself: gradient, adhesive band, text and project label. Flexible size, no
/// rotation or shadow (callers add those so overlays rotate with it).
struct PostItPaper: View {
    let note: Note
    let project: Project?

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var paper: RGBA { project?.color.postItRGBA ?? .vanilla }

    var body: some View {
        ZStack {
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
                // Adhesive band; the completion check sits on it.
                Rectangle()
                    .fill(Color.black.opacity(0.05))
                    .frame(height: PostItMetrics.bandHeight)

                Text(note.text)
                    .font(.system(size: 13, design: .rounded))
                    .strikethrough(note.isCompleted, color: .black.opacity(0.45))
                    .foregroundStyle(Color.black.opacity(note.isCompleted ? 0.4 : 0.82))
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, project == nil ? 6 : 16)
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
    }
}

/// A tilted post-it with a completion check in its top-right corner. The paper and the
/// check are sibling controls (never nested), so tapping the check only toggles it.
struct PostItView: View {
    enum Tap {
        case none
        case link(URL)
        case openStack(OpenStackIntent)
    }

    let note: Note
    let project: Project?
    var tap: Tap = .none

    var body: some View {
        ZStack(alignment: .topTrailing) {
            paper
            Button(intent: ToggleNoteCompletedIntent(noteID: note.id.uuidString)) {
                CompletionCheck(isCompleted: note.isCompleted)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .padding(.trailing, 3)
            .accessibilityLabel(note.isCompleted ? "Marcar como pendiente" : "Marcar como completada")
        }
        .aspectRatio(PostItMetrics.aspectRatio, contentMode: .fit)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 2)
        .rotationEffect(.degrees(note.tilt))
    }

    @ViewBuilder
    private var paper: some View {
        let content = PostItPaper(note: note, project: project)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        switch tap {
        case .none:
            content
        case .link(let url):
            Link(destination: url) { content }
        case .openStack(let intent):
            Button(intent: intent) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Abre el proyecto")
        }
    }

    private var accessibilityText: String {
        var parts = [note.text]
        if let project { parts.append("Proyecto \(project.name)") }
        if note.isCompleted { parts.append("Completada") }
        return parts.joined(separator: ". ")
    }
}

/// The checkmark ("palomita") on the band: outlined when pending, filled green when done.
struct CompletionCheck: View {
    let isCompleted: Bool

    var body: some View {
        Image(systemName: isCompleted ? "checkmark.circle.fill" : "checkmark.circle")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isCompleted ? Color.green : Color.black.opacity(0.35))
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
    }
}

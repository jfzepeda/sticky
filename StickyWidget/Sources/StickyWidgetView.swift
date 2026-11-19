import StickyCore
import SwiftUI
import WidgetKit

struct StickyWidgetView: View {
    let entry: StickyEntry
    @Environment(\.widgetFamily) private var family

    /// Outer padding so rotation and shadow are never clipped by the widget bounds.
    private let outerPadding: CGFloat = 12
    private let spacing: CGFloat = 10

    var body: some View {
        let notes = entry.notes(limit: capacity)
        Group {
            if notes.isEmpty {
                NotebookSheetView()
            } else {
                content(for: notes)
            }
        }
        .padding(outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var capacity: Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 3
        case .systemLarge: 6
        default: 1
        }
    }

    @ViewBuilder
    private func content(for notes: [Note]) -> some View {
        switch family {
        case .systemMedium:
            HStack(spacing: spacing) {
                ForEach(notes) { note in linked(note) }
            }
        case .systemLarge:
            Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
                ForEach(Array(stride(from: 0, to: notes.count, by: 2)), id: \.self) { start in
                    GridRow {
                        linked(notes[start])
                        if start + 1 < notes.count {
                            linked(notes[start + 1])
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
        default:
            // Small: a single note; the whole widget opens it.
            if let note = notes.first {
                PostItView(note: note, project: entry.store.project(for: note))
                    .widgetURL(DeepLink.noteURL(for: note.id))
            }
        }
    }

    private func linked(_ note: Note) -> some View {
        Link(destination: DeepLink.noteURL(for: note.id)) {
            PostItView(note: note, project: entry.store.project(for: note))
        }
    }
}

#Preview("Small", as: .systemSmall) {
    StickyWidget()
} timeline: {
    StickyEntry(date: .now, store: .sample)
    StickyEntry(date: .now, store: .empty)
}

#Preview("Medium", as: .systemMedium) {
    StickyWidget()
} timeline: {
    StickyEntry(date: .now, store: .sample)
}

#Preview("Large", as: .systemLarge) {
    StickyWidget()
} timeline: {
    StickyEntry(date: .now, store: .sample)
    StickyEntry(date: .now, store: .empty)
}

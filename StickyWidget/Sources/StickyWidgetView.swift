import AppIntents
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
        let presentation = WidgetPresentation(
            store: entry.store,
            state: entry.browse[stateKey],
            slotCount: family.slotCount,
            pinnedProjectID: entry.pinnedProjectID
        )
        Group {
            switch presentation {
            case .empty:
                NotebookSheetView()
            case .overview(let groups):
                overview(groups)
            case .group(let group, let notes):
                opened(group, notes, canClose: true)
            case .pinned(let group, let notes):
                opened(group, notes, canClose: false)
            }
        }
        .padding(outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Pinned widgets keep their page apart from the "all projects" widgets of that size.
    private var stateKey: String {
        WidgetBrowseState.key(family: family.browseKey, pinnedProjectID: entry.pinnedProjectID)
    }

    // MARK: Overview: one stack per project

    @ViewBuilder
    private func overview(_ groups: Paged<NoteGroup>) -> some View {
        VStack(spacing: 6) {
            if groups.pageCount > 1 {
                HStack {
                    Spacer()
                    pager(groups, inGroup: false)
                }
            }
            SlotGrid(items: groups.items, slotCount: family.slotCount, spacing: spacing) { group in
                Button(intent: OpenStackIntent(groupID: group.id, family: stateKey)) {
                    NoteStackView(group: group)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Opened stack: that project's notes

    @ViewBuilder
    private func opened(_ group: NoteGroup, _ notes: Paged<Note>, canClose: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if canClose {
                    Button(intent: CloseStackIntent(family: stateKey)) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                            groupTitle(group)
                        }
                        .chip()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Volver a los proyectos")
                } else {
                    // Configured for this project: nothing to go back to.
                    HStack(spacing: 3) { groupTitle(group) }.chip()
                }
                Spacer(minLength: 0)
                if notes.pageCount > 1 {
                    pager(notes, inGroup: true)
                }
            }
            SlotGrid(items: notes.items, slotCount: family.slotCount, spacing: spacing) { note in
                if family == .systemSmall {
                    // Small widgets open via widgetURL; the header buttons still win their taps.
                    PostItView(note: note, project: group.project)
                } else {
                    Link(destination: DeepLink.noteURL(for: note.id)) {
                        PostItView(note: note, project: group.project)
                    }
                }
            }
        }
        .widgetURL(family == .systemSmall ? notes.items.first.map { DeepLink.noteURL(for: $0.id) } : nil)
    }

    @ViewBuilder
    private func groupTitle(_ group: NoteGroup) -> some View {
        ProjectSwatchDot(color: group.project?.color)
        Text(group.project?.name ?? "Sin proyecto").lineLimit(1)
        Text("· \(group.notes.count)").foregroundStyle(.white.opacity(0.7))
    }

    private func pager<Item>(_ paged: Paged<Item>, inGroup: Bool) -> some View {
        HStack(spacing: 2) {
            pageButton("chevron.left", page: paged.page - 1, inGroup: inGroup,
                       enabled: paged.hasPrevious, label: "Página anterior")
            Text("\(paged.page + 1)/\(paged.pageCount)").monospacedDigit()
            pageButton("chevron.right", page: paged.page + 1, inGroup: inGroup,
                       enabled: paged.hasNext, label: "Página siguiente")
        }
        .chip()
    }

    @ViewBuilder
    private func pageButton(_ symbol: String, page: Int, inGroup: Bool, enabled: Bool, label: String) -> some View {
        let image = Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
        if enabled {
            Button(intent: ShowPageIntent(family: stateKey, page: page, inGroup: inGroup)) { image }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
        } else {
            image.opacity(0.3).accessibilityHidden(true)
        }
    }
}

/// Lays out exactly `slotCount` square slots (1, 1×2 or 2×2). Slots without an item are
/// drawn as dashed outlines so the widget always shows its full capacity.
private struct SlotGrid<Item, Cell: View>: View {
    let items: [Item]
    let slotCount: Int
    let spacing: CGFloat
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        let columns = slotCount >= 4 ? 2 : max(1, slotCount)
        let rows = (slotCount + columns - 1) / columns
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        slot(row * columns + column)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        if index < items.count {
            cell(items[index])
        } else {
            EmptySlotView()
        }
    }
}

/// Dashed outline where a note would go.
private struct EmptySlotView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .strokeBorder(
                Color.primary.opacity(renderingMode == .fullColor ? 0.35 : 0.6),
                style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
            )
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// A project's newest note on top of a couple of offset sheets, with a count badge.
private struct NoteStackView: View {
    let group: NoteGroup

    var body: some View {
        if let top = group.newest {
            let paper = group.project?.color.postItRGBA ?? .vanilla
            let count = group.notes.count
            ZStack {
                if count > 2 { sheet(paper, rotation: top.tilt + 5, x: 4, y: 3) }
                if count > 1 { sheet(paper, rotation: top.tilt - 3.5, x: -3, y: 2) }
                PostItView(note: top, project: group.project)
            }
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .offset(x: 5, y: -5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(group.project?.name ?? "Sin proyecto"), \(count) \(count == 1 ? "nota" : "notas"). "
                    + "Última: \(top.text)"
            )
            .accessibilityHint("Abre el proyecto")
        }
    }

    private func sheet(_ paper: RGBA, rotation: Double, x: CGFloat, y: CGFloat) -> some View {
        Rectangle()
            .fill(paper.mixed(with: .black, amount: 0.07).solid)
            .aspectRatio(1, contentMode: .fit)
            .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: y)
    }
}

private struct ProjectSwatchDot: View {
    let color: RGBA?
    var body: some View {
        Circle()
            .fill((color?.postItRGBA ?? .vanilla).solid)
            .frame(width: 7, height: 7)
    }
}

private extension View {
    /// Small dark capsule so header controls stay legible over any wallpaper.
    func chip() -> some View {
        font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.55)))
    }
}

extension WidgetFamily {
    /// 1 / 2 / 4 notes or stacks.
    var slotCount: Int {
        switch self {
        case .systemMedium: 2
        case .systemLarge: 4
        default: 1
        }
    }

    /// Key into `WidgetBrowseState`; each size remembers what it has open.
    var browseKey: String {
        switch self {
        case .systemMedium: "medium"
        case .systemLarge: "large"
        default: "small"
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
    StickyEntry(date: .now, store: .sample, pinnedProjectID: NotesStore.sample.projects.first?.id)
}

#Preview("Large", as: .systemLarge) {
    StickyWidget()
} timeline: {
    StickyEntry(date: .now, store: .sample)
    StickyEntry(date: .now, store: .empty)
}

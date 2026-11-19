import StickyCore
import SwiftUI
import WidgetKit

@main
struct StickyWidgetBundle: WidgetBundle {
    var body: some Widget {
        StickyWidget()
    }
}

struct StickyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetReloader.widgetKind, provider: StickyProvider()) { entry in
            StickyWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("StickyDesk")
        .description("Tus notas como post-its en el escritorio.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

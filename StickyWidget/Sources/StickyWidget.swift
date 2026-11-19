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
        AppIntentConfiguration(
            kind: WidgetReloader.widgetKind,
            intent: StickyConfigurationIntent.self,
            provider: StickyProvider()
        ) { entry in
            StickyWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("StickyDesk")
        .description("Tus notas como post-its, agrupadas por proyecto. Edita el widget para mostrar solo un proyecto.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

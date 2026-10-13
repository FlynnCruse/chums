import WidgetKit
import SwiftUI

/// Chums on the watch face and in the Smart Stack: its mark, and one tap opens Chums. It's there for the moments Chums
/// isn't in front: after a crown press, or after the watch restarts (an app can't start itself).
@main
struct ChumsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "chums", provider: Provider()) { _ in ChumsWidgetView() }
            .configurationDisplayName("Chums")
            .description("Opens Chums, where you talk to your coding agents.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

struct Entry: TimelineEntry { let date: Date }

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

struct ChumsWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    ChumsMark().frame(width: 40, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Chums").font(.headline)
                        Text("Open").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            case .accessoryInline:
                Text("Chums")
            case .accessoryCorner:
                ChumsMark().padding(6)
            default:
                ChumsMark().padding(9)
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }
}

/// The Chums mark: two eyes on black, like Peeps.
struct ChumsMark: View {
    var body: some View {
        Canvas { ctx, size in
            let h = min(size.height * 0.8, size.width * 0.5), w = h * 0.62, gap = w * 0.7
            for dx: CGFloat in [-1, 1] {
                let r = CGRect(x: size.width / 2 + dx * (gap + w) / 2 - w / 2, y: (size.height - h) / 2, width: w, height: h)
                ctx.fill(Path(roundedRect: r, cornerRadius: w / 2), with: .color(.white))
            }
        }
        .widgetAccentable()
    }
}

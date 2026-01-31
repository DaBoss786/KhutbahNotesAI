import SwiftUI
import WidgetKit

private struct DailyAyahEntry: TimelineEntry {
    let date: Date
    let ayah: DailyAyah
    let isJummahWindow: Bool
    let widgetURL: URL
}

private struct DailyAyahTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyAyahEntry {
        let sampleTarget = QuranCitationTarget(surahId: 2, ayah: 255)
        let sampleAyah = DailyAyah(
            target: sampleTarget,
            surahName: "Al-Baqarah",
            arabicText: "",
            translationText: "Allah! There is no deity except Him, the Ever-Living, the Sustainer of existence."
        )
        return DailyAyahEntry(
            date: Date(),
            ayah: sampleAyah,
            isJummahWindow: false,
            widgetURL: QuranDeepLink.url(for: sampleTarget)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyAyahEntry) -> Void) {
        completion(makeEntry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyAyahEntry>) -> Void) {
        let now = Date()
        let entry = makeEntry(for: now)
        let nextRefresh = DailyAyahProvider.nextRefreshDate(after: now, cadence: .daily)
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    private func makeEntry(for date: Date) -> DailyAyahEntry {
        let ayah = DailyAyahProvider.dailyAyah(on: date, bundle: .main)
        let isJummahWindow = DailyAyahProvider.isJummahWindow(on: date)
        let widgetURL = isJummahWindow
            ? RecordingDeepLink.url(for: .openRecording)
            : QuranDeepLink.url(for: ayah.target)
        return DailyAyahEntry(
            date: date,
            ayah: ayah,
            isJummahWindow: isJummahWindow,
            widgetURL: widgetURL
        )
    }
}

private struct DailyAyahWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyAyahEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                inlineView
            default:
                rectangularView
            }
        }
        .widgetURL(entry.widgetURL)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if entry.isJummahWindow {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                    Text("Jummah Mubarak")
                        .font(.caption.bold())
                }
                .foregroundStyle(.primary)
                Text("Tap to record")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(translationText)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .minimumScaleFactor(0.9)
                Text(entry.ayah.displayReferenceText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var inlineView: some View {
        if entry.isJummahWindow {
            Label("Jummah Mubarak", systemImage: "mic.fill")
        } else {
            Text("\(entry.ayah.displayReferenceText) \(inlineSnippet)")
                .lineLimit(1)
        }
    }

    private var translationText: String {
        let trimmed = entry.ayah.translationText?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? entry.ayah.referenceText : trimmed
    }

    private var inlineSnippet: String {
        let text = translationText
        guard text.count > 40 else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: 40)
        return "\(text[..<endIndex])…"
    }
}

struct DailyAyahWidget: Widget {
    private let kind = "DailyAyahWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyAyahTimelineProvider()) { entry in
            DailyAyahWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Daily Ayah")
        .description("A daily verse that becomes a Jummah recorder on Fridays.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .accessoryRectangular) {
    DailyAyahWidget()
} timeline: {
    let target = QuranCitationTarget(surahId: 18, ayah: 10)
    DailyAyahEntry(
        date: .now,
        ayah: DailyAyah(
            target: target,
            surahName: "Al-Kahf",
            arabicText: "",
            translationText: "Our Lord, grant us mercy from Yourself and guide us to a right course."
        ),
        isJummahWindow: false,
        widgetURL: QuranDeepLink.url(for: target)
    )
}

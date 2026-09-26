import AppIntents
import SwiftUI
import WidgetKit

struct UnlockGateIntent: AppIntent {
    static var title: LocalizedStringResource = "Unlock gate"
    static var description = IntentDescription("Send an unlock command to your LockLink gate on the same Wi-Fi.")
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ProvidesDialog {
        GateWidgetStore.setResult("Sending unlock request…")
        let message = await GateWidgetClient.shared.unlock()
        GateWidgetStore.setResult(message)
        WidgetCenter.shared.reloadTimelines(ofKind: GateWidgetStore.kind)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct GateEntry: TimelineEntry {
    let date: Date
    let configured: Bool
    let message: String
    let resultDate: Date?
}

struct GateProvider: TimelineProvider {
    func placeholder(in context: Context) -> GateEntry {
        GateEntry(date: Date(), configured: true, message: "Same Wi-Fi as your gate", resultDate: nil)
    }
    private func entry() -> GateEntry {
        let defaults = GateWidgetStore.defaults
        let timestamp = defaults?.double(forKey: "resultDate") ?? 0
        return GateEntry(date: Date(), configured: defaults?.bool(forKey: "configured") ?? false,
            message: defaults?.string(forKey: "result") ?? "Same Wi-Fi as your gate",
            resultDate: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (GateEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GateEntry>) -> Void) {
        // Timeline refreshes never send device commands or perform background polling.
        completion(Timeline(entries: [entry()], policy: .never))
    }
}

struct GateWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: GateEntry

    var body: some View {
        Group {
            if family == .accessoryCircular {
                Button(intent: UnlockGateIntent()) {
                    Image(systemName: "lock.open.fill").font(.title2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(!entry.configured)
                .accessibilityLabel("Unlock gate")
                .accessibilityHint(entry.configured ? "Sends a command on your local Wi-Fi" : "Open LockLink to set up widgets")
            } else if family == .accessoryRectangular {
                Button(intent: UnlockGateIntent()) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Unlock gate", systemImage: "lock.open.fill").font(.headline)
                        Text(entry.configured ? (entry.resultDate == nil ? entry.message : "Last: \(entry.message)") : "Set up in LockLink")
                            .font(.caption2).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain).disabled(!entry.configured)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("LockLink", systemImage: "door.left.hand.closed").font(.headline)
                    Text(entry.configured ? entry.message : "Open LockLink to set up widgets.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    if let resultDate = entry.resultDate {
                        Text(resultDate, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(intent: UnlockGateIntent()) {
                        Label("Unlock gate", systemImage: "lock.open.fill")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 32)
                            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(colorScheme == .dark ? Color.white : Color.black)
                    .disabled(!entry.configured)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@main
struct LockLinkWidgets: Widget {
    let kind = GateWidgetStore.kind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GateProvider()) { GateWidgetView(entry: $0) }
            .configurationDisplayName("Unlock gate")
            .description("Unlock your gate on the same Wi-Fi without opening LockLink.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

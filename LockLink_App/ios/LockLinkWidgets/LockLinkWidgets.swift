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
    func getSnapshot(in context: Context, completion: @escaping (GateEntry) -> Void) { completion(context.isPreview ? placeholder(in: context) : entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GateEntry>) -> Void) {
        // Timeline refreshes never send device commands or perform background polling.
        completion(Timeline(entries: [entry()], policy: .never))
    }
}

struct GateWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: GateEntry

    private var surface: Color { colorScheme == .dark
        ? Color(red: 0.125, green: 0.153, blue: 0.133)
        : Color(red: 0.965, green: 0.957, blue: 0.937) }
    private var ink: Color { colorScheme == .dark
        ? Color(red: 0.95, green: 0.95, blue: 0.92)
        : Color(red: 0.133, green: 0.157, blue: 0.137) }
    private var hint: String { entry.configured
        ? "Sends an unlock command on your local Wi-Fi. Last result: \(entry.message)"
        : "Open LockLink to set up widgets." }
    private var shortResult: String {
        guard entry.configured else { return "Set up in app" }
        guard entry.resultDate != nil else { return "Same Wi-Fi" }
        if entry.message.contains("accepted") { return "Last: Sent" }
        if entry.message.contains("Sending") { return "Sending…" }
        if entry.message.contains("No confirmation") || entry.message.contains("interrupted") { return "Check gate" }
        if entry.message.contains("offline") || entry.message.contains("Cannot reach") { return "Offline" }
        if entry.message.contains("already unlocking") { return "Last: Active" }
        if entry.message.contains("Pairing") { return "Pairing key" }
        if entry.message.contains("not armed") { return "Not armed" }
        if entry.message.contains("expired") { return "Tap again" }
        return "Check app"
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Button(intent: UnlockGateIntent()) {
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 2) {
                            Image(systemName: "lock.open.fill").font(.system(size: 20, weight: .medium))
                            Text("Gate").font(.system(size: 9, weight: .medium))
                        }
                    }
                }
                .buttonStyle(.plain)
            case .accessoryRectangular:
                Button(intent: UnlockGateIntent()) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 34, height: 34)
                            .background(.primary.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unlock gate").font(.headline)
                            Text(shortResult).font(.caption2).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            case .systemSmall:
                GeometryReader { geometry in
                    let side = min(112, min(geometry.size.width, geometry.size.height))
                    Button(intent: UnlockGateIntent()) {
                        VStack(spacing: 5) {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 23, weight: .medium))
                            Text("Unlock gate").font(.system(.subheadline, design: .rounded, weight: .semibold))
                            VStack(spacing: 1) {
                                Text(shortResult).lineLimit(1)
                                if let date = entry.resultDate {
                                    Text(date, style: .time)
                                }
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ink.opacity(0.75))
                        }
                        .frame(width: side, height: side)
                        .foregroundStyle(ink)
                        .background(surface, in: Circle())
                        .overlay(Circle().strokeBorder(ink.opacity(0.15), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            default:
                Button(intent: UnlockGateIntent()) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(surface)
                            .frame(width: 44, height: 44)
                            .background(ink, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Unlock gate").font(.system(.headline, design: .rounded))
                            Text(entry.configured ? entry.message : "Set up in LockLink")
                                .font(.caption).foregroundStyle(ink.opacity(0.75)).lineLimit(2)
                            if let date = entry.resultDate {
                                Text(date, style: .time).font(.caption2).foregroundStyle(ink.opacity(0.65))
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .foregroundStyle(ink)
                    .background(surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(ink.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .disabled(!entry.configured)
        .accessibilityLabel("Unlock gate")
        .accessibilityHint(hint)
        .containerBackground(for: .widget) { Color.clear }
    }
}

@main
struct LockLinkWidgets: Widget {
    let kind = GateWidgetStore.kind
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GateProvider()) { GateWidgetView(entry: $0) }
            .configurationDisplayName("Gate control")
            .description("A circular control or a slim pill. Unlock your gate on the same Wi-Fi.")
            .contentMarginsDisabled()
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

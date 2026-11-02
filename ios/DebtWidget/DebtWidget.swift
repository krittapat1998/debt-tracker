import SwiftUI
import WidgetKit

/// Must match HomeWidgetService.appGroupId in lib/platform/home_widget_service.dart.
private let appGroupId = "group.com.krittapat.debtTracker"

struct DebtEntry: TimelineEntry {
    let date: Date
    let totalDebt: String
    let dueMonth: String
    let nextDueName: String
    let nextDueDate: String
    let nextDueIso: String
    let nextDueAmount: String
    let updatedAt: String

    static let sample = DebtEntry(
        date: Date(),
        totalDebt: "฿125,430.00",
        dueMonth: "฿8,250.00",
        nextDueName: "KTC",
        nextDueDate: "5 พ.ย. 2569",
        nextDueIso: "",
        nextDueAmount: "฿1,523.05",
        updatedAt: ""
    )
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DebtEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (DebtEntry) -> Void) {
        completion(context.isPreview ? .sample : load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DebtEntry>) -> Void) {
        // Re-render just after midnight so the day countdown stays correct.
        let tomorrow = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 + 60)
        completion(Timeline(entries: [load()], policy: .after(tomorrow)))
    }

    private func load() -> DebtEntry {
        let d = UserDefaults(suiteName: appGroupId)
        func s(_ key: String) -> String { d?.string(forKey: key) ?? "" }
        return DebtEntry(
            date: Date(),
            totalDebt: s("total_debt").isEmpty ? "฿0.00" : s("total_debt"),
            dueMonth: s("due_month").isEmpty ? "-" : s("due_month"),
            nextDueName: s("next_due_name").isEmpty ? "เปิดแอพเพื่ออัปเดตข้อมูล" : s("next_due_name"),
            nextDueDate: s("next_due_date"),
            nextDueIso: s("next_due_iso"),
            nextDueAmount: s("next_due_amount"),
            updatedAt: s("updated_at")
        )
    }
}

private func relativeDays(_ iso: String) -> String {
    guard !iso.isEmpty else { return "" }
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    guard let due = f.date(from: iso) else { return "" }
    let cal = Calendar.current
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: due)).day ?? 0
    switch days {
    case 0: return "วันนี้"
    case 1: return "พรุ่งนี้"
    case ..<0: return "เลยมา \(-days) วัน"
    default: return "อีก \(days) วัน"
    }
}

struct DebtWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DebtEntry

    private var detail: String {
        let countdown = relativeDays(entry.nextDueIso)
        // A small widget only fits one short line: the countdown beats the date.
        let when = family == .systemSmall && !countdown.isEmpty ? [countdown] : [entry.nextDueDate, countdown]
        return (when + [entry.nextDueAmount])
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("หนี้รวมทั้งหมด")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
            Text(entry.totalDebt)
                .font(.title3.bold())
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("ต้องจ่ายเดือนนี้ \(entry.dueMonth)")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(height: 1)
                .padding(.vertical, 3)
            Text("ใกล้ครบกำหนด")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
            Text(entry.nextDueName)
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .lineLimit(1)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetBackground(Color(red: 0.008, green: 0.533, blue: 0.820))
    }
}

private extension View {
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(color, for: .widget)
        } else {
            padding().background(color)
        }
    }
}

@main
struct DebtWidget: Widget {
    /// Must match HomeWidgetService.iOSName.
    let kind = "DebtWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DebtWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Debt Tracker")
        .description("ยอดหนี้รวมและบัตรที่ใกล้ครบกำหนดชำระ")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

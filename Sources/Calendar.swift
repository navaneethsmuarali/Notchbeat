// Calendar: today's and tomorrow's events, a countdown for the next meeting, and one-click Join.
import Cocoa
import SwiftUI
import EventKit

struct EventItem: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
    let joinURL: URL?
}

final class CalendarModel: ObservableObject {
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var events: [EventItem] = []
    @Published private(set) var now = Date()
    private let store = EKEventStore()
    private var timer: Timer?

    var authorized: Bool { status == .fullAccess }

    /// The meeting to surface in the small island: starting within 10 minutes, or started under 5 minutes ago.
    var soon: EventItem? {
        events.first { e in
            !e.allDay && e.end > now && e.start.timeIntervalSince(now) < 600 && now.timeIntervalSince(e.start) < 300
        }
    }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.now = Date()
            self?.reload()
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.reload() }
        reload()
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.status = EKEventStore.authorizationStatus(for: .event)
                self?.reload()
            }
        }
    }

    func reload() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard authorized else { events = []; return }
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: Date()))!
        let pred = store.predicateForEvents(withStart: Date().addingTimeInterval(-3600), end: end, calendars: nil)
        events = store.events(matching: pred)
            .filter { $0.endDate > Date() && $0.status != .canceled }
            .sorted {
                // Group by day; within a day, all-day events first, then by start time.
                let d0 = max(cal.startOfDay(for: $0.startDate), cal.startOfDay(for: Date()))
                let d1 = max(cal.startOfDay(for: $1.startDate), cal.startOfDay(for: Date()))
                return (d0, $0.isAllDay ? 0 : 1, $0.startDate) < (d1, $1.isAllDay ? 0 : 1, $1.startDate)
            }
            .prefix(30)
            .map { e in
                EventItem(id: (e.calendarItemIdentifier) + "\(e.startDate.timeIntervalSince1970)",
                          title: e.title ?? "Untitled",
                          start: e.startDate, end: e.endDate, allDay: e.isAllDay,
                          color: Color(cgColor: e.calendar.cgColor),
                          joinURL: Self.meetingURL(e))
            }
        now = Date()
    }

    private static let meetingPattern = try! NSRegularExpression(
        pattern: #"(https?://)?[^\s<>"'/]*\.?(zoom\.us/(j|my|w)/|meet\.google\.com/|teams\.microsoft\.com/l/meetup-join|teams\.live\.com/meet|webex\.com/|whereby\.com/|meet\.jit\.si/|chime\.aws/)[^\s<>"']*"#,
        options: [.caseInsensitive])

    static func meetingURL(_ e: EKEvent) -> URL? {
        for text in [e.url?.absoluteString, e.location, e.notes].compactMap({ $0 }) {
            let r = NSRange(text.startIndex..., in: text)
            if let m = meetingPattern.firstMatch(in: text, range: r), let range = Range(m.range, in: text) {
                let found = String(text[range])
                return URL(string: found.lowercased().hasPrefix("http") ? found : "https://" + found)
            }
        }
        return nil
    }

    func countdown(_ e: EventItem) -> String {
        let s = Int(e.start.timeIntervalSince(now))
        if s <= 0 { return "now" }
        if s < 3600 { return "in \(max(1, s / 60))m" }
        return "in \(s / 3600)h \(s % 3600 / 60)m"
    }
}

struct CalendarView: View {
    @ObservedObject var cal: CalendarModel

    var body: some View {
        if cal.authorized {
            list
        } else {
            VStack(spacing: 8) {
                Image(systemName: "calendar").font(.system(size: 22)).foregroundStyle(.white.opacity(0.6))
                if cal.status == .notDetermined {
                    Text("See your next meetings and join them from here.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    pill("Connect Calendar") { cal.requestAccess() }
                } else {
                    Text("Allow Notchbeat under Privacy & Security → Calendars.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                    pill("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var list: some View {
        Group {
            if cal.events.isEmpty {
                Text("Nothing else on your calendar today or tomorrow.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(cal.events.enumerated()), id: \.element.id) { i, e in
                            if i == 0 || !Calendar.current.isDate(displayDay(cal.events[i - 1]), inSameDayAs: displayDay(e)) {
                                Text(dayLabel(displayDay(e))).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                                    .padding(.top, i == 0 ? 0 : 4)
                            }
                            row(e)
                        }
                    }
                }
            }
        }
    }

    private func row(_ e: EventItem) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(e.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Text(timeLabel(e)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 6)
            if !e.allDay && e.start > cal.now && e.start.timeIntervalSince(cal.now) < 3 * 3600 {
                Text(cal.countdown(e)).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            }
            if let url = e.joinURL {
                pill("Join", color: Color(red: 0.2, green: 0.78, blue: 0.35)) { NSWorkspace.shared.open(url) }
            }
        }
        .frame(height: 32)
    }

    private func pill(_ title: String, color: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.black)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(color))
        }
        .buttonStyle(PressStyle())
    }

    /// Multi-day events that started before today are shown under today.
    private func displayDay(_ e: EventItem) -> Date { max(e.start, Calendar.current.startOfDay(for: Date())) }

    private func dayLabel(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "TODAY" : (Calendar.current.isDateInTomorrow(d) ? "TOMORROW" : d.formatted(.dateTime.weekday(.wide)).uppercased())
    }

    private func timeLabel(_ e: EventItem) -> String {
        if e.allDay { return "All day" }
        let f = Date.FormatStyle.dateTime.hour().minute()
        return "\(e.start.formatted(f)) – \(e.end.formatted(f))"
    }
}

// Tabs inside the expanded island, the feature models they show, and short "live activity" toasts.
import SwiftUI

enum IslandTab: String, CaseIterable {
    case music, files, clipboard, calendar, stats, notes, agents

    var icon: String {
        switch self {
        case .music: return "music.note"
        case .files: return "tray.full"
        case .clipboard: return "doc.on.clipboard"
        case .calendar: return "calendar"
        case .stats: return "gauge.with.dots.needle.33percent"
        case .notes: return "note.text"
        case .agents: return "sparkles"
        }
    }
    var title: String {
        switch self {
        case .music: return "Music"
        case .files: return "Files"
        case .clipboard: return "Clipboard"
        case .calendar: return "Calendar"
        case .stats: return "System"
        case .notes: return "Notes"
        case .agents: return "Agents"
        }
    }
}

struct Toast: Equatable {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    let until: Date
}

final class Hub: ObservableObject {
    @Published var tab: IslandTab = .music
    @Published var musicShowsQueue = false
    @Published private(set) var toast: Toast?

    let shelf = Shelf()
    let clips = ClipboardHistory()
    let cal = CalendarModel()
    let stats = SystemStats()
    let devices = DeviceMonitor()
    let notes = NotesModel()
    let agents = AgentMonitor()
    let recorder = Recorder()
    let settings = AppSettings.shared

    var visibleTabs: [IslandTab] { IslandTab.allCases.filter { settings.isTabOn($0) } }

    /// Tab to open on hover: an imminent meeting wins, then music, otherwise whatever was open last.
    func tabForHover(hasTrack: Bool) -> IslandTab {
        if cal.soon != nil && settings.isTabOn(.calendar) { return .calendar }
        if hasTrack && tab == .music { return .music }
        return settings.isTabOn(tab) ? tab : .music
    }

    func show(_ icon: String, _ tint: Color, _ title: String, _ detail: String = "", seconds: Double = 4) {
        let t = Toast(icon: icon, tint: tint, title: title, detail: detail, until: Date().addingTimeInterval(seconds))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.toast == t else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { self.toast = nil }
        }
    }
}

struct TabStrip: View {
    @ObservedObject var hub: Hub
    @ObservedObject var shelf: Shelf
    @ObservedObject var recorder: Recorder
    @ObservedObject var settings = AppSettings.shared
    var collapse: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(hub.visibleTabs, id: \.self) { t in
                let on = hub.tab == t
                Button { hub.tab = t } label: {
                    Image(systemName: t.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(on ? 1 : 0.45))
                        .frame(width: 30, height: 22)
                        .background(Capsule().fill(Color.white.opacity(on ? 0.16 : 0)))
                        .overlay(alignment: .topTrailing) {
                            if t == .files && !shelf.items.isEmpty {
                                Circle().fill(Color.blue).frame(width: 6, height: 6).offset(x: -4, y: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
            Spacer(minLength: 4)
            if recorder.supported {
                iconButton(recorder.isRecording ? "stop.circle.fill" : "record.circle", recorder.isRecording ? .red : .white.opacity(0.6),
                           help: recorder.isRecording ? "Stop recording" : "Record the screen") {
                    if recorder.isRecording { recorder.stop() } else {
                        collapse()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { recorder.start() }
                    }
                }
            }
            iconButton("pip", settings.floatingPlayer ? .white : .white.opacity(0.6), help: "Floating player") {
                settings.floatingPlayer.toggle()
            }
            iconButton("gearshape", .white.opacity(0.6), help: "Settings") { SettingsWindow.shared.show() }
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.15), value: hub.tab)
    }

    private func iconButton(_ s: String, _ c: Color, help: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: s).font(.system(size: 12, weight: .semibold)).foregroundStyle(c).frame(width: 24, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Island background: solid black, or frosted glass when the "Glass" finish is chosen.
struct IslandBackground: View {
    var glass: Bool
    var radius: CGFloat
    var floating: Bool

    var body: some View {
        if glass {
            VisualEffect()
                .overlay(Color.black.opacity(0.42))
                .mask(IslandShape(radius: radius, floating: floating))
                .overlay(IslandShape(radius: radius, floating: floating).stroke(Color.white.opacity(0.12), lineWidth: 1))
        } else {
            IslandShape(radius: radius, floating: floating).fill(Color.black)
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// Small text on either side of the collapsed island.
struct GlanceView: View {
    let glance: Glance
    @ObservedObject var stats: SystemStats
    @ObservedObject var cal: CalendarModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            HStack(spacing: 3) {
                switch glance {
                case .none: EmptyView()
                case .time: Text(ctx.date.formatted(.dateTime.hour().minute()))
                case .date: Text(ctx.date.formatted(.dateTime.weekday(.abbreviated).day()))
                case .nextEvent:
                    if let e = cal.events.first(where: { !$0.allDay && $0.start > ctx.date }) {
                        Image(systemName: "calendar").font(.system(size: 9))
                        Text(e.start.formatted(.dateTime.hour().minute()))
                    } else { Image(systemName: "calendar").font(.system(size: 9)); Text("Free") }
                case .battery:
                    if let b = stats.battery {
                        Image(systemName: stats.charging ? "battery.100.bolt" : batterySymbol(b)).font(.system(size: 10))
                            .foregroundStyle(b <= 20 && !stats.onAC ? .red : .white)
                        Text("\(b)%")
                    } else { Image(systemName: "powerplug.fill").font(.system(size: 9)) }
                case .cpu: Image(systemName: "cpu").font(.system(size: 9)); Text("\(Int(stats.cpu * 100))%")
                case .memory: Image(systemName: "memorychip").font(.system(size: 9)); Text("\(Int(stats.memFraction * 100))%")
                }
            }
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
        }
    }

    private func batterySymbol(_ b: Int) -> String {
        b > 85 ? "battery.100" : b > 60 ? "battery.75" : b > 35 ? "battery.50" : b > 15 ? "battery.25" : "battery.0"
    }
}

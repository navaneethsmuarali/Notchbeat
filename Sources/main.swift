// Notchbeat — a Dynamic Island for YouTube Music (via Chrome) with app and window switching bubbles.
import Cocoa
import ServiceManagement
import UniformTypeIdentifiers
import SwiftUI
import Combine

// MARK: - Player state shared between Chrome and the island

final class Player: ObservableObject {
    @Published var title = ""
    @Published var artist = ""
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var updatedAt = Date()
    @Published var expanded = false
    @Published var artwork: NSImage?
    @Published var accent = Color.white
    /// Short setup hint shown in the island when it can't read Chrome yet.
    @Published var notice: String?
    var onNotice: () -> Void = {}

    @Published var queue: [QueueItem] = []
    /// True while something on screen is showing Up Next, so the bridge only reads the queue when needed.
    var wantsQueue: () -> Bool = { false }

    var hasTrack: Bool { !title.isEmpty }
    var send: (String) -> Void = { _ in }
    var openApp: () -> Void = {}
    private var artURL = ""

    func livePosition(at now: Date) -> Double {
        guard isPlaying else { return position }
        return min(duration, position + now.timeIntervalSince(updatedAt))
    }

    func toggle() {
        isPlaying.toggle()
        send("if (!click('ytmusic-player-bar #play-pause-button') && v) { v.paused ? v.play() : v.pause(); }")
    }
    func next() { send("click('ytmusic-player-bar .next-button');") }
    func previous() { send("click('ytmusic-player-bar .previous-button');") }
    func seek(_ t: Double) { position = t; updatedAt = Date(); send("if (v) v.currentTime = \(t);") }
    func playQueueItem(_ q: QueueItem) {
        send("""
        const items = [...document.querySelectorAll('ytmusic-player-queue ytmusic-player-queue-item')];
        const it = items[\(q.id)];
        if (it) { (it.querySelector('ytmusic-play-button-renderer') || it.querySelector('.song-info') || it).click(); }
        """)
    }

    func apply(_ d: [String: Any]) {
        let t = d["title"] as? String ?? "", a = d["artist"] as? String ?? ""
        if t != title { title = t }
        if a != artist { artist = a }
        let playing = d["playing"] as? Bool ?? false
        if playing != isPlaying { isPlaying = playing }
        position = d["pos"] as? Double ?? 0
        duration = d["dur"] as? Double ?? 0
        updatedAt = Date()
        let art = d["art"] as? String ?? ""
        if art != artURL { artURL = art; loadArtwork(art) }
    }

    private func loadArtwork(_ s: String) {
        guard let url = URL(string: s), !s.isEmpty else { artwork = nil; return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            let color = Self.accentColor(of: img)
            DispatchQueue.main.async {
                guard let self, self.artURL == s else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    self.artwork = img
                    self.accent = color
                }
            }
        }.resume()
    }

    /// Average colour of the artwork, pushed bright and saturated so it reads on black.
    static func accentColor(of img: NSImage) -> Color {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }
        var px = [UInt8](repeating: 0, count: 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard ok else { return .white }
        let c = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.12 { return Color(white: 0.92) }
        return Color(nsColor: NSColor(hue: h, saturation: min(1, s * 1.4), brightness: max(0.85, b), alpha: 1))
    }
}

// MARK: - Chrome bridge (drives the music.youtube.com tab / YouTube Music Chrome app)

let stateJS = """
(function(){
  const q = s => document.querySelector(s);
  const v = q('#movie_player video') || q('video');
  const m = navigator.mediaSession && navigator.mediaSession.metadata;
  let title = m ? m.title : '', artist = m ? m.artist : '', art = '';
  if (m && m.artwork && m.artwork.length) art = m.artwork[m.artwork.length - 1].src;
  if (!title) { const e = q('ytmusic-player-bar .title'); title = e ? e.textContent.trim() : ''; }
  if (!artist) { const e = q('ytmusic-player-bar .byline'); artist = e ? e.textContent.split('•')[0].trim() : ''; }
  if (!art) { const e = q('ytmusic-player-bar img.image'); art = e && /^https:\\/\\/(i|lh\\d)\\./.test(e.src) ? e.src : ''; }
  return JSON.stringify({ title, artist, art,
    playing: !!(v && !v.paused && !v.ended),
    pos: v ? (v.currentTime || 0) : 0,
    dur: v && isFinite(v.duration) ? v.duration : 0 });
})()
"""

let queueJS = """
(function(){
  const items = [...document.querySelectorAll('ytmusic-player-queue ytmusic-player-queue-item')];
  const cur = items.findIndex(i => i.hasAttribute('selected'));
  const out = [];
  for (let i = cur + 1; i < items.length && out.length < 25; i++) {
    const it = items[i];
    const t = it.querySelector('.song-title'), b = it.querySelector('.byline'), img = it.querySelector('img');
    out.push({ i, title: t ? t.textContent.trim() : '', artist: b ? b.textContent.trim() : '',
               art: img && img.src && img.src.startsWith('http') ? img.src : '' });
  }
  return JSON.stringify(out);
})()
"""

func actionJS(_ body: String) -> String {
    """
    (function(){
      const q = s => document.querySelector(s);
      const v = q('#movie_player video') || q('video');
      const click = s => { const b = q(s); if (b) { b.click(); return true; } return false; };
      \(body)
      return 'ok';
    })()
    """
}

let chromeScript = """
on run argv
  set js to item 1 of argv
  if application id "com.google.Chrome" is not running then return "NOCHROME"
  tell application id "com.google.Chrome"
    repeat with w in windows
      repeat with t in tabs of w
        if (URL of t) starts with "https://music.youtube.com" then
          return execute t javascript js
        end if
      end repeat
    end repeat
  end tell
  tell application id "com.google.Chrome" to return "NOTAB windows=" & (count of windows) & " tabs=" & (count of tabs of every window)
end run
"""

final class ChromeBridge {
    enum Status: Equatable { case ok, noChrome, noTab, jsDisabled, notAllowed, error(String) }

    let player: Player
    private(set) var status: Status = .noChrome {
        didSet {
            guard status != oldValue else { return }
            onStatus(status)
            Self.log("status: \(status)")
            switch status {
            case .jsDisabled, .notAllowed: player.notice = "Setup needed — click"
            case .error: player.notice = "Can't reach Chrome"
            default: player.notice = nil
            }
        }
    }

    static func log(_ msg: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Notchbeat.log")
        let line = "\(Date()) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
    var onStatus: (Status) -> Void = { _ in }
    private let queue = DispatchQueue(label: "chrome-bridge")
    private var polling = false
    private var timer: Timer?
    static let chromeID = "com.google.Chrome"

    init(player: Player) {
        self.player = player
        player.send = { [weak self] js in self?.perform(js) }
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    private var chromeRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: Self.chromeID).isEmpty }

    func poll() {
        // Never touch Chrome (which would launch it) unless it is already running.
        guard chromeRunning else { update(.noChrome); return }
        guard !polling else { return }
        polling = true
        run(stateJS) { [weak self] out, err in
            guard let self else { return }
            self.polling = false
            if let err { self.update(err); return }
            guard let out else { return }
            if out == "NOCHROME" { self.update(.noChrome); return }
            if out.hasPrefix("NOTAB") { if self.status != .noTab { Self.log(out) }; self.update(.noTab); return }
            guard let data = out.data(using: .utf8),
                  let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            self.status = .ok
            self.player.apply(d)
            if self.player.wantsQueue() { self.fetchQueue() }
        }
    }

    private var fetchingQueue = false
    private func fetchQueue() {
        guard !fetchingQueue else { return }
        fetchingQueue = true
        run(queueJS) { [weak self] out, _ in
            guard let self else { return }
            self.fetchingQueue = false
            guard let data = out?.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            let q = arr.compactMap { d -> QueueItem? in
                guard let i = d["i"] as? Int, let t = d["title"] as? String, !t.isEmpty else { return nil }
                return QueueItem(id: i, title: t, artist: d["artist"] as? String ?? "", art: d["art"] as? String ?? "")
            }
            if q != self.player.queue { self.player.queue = q }
        }
    }

    private func update(_ s: Status) {
        status = s
        if player.hasTrack { player.apply(["title": "", "artist": "", "art": "", "playing": false]) }
        if !player.queue.isEmpty { player.queue = [] }
    }

    func perform(_ body: String) {
        guard chromeRunning else { return }
        run(actionJS(body)) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.poll() }
        }
    }

    /// Runs the AppleScript in osascript off the main thread so a busy Chrome never freezes the island.
    private func run(_ js: String, completion: @escaping (String?, Status?) -> Void) {
        queue.async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", chromeScript, js]
            let out = Pipe(), err = Pipe()
            p.standardOutput = out; p.standardError = err
            var result: String?, status: Status?
            do {
                try p.run()
                p.waitUntilExit()
                result = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if p.terminationStatus != 0 {
                    if e.contains("JavaScript") && e.contains("Apple Events") { status = .jsDisabled }
                    else if e.contains("-1743") || e.contains("Not authorized") { status = .notAllowed }
                    else { status = .error(e.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
            } catch { status = .error(error.localizedDescription) }
            DispatchQueue.main.async { completion(result, status) }
        }
    }
}

// MARK: - Island shape (flared top corners like the hardware notch, rounded bottom)

struct IslandShape: Shape {
    var radius: CGFloat
    var floating = false
    var animatableData: CGFloat { get { radius } set { radius = newValue } }

    func path(in r: CGRect) -> Path {
        if floating {
            return Path(roundedRect: r, cornerRadius: min(radius, r.height / 2), style: .continuous)
        }
        let t: CGFloat = 6                       // top "ear" flare
        let rad = min(radius, (r.height - t) , (r.width - 2 * t) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - rad))
        p.addQuadCurve(to: CGPoint(x: r.minX + t + rad, y: r.maxY), control: CGPoint(x: r.minX + t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - rad, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - rad), control: CGPoint(x: r.maxX - t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - t, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Island views

struct Equalizer: View {
    var playing: Bool
    var color: Color
    var bars = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<bars, id: \.self) { i in
                    let phase = Double(i) * 1.7
                    let h = playing ? 0.3 + 0.7 * abs(sin(t * (5 + Double(i)) + phase) * cos(t * 2.3 + phase)) : 0.2
                    Capsule().fill(color).frame(width: 3).frame(maxHeight: .infinity).scaleEffect(y: h)
                }
            }
        }
    }
}

struct Artwork: View {
    var image: NSImage?
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner).fill(Color.white.opacity(0.12))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.45)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner))
    }
}

enum CompactKind { case recording, toast, meeting, music, agent, notice, shelf, glances, none }

struct IslandView: View {
    @ObservedObject var p: Player
    @ObservedObject var s: Switcher
    @ObservedObject var hub: Hub
    @ObservedObject var shelf: Shelf
    @ObservedObject var cal: CalendarModel
    @ObservedObject var recorder: Recorder
    @ObservedObject var agents: AgentMonitor
    @ObservedObject var settings: AppSettings
    let geo: IslandGeometry
    var collapse: () -> Void
    var paste: (Clip) -> Void
    @State private var dragFraction: Double?
    @State private var dropTargeted = false

    init(p: Player, s: Switcher, hub: Hub, geo: IslandGeometry, collapse: @escaping () -> Void, paste: @escaping (Clip) -> Void) {
        self.p = p; self.s = s; self.hub = hub; self.shelf = hub.shelf; self.cal = hub.cal
        self.recorder = hub.recorder; self.agents = hub.agents; self.settings = hub.settings
        self.geo = geo; self.collapse = collapse; self.paste = paste
    }

    /// What the collapsed island shows, most urgent first.
    private var kind: CompactKind {
        if recorder.isRecording { return .recording }
        if hub.toast != nil { return .toast }
        if cal.soon != nil { return .meeting }
        if p.hasTrack { return .music }
        if agents.working != nil { return .agent }
        if p.notice != nil { return .notice }
        if !shelf.items.isEmpty { return .shelf }
        if settings.glanceCount > 0 { return .glances }
        return .none
    }
    private var accent: Color { settings.accent(album: p.accent) }

    var body: some View {
        let k = kind
        let size: CGSize = p.expanded ? geo.expanded : (k == .none ? geo.idle : (k == .glances ? geo.glancesOnly : geo.compact))
        let hiddenIdle = !geo.hasNotch && !p.expanded && k == .none
        let radius: CGFloat = p.expanded ? (geo.hasNotch ? 30 : 36) : (geo.hasNotch ? 10 : size.height / 2)
        VStack(spacing: Layout.rowGap) {
            ZStack(alignment: .top) {
                // On notch Macs the collapsed island stays solid black so it blends into the camera housing.
                IslandBackground(glass: settings.finish == .glass && (p.expanded || !geo.hasNotch), radius: radius, floating: !geo.hasNotch)
                    .shadow(color: .black.opacity(p.expanded ? 0.45 : 0), radius: 14, y: 6)
                if p.expanded {
                    expandedTabs.transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .top)))
                } else if k != .none {
                    compactRow(k).transition(.opacity)
                }
                if dropTargeted {
                    IslandShape(radius: radius, floating: !geo.hasNotch)
                        .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            .opacity(hiddenIdle ? 0 : 1)
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                hub.tab = .files
                shelf.add(providers: providers)
                return true
            }
            if p.expanded && settings.showBubbles {
                BubbleRow(s: s).transition(.opacity)
                if let b = s.selectedBubble {
                    WindowList(b: b, s: s).transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.top, geo.topGap)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: p.expanded)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: k)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: s.selected)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: hub.tab)
    }

    // MARK: Collapsed

    private func compactRow(_ k: CompactKind) -> some View {
        HStack(spacing: 0) {
            if settings.glanceLeft != .none {
                GlanceView(glance: settings.glanceLeft, stats: hub.stats, cal: cal).frame(width: geo.glanceWidth)
            }
            Group {
                switch k {
                case .recording: recordingCompact
                case .toast: toastCompact
                case .meeting: meetingCompact
                case .music: compact
                case .agent: agentCompact
                case .notice: noticeView
                case .shelf: shelfCompact
                case .glances, .none: Color.clear.frame(width: geo.hasNotch ? geo.notch.width : 4)
                }
            }
            .frame(maxWidth: .infinity)
            if settings.glanceRight != .none {
                GlanceView(glance: settings.glanceRight, stats: hub.stats, cal: cal).frame(width: geo.glanceWidth)
            }
        }
        .frame(height: geo.compact.height)
    }

    private var recordingCompact: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 9, height: 9)
                    .opacity(Int(ctx.date.timeIntervalSince1970) % 2 == 0 ? 1 : 0.4)
                if !geo.hasNotch { Text("Recording").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white) }
                Spacer(minLength: 4)
                Text(Recorder.elapsed(since: recorder.startedAt, now: ctx.date))
                    .font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
        }
        .frame(height: geo.compact.height)
        .contentShape(Rectangle())
        .onTapGesture { recorder.stop() }
        .help("Click to stop recording")
    }

    private var toastCompact: some View {
        let t = hub.toast
        return HStack(spacing: 6) {
            Image(systemName: t?.icon ?? "bell").font(.system(size: 12, weight: .semibold)).foregroundStyle(t?.tint ?? .white)
            if !geo.hasNotch {
                Text(t?.title ?? "").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(geo.hasNotch ? ((t?.detail.isEmpty ?? true) ? (t?.title ?? "") : (t?.detail ?? "")) : (t?.detail ?? ""))
                .font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: geo.compact.height)
    }

    private var agentCompact: some View {
        let a = agents.working
        return HStack(spacing: 6) {
            Spinner(color: a?.tool == "Codex" ? .cyan : .orange).frame(width: 12, height: 12)
            if !geo.hasNotch {
                Text("\(a?.tool ?? "") · \(a?.project ?? "")").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.orange)
        }
        .padding(.horizontal, 14)
        .frame(height: geo.compact.height)
        .contentShape(Rectangle())
        .onTapGesture { hub.tab = .agents; p.expanded = true }
    }

    private var meetingCompact: some View {
        let e = cal.soon
        return HStack(spacing: 6) {
            Image(systemName: "video.fill").font(.system(size: 11)).foregroundStyle(e?.color ?? .green)
            if !geo.hasNotch {
                Text(e?.title ?? "").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(e.map { cal.countdown($0) } ?? "").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .frame(height: geo.compact.height)
        .contentShape(Rectangle())
        .onTapGesture { hub.tab = .calendar; p.expanded = true }
    }

    private var shelfCompact: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 4)
            Text("\(shelf.items.count)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .frame(height: geo.compact.height)
        .contentShape(Rectangle())
        .onTapGesture { hub.tab = .files; p.expanded = true }
    }

    private var noticeView: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(p.notice ?? "").foregroundStyle(.white).lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { p.onNotice() }
    }

    private var compact: some View {
        HStack {
            Artwork(image: p.artwork, size: geo.compact.height - 10, corner: geo.hasNotch ? 5 : (geo.compact.height - 10) / 2)
            if !geo.hasNotch {
                Text(p.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer(minLength: 6)
            Equalizer(playing: p.isPlaying, color: accent).frame(width: 18, height: geo.compact.height - 16)
        }
        .padding(.leading, geo.hasNotch ? 14 : 5)
        .padding(.trailing, 14)
        .frame(height: geo.compact.height)
        .contentShape(Rectangle())
        .onTapGesture { p.expanded = true }
    }

    // MARK: Expanded

    private var expandedTabs: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: geo.hasNotch ? geo.notch.height - 8 : 2)
            TabStrip(hub: hub, shelf: shelf, recorder: recorder, collapse: collapse)
            Group {
                switch hub.tab {
                case .music: musicTab
                case .files: ShelfView(shelf: shelf)
                case .clipboard: ClipboardView(c: hub.clips, onPaste: paste, onClose: collapse)
                case .calendar: CalendarView(cal: cal)
                case .stats: StatsView(stats: hub.stats, devices: hub.devices)
                case .notes: NotesView(notes: hub.notes)
                case .agents: AgentsView(agents: agents)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
            .id(hub.tab)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var musicTab: some View {
        if !p.hasTrack {
            idleExpanded
        } else if hub.musicShowsQueue {
            VStack(spacing: 4) {
                HStack {
                    Text("UP NEXT").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Button { hub.musicShowsQueue = false } label: {
                        Label("Now Playing", systemImage: "chevron.left").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                }
                QueueList(p: p)
            }
        } else {
            nowPlaying
        }
    }

    private var idleExpanded: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            Text("Nothing playing").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button { p.openApp() } label: {
                Text("Open YouTube Music").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(PressStyle())
        }
        .frame(maxHeight: .infinity)
    }

    private var nowPlaying: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Artwork(image: p.artwork, size: 54, corner: 11)
                    .onTapGesture { p.openApp() }
                    .help("Open YouTube Music")
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(p.artist).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button { hub.musicShowsQueue = true } label: {
                    Image(systemName: "list.bullet").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                        .frame(width: 30, height: 26).background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(PressStyle())
                .help("Up Next")
            }
            if settings.showWaveform {
                Waveform(playing: p.isPlaying, color: accent).frame(height: 14)
            }
            progress
            HStack(spacing: 40) {
                control("backward.fill", 18) { p.previous() }
                control(p.isPlaying ? "pause.fill" : "play.fill", 26) { p.toggle() }
                control("forward.fill", 18) { p.next() }
            }
        }
        .padding(.horizontal, 6)
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let pos = dragFraction.map { $0 * p.duration } ?? p.livePosition(at: ctx.date)
            let frac = p.duration > 0 ? pos / p.duration : 0
            HStack(spacing: 10) {
                Text(fmt(pos)).frame(width: 38, alignment: .trailing)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule().fill(accent).frame(width: max(0, g.size.width * frac))
                    }
                    .frame(height: dragFraction == nil ? 5 : 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { dragFraction = min(1, max(0, $0.location.x / g.size.width)) }
                        .onEnded { _ in
                            if let f = dragFraction { p.seek(f * p.duration) }
                            dragFraction = nil
                        })
                }
                .frame(height: 14)
                Text("-" + fmt(max(0, p.duration - pos))).frame(width: 42, alignment: .leading)
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
            .animation(.easeOut(duration: 0.15), value: dragFraction == nil)
        }
    }

    private func control(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private func fmt(_ s: Double) -> String {
        guard s.isFinite else { return "0:00" }
        let t = Int(s)
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - App switcher bubbles

enum Layout {
    static let bubble: CGFloat = 48
    static let bubbleGap: CGFloat = 10
    static let rowGap: CGFloat = 10
    static let maxBubbles = 8
    static let listRow: CGFloat = 28
    static let listMaxRows = 8
    static let listChrome: CGFloat = 20 + 26      // padding + header
    static let listWidth: CGFloat = 320
}

struct WindowEntry: Identifiable {
    let id: Int
    let title: String
    let minimized: Bool
    let element: AXUIElement
}

struct AppBubble: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
    let url: URL?
    let app: NSRunningApplication?
    var windows: [WindowEntry]
    let pinned: Bool
}

final class Switcher: ObservableObject {
    @Published var bubbles: [AppBubble] = []
    @Published var selected: String?
    @Published var axTrusted = AXIsProcessTrusted()
    var onDone: () -> Void = {}
    private let queue = DispatchQueue(label: "switcher")

    var pinnedPaths: [String] {
        get { UserDefaults.standard.stringArray(forKey: "pinnedApps") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "pinnedApps") }
    }

    /// Height the bubble row + window list take below the island.
    var extraHeight: CGFloat {
        var h: CGFloat = 0
        if !bubbles.isEmpty || !axTrusted { h += Layout.rowGap + Layout.bubble + 8 }
        if let b = selectedBubble { h += Layout.rowGap + Layout.listChrome + CGFloat(min(b.windows.count, Layout.listMaxRows)) * Layout.listRow }
        return h
    }
    var extraWidth: CGFloat {
        let n = CGFloat(bubbles.count + (axTrusted ? 0 : 1))
        return max(n * (Layout.bubble + Layout.bubbleGap) - Layout.bubbleGap, selectedBubble == nil ? 0 : Layout.listWidth)
    }
    var selectedBubble: AppBubble? { selected.flatMap { id in bubbles.first { $0.id == id } } }

    func refresh() {
        let pinned = pinnedPaths
        queue.async {
            let trusted = AXIsProcessTrusted()
            let list = Self.buildBubbles(pinned: pinned, trusted: trusted)
            DispatchQueue.main.async {
                self.axTrusted = trusted
                self.bubbles = list
                if let s = self.selected, !list.contains(where: { $0.id == s }) { self.selected = nil }
            }
        }
    }

    private static func buildBubbles(pinned: [String], trusted: Bool) -> [AppBubble] {
        let me = ProcessInfo.processInfo.processIdentifier
        // Front-to-back order of real (layer 0, reasonably sized) windows tells us which apps were used most recently.
        func pids(_ opts: CGWindowListOption) -> [pid_t] {
            let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
            var out: [pid_t] = []
            for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
                guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != me else { continue }
                if let bd = w[kCGWindowBounds as String], let r = CGRect(dictionaryRepresentation: bd as! CFDictionary),
                   r.width < 80 || r.height < 60 { continue }
                if !out.contains(pid) { out.append(pid) }
            }
            return out
        }
        let onScreen = pids([.optionOnScreenOnly, .excludeDesktopElements])
        let any = Set(pids([.optionAll, .excludeDesktopElements]))
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated
        }

        func make(_ app: NSRunningApplication?, url: URL?, pinned: Bool) -> AppBubble? {
            guard let url = url ?? app?.bundleURL else { return nil }
            let name = app?.localizedName ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            let icon = app?.icon ?? NSWorkspace.shared.icon(forFile: url.path)
            let windows = (trusted && app != nil) ? axWindows(app!.processIdentifier, fallback: name) : []
            return AppBubble(id: url.path, name: name, icon: icon, url: url, app: app, windows: windows, pinned: pinned)
        }

        var result: [AppBubble] = []
        var used = Set<String>()
        for path in pinned {
            let app = running.first { $0.bundleURL?.path == path }
            if let b = make(app, url: URL(fileURLWithPath: path), pinned: true) { result.append(b); used.insert(path) }
        }
        let ranked = running
            .filter { any.contains($0.processIdentifier) && !used.contains($0.bundleURL?.path ?? "") }
            .sorted { (onScreen.firstIndex(of: $0.processIdentifier) ?? 999) < (onScreen.firstIndex(of: $1.processIdentifier) ?? 999) }
        for app in ranked where result.count < Layout.maxBubbles {
            if let b = make(app, url: nil, pinned: false), !(trusted && b.windows.isEmpty) { result.append(b) }
        }
        return Array(result.prefix(Layout.maxBubbles))
    }

    private static func axWindows(_ pid: pid_t, fallback: String) -> [WindowEntry] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)   // never hang on a frozen app
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success,
              let wins = v as? [AXUIElement] else { return [] }
        var out: [WindowEntry] = []
        for (i, w) in wins.enumerated() {
            var sub: CFTypeRef?, title: CFTypeRef?, mini: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &sub)
            if let s = sub as? String, s != kAXStandardWindowSubrole as String && s != kAXDialogSubrole as String { continue }
            AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &title)
            AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &mini)
            let t = (title as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            out.append(WindowEntry(id: i, title: t, minimized: (mini as? Bool) ?? false, element: w))
        }
        return out
    }

    func tap(_ b: AppBubble) {
        if b.windows.count > 1 { selected = (selected == b.id) ? nil : b.id; return }
        if let w = b.windows.first { raise(w, in: b) } else { bringForward(b) }
    }

    func raise(_ w: WindowEntry, in b: AppBubble) {
        if w.minimized { AXUIElementSetAttributeValue(w.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        AXUIElementSetAttributeValue(w.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(w.element, kAXRaiseAction as CFString)
        bringForward(b)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { AXUIElementPerformAction(w.element, kAXRaiseAction as CFString) }
    }

    /// Opening through Launch Services reliably brings an app forward even though the island never becomes active.
    func bringForward(_ b: AppBubble) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        if let url = b.url { NSWorkspace.shared.openApplication(at: url, configuration: cfg) } else { b.app?.activate() }
        selected = nil
        onDone()
    }

    func togglePin(_ b: AppBubble) {
        var p = pinnedPaths
        if let i = p.firstIndex(of: b.id) { p.remove(at: i) } else { p.append(b.id) }
        pinnedPaths = p
        refresh()
    }

    func addPinned(_ url: URL) {
        var p = pinnedPaths
        if !p.contains(url.path) { p.append(url.path) }
        pinnedPaths = p
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}

struct BubbleView: View {
    let b: AppBubble
    let selected: Bool
    @State private var hover = false

    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            Circle().strokeBorder(Color.white.opacity(selected ? 0.7 : (hover ? 0.3 : 0.1)), lineWidth: selected ? 2 : 1)
            Image(nsImage: b.icon).resizable().interpolation(.high).frame(width: 32, height: 32)
        }
        .frame(width: Layout.bubble, height: Layout.bubble)
        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
        .overlay(alignment: .topTrailing) {
            if b.windows.count > 1 {
                Text("\(b.windows.count)")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Circle().fill(Color.white))
                    .offset(x: 3, y: -3)
            }
        }
        .overlay(alignment: .bottom) {
            if b.app != nil { Circle().fill(Color.white.opacity(0.75)).frame(width: 4, height: 4).offset(y: 8) }
        }
        .scaleEffect(hover ? 1.1 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hover)
        .onHover { hover = $0 }
        .help(b.windows.count > 1 ? "\(b.name) — \(b.windows.count) windows" : b.name)
    }
}

struct BubbleRow: View {
    @ObservedObject var s: Switcher
    @State private var shown = false

    var body: some View {
        HStack(spacing: Layout.bubbleGap) {
            ForEach(Array(s.bubbles.enumerated()), id: \.element.id) { i, b in
                BubbleView(b: b, selected: s.selected == b.id)
                    .contentShape(Circle())
                    .onTapGesture { s.tap(b) }
                    .contextMenu {
                        Button(b.pinned ? "Unpin from Island" : "Pin to Island") { s.togglePin(b) }
                    }
                    .scaleEffect(shown ? 1 : 0.2)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : -30)
                    .animation(.spring(response: 0.4, dampingFraction: 0.66).delay(Double(i) * 0.035), value: shown)
            }
            if !s.axTrusted {
                ZStack {
                    Circle().fill(Color.black)
                    Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                    Image(systemName: "macwindow.on.rectangle").font(.system(size: 17)).foregroundStyle(.white.opacity(0.8))
                }
                .frame(width: Layout.bubble, height: Layout.bubble)
                .contentShape(Circle())
                .onTapGesture { s.requestAccessibility() }
                .help("Allow Accessibility to switch between individual windows")
                .scaleEffect(shown ? 1 : 0.2).opacity(shown ? 1 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.66).delay(Double(s.bubbles.count) * 0.035), value: shown)
            }
        }
        .frame(height: Layout.bubble + 8, alignment: .top)
        .onAppear { shown = true }
    }
}

struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0)))
    }
}

struct WindowList: View {
    let b: AppBubble
    let s: Switcher

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(nsImage: b.icon).resizable().frame(width: 18, height: 18)
                Text(b.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
            }
            .frame(height: 26)
            .padding(.horizontal, 8)
            ForEach(b.windows.prefix(Layout.listMaxRows)) { w in
                Button { s.raise(w, in: b) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: w.minimized ? "arrow.down.right.and.arrow.up.left" : "macwindow")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).frame(width: 18)
                        Text(w.title).font(.system(size: 12)).foregroundStyle(.white.opacity(w.minimized ? 0.5 : 0.9)).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: Layout.listRow)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowStyle())
            }
        }
        .padding(10)
        .frame(width: Layout.listWidth)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black).shadow(color: .black.opacity(0.4), radius: 10, y: 4))
    }
}

// MARK: - Island window

struct IslandGeometry {
    var notch: CGSize
    var hasNotch: Bool
    var glanceCount = 0
    let glanceWidth: CGFloat = 58
    var topGap: CGFloat { hasNotch ? 0 : 6 }
    var idle: CGSize { CGSize(width: notch.width + 12, height: notch.height) }
    var compact: CGSize {
        let base: CGFloat = hasNotch ? notch.width + 2 * 46 + 12 : 230
        return CGSize(width: base + CGFloat(glanceCount) * glanceWidth, height: hasNotch ? notch.height : 34)
    }
    var glancesOnly: CGSize {
        CGSize(width: (hasNotch ? notch.width + 16 : 14) + CGFloat(glanceCount) * glanceWidth, height: compact.height)
    }
    var expanded: CGSize { hasNotch ? CGSize(width: max(460, notch.width + 240), height: notch.height + 196) : CGSize(width: 460, height: 214) }
    /// Largest the whole island (plus bubbles and window list) can get; the panel uses this while expanded.
    var maxExpanded: CGSize {
        let bubbles = CGFloat(Layout.maxBubbles + 1) * (Layout.bubble + Layout.bubbleGap)
        let extra = Layout.rowGap + Layout.bubble + 8 + Layout.rowGap + Layout.listChrome + CGFloat(Layout.listMaxRows) * Layout.listRow + 24
        return CGSize(width: max(expanded.width, bubbles, Layout.listWidth, compact.width) + 40, height: expanded.height + extra)
    }

    static func current(for screen: NSScreen, glances: Int) -> IslandGeometry {
        let top = screen.safeAreaInsets.top
        if top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return IslandGeometry(notch: CGSize(width: screen.frame.width - l.width - r.width, height: top), hasNotch: true, glanceCount: glances)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return IslandGeometry(notch: CGSize(width: 120, height: max(menuBar, 24)), hasNotch: false, glanceCount: glances)
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class IslandController {
    let player: Player
    let switcher: Switcher
    let hub: Hub
    private var dragBaseline = NSPasteboard(name: .drag).changeCount
    private var panel: IslandPanel!
    private var geo: IslandGeometry
    private var screen: NSScreen
    private var timer: Timer?
    private var hoverSince: Date?
    private var leftSince: Date?
    /// Opened from the keyboard shortcut: stays open until the pointer has visited and left, a click lands outside, or Esc.
    private var sticky = false
    private var stickyVisited = false
    private var hosting: FirstMouseHostingView<IslandView>!
    private var clickMonitor: Any?
    private var settingsSink: AnyCancellable?

    init(player: Player, switcher: Switcher, hub: Hub) {
        self.player = player
        self.switcher = switcher
        self.hub = hub
        screen = Self.pickScreen()
        geo = IslandGeometry.current(for: screen, glances: hub.settings.glanceCount)
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        hosting = FirstMouseHostingView(rootView: makeView())
        panel.contentView = hosting
        layout(expanded: false)
        panel.orderFrontRegardless()
        switcher.onDone = { [weak self] in self?.collapse() }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
        // Glances change the island's width; rebuild geometry when settings change.
        settingsSink = hub.settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.rebuildIfNeeded() }
        }
        // Clicking anywhere outside the island closes it.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.player.expanded else { return }
            if !self.visibleExpandedRect.contains(NSEvent.mouseLocation) { self.collapse() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func makeView() -> IslandView {
        IslandView(p: player, s: switcher, hub: hub, geo: geo,
                   collapse: { [weak self] in self?.collapse() },
                   paste: { [weak self] clip in self?.paste(clip) })
    }

    private static func pickScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func rebuild() {
        screen = Self.pickScreen()
        geo = IslandGeometry.current(for: screen, glances: hub.settings.glanceCount)
        hosting.rootView = makeView()
        layout(expanded: player.expanded)
    }

    private func rebuildIfNeeded() {
        if geo.glanceCount != hub.settings.glanceCount { rebuild() }
    }

    /// Window frame is the biggest the island can be in a state; SwiftUI animates the shape inside it.
    private func layout(expanded: Bool) {
        let size = expanded ? geo.maxExpanded : geo.compact
        let f = screen.frame
        let h = size.height + geo.topGap
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - h, width: size.width, height: h), display: true)
    }

    private func islandRect(_ size: CGSize) -> NSRect {
        let f = screen.frame
        let h = size.height + geo.topGap
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - h, width: size.width, height: h)
    }

    /// What is actually drawn while expanded: the island plus the bubble row and window list under it.
    private var visibleExpandedRect: NSRect {
        let island = geo.expanded
        let showBubbles = hub.settings.showBubbles
        let size = CGSize(width: max(island.width, showBubbles ? switcher.extraWidth : 0),
                          height: island.height + (showBubbles ? switcher.extraHeight : 0))
        return islandRect(size).insetBy(dx: -10, dy: -10)
    }

    private func tick() {
        if !panel.isVisible { panel.orderFrontRegardless() }

        let mouse = NSEvent.mouseLocation
        // A file drag is in progress when the left button is down and the drag pasteboard has changed since it went down.
        let leftDown = NSEvent.pressedMouseButtons & 1 != 0
        let dragPB = NSPasteboard(name: .drag)
        if !leftDown { dragBaseline = dragPB.changeCount }
        let draggingFiles = leftDown && dragPB.changeCount != dragBaseline && (dragPB.types ?? []).contains(.fileURL)

        if !player.expanded && draggingFiles && islandRect(geo.compact).insetBy(dx: -80, dy: -40).contains(mouse) {
            expand(tab: .files)
            return
        }
        if player.expanded {
            let inside = visibleExpandedRect.contains(mouse)
            if sticky {
                if inside { stickyVisited = true }
                if !(stickyVisited && !inside) { leftSince = nil; return }
                sticky = false
            }
            // Typing a note keeps the island open until you click elsewhere.
            if hub.tab == .notes && panel.isKeyWindow { leftSince = nil; return }
            if inside || NSEvent.pressedMouseButtons != 0 {
                leftSince = nil
            } else if let t = leftSince {
                if Date().timeIntervalSince(t) > 0.25 { collapse() }
            } else { leftSince = Date() }
        } else {
            guard islandRect(geo.compact).contains(mouse) else { hoverSince = nil; return }
            // With nothing showing (no notch, no music) wait a little longer so passing the menu bar doesn't pop it open.
            let dwell = (player.hasTrack || geo.hasNotch || hub.settings.glanceCount > 0) ? 0.12 : 0.35
            if let t = hoverSince {
                if Date().timeIntervalSince(t) > dwell { expand(tab: hub.tabForHover(hasTrack: player.hasTrack)) }
            } else { hoverSince = Date() }
        }
        // Tapping the compact island sets expanded directly; keep the window in sync.
        if player.expanded && panel.frame.height < geo.maxExpanded.height { layout(expanded: true) }
    }

    func expand(tab: IslandTab? = nil) {
        hoverSince = nil; leftSince = nil
        if let tab { hub.tab = tab }
        hub.shelf.prune()
        switcher.refresh()
        layout(expanded: true)
        player.expanded = true
    }

    func collapse() {
        leftSince = nil
        sticky = false
        switcher.selected = nil
        hub.musicShowsQueue = false
        player.expanded = false
        if panel.isKeyWindow {
            // Hand keyboard focus back to the app you were using.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, !self.player.expanded else { return }
            self.layout(expanded: false)
        }
    }

    /// Keyboard shortcut: open clipboard history, ready for ↑ ↓ and Return.
    func toggleClipboard() {
        if player.expanded && hub.tab == .clipboard { collapse(); return }
        expand(tab: .clipboard)
        sticky = true
        stickyVisited = false
        panel.makeKey()
    }

    private func paste(_ clip: Clip) {
        hub.clips.copy(clip)
        collapse()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pasteIntoFrontApp() }
    }
}

// MARK: - App (menu bar agent: the island + a status menu)

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let player = Player()
    let switcher = Switcher()
    let hub = Hub()
    var bridge: ChromeBridge!
    var island: IslandController!
    var statusItem: NSStatusItem!
    var mini: MiniPlayerController!
    var hotKey: HotKey?
    var sinks: [AnyCancellable] = []

    static let pwaID = "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod"

    func applicationDidFinishLaunching(_ n: Notification) {
        bridge = ChromeBridge(player: player)
        player.openApp = { [weak self] in self?.openYouTubeMusic() }
        island = IslandController(player: player, switcher: switcher, hub: hub)
        bridge.onStatus = { [weak self] s in if s == .jsDisabled { self?.explainChromeSetting() } }
        player.onNotice = { [weak self] in
            guard let self else { return }
            if self.bridge.status == .notAllowed { self.openAutomationSettings() } else { self.explainChromeSetting(force: true) }
        }
        bridge.start()
        wireFeatures()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let st = self?.hub.stats else { return }
            ChromeBridge.log(String(format: "stats: cpu %.0f%%, mem %.1f/%.0f GB, net %.0f B/s, battery %@",
                                    st.cpu * 100, st.memUsed / 1_073_741_824, st.memTotal / 1_073_741_824, st.netIn + st.netOut,
                                    st.battery.map { "\($0)%\(st.onAC ? " (AC)" : "")" } ?? "none"))
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Notchbeat")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func wireFeatures() {
        let settings = hub.settings
        mini = MiniPlayerController(player: player)
        player.wantsQueue = { [weak self] in
            guard let self else { return false }
            return (self.player.expanded && self.hub.tab == .music && self.hub.musicShowsQueue) || self.mini.expandedQueueVisible
        }
        sinks.append(settings.$floatingPlayer.sink { [weak self] on in self?.mini.setVisible(on) })
        sinks.append(settings.$hotkey.sink { [weak self] preset in self?.registerHotkey(preset) })
        sinks.append(settings.$agentsEnabled.sink { [weak self] _ in DispatchQueue.main.async { self?.hub.agents.scan() } })

        hub.devices.onConnect = { [weak self] d in
            guard let self, settings.deviceAlerts else { return }
            self.hub.show(d.symbol, .white, d.shortName, d.levels.isEmpty ? "Connected" : d.levelText)
        }
        hub.devices.onLow = { [weak self] d in
            guard let self, settings.deviceAlerts, !d.levels.isEmpty else { return }
            self.hub.show(d.symbol, .red, "\(d.shortName) is low", d.levelText, seconds: 6)
        }
        hub.stats.onPowerChange = { [weak self] pct, ac in
            self?.hub.show(ac ? "bolt.fill" : "battery.75", ac ? .green : .white, ac ? "Charging" : "On battery", "\(pct)%")
        }
        hub.stats.onLowBattery = { [weak self] pct in
            self?.hub.show("battery.25", .red, "Battery low", "\(pct)%", seconds: 6)
        }
        hub.recorder.onFinished = { [weak self] url in
            self?.hub.shelf.add([url])
            self?.hub.show("checkmark.circle.fill", .green, "Recording saved", "In Files")
        }
        sinks.append(hub.recorder.$lastError.compactMap { $0 }.sink { [weak self] err in
            guard let self else { return }
            if err.contains("Screen Recording") {
                let a = NSAlert()
                a.messageText = "Allow screen recording"
                a.informativeText = "Turn on Notchbeat in System Settings → Privacy & Security → Screen & System Audio Recording, then start the recording again."
                a.addButton(withTitle: "Open Settings")
                a.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                if a.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            } else {
                self.hub.show("exclamationmark.triangle.fill", .yellow, "Can't record", err, seconds: 6)
            }
        })
        hub.agents.onChange = { [weak self] s in
            guard let self else { return }
            switch s.state {
            case .done where s.detail != "Idle":
                self.hub.show("checkmark.seal.fill", .orange, "\(s.tool) finished", s.project, seconds: 5)
                if settings.agentSound { NSSound(named: "Glass")?.play() }
            case .waiting:
                self.hub.show("hand.raised.fill", .yellow, "\(s.tool) needs you", s.project, seconds: 6)
                if settings.agentSound { NSSound(named: "Funk")?.play() }
            default: break
            }
        }
    }

    private func registerHotkey(_ preset: HotkeyPreset) {
        hotKey = nil
        guard let mods = preset.modifiers else { return }
        hotKey = HotKey(keyCode: preset.keyCode, modifiers: mods, id: 1) { [weak self] in self?.island.toggleClipboard() }
        if hotKey == nil { hub.show("keyboard", .yellow, "Shortcut taken", preset.label, seconds: 5) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector?, _ key: String = "") {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
            it.target = self
            it.isEnabled = action != nil
            menu.addItem(it)
        }
        switch bridge.status {
        case .ok where player.hasTrack:
            add("\(player.title) — \(player.artist)", nil)
        case .ok, .noTab:
            add("Nothing playing in YouTube Music", nil)
        case .noChrome:
            add("Chrome isn't running", nil)
        case .jsDisabled:
            add("⚠︎ In Chrome, turn on: View → Developer →", nil)
            add("    Allow JavaScript from Apple Events", nil)
        case .notAllowed:
            add("⚠︎ Allow control of Chrome in System Settings →", nil)
            add("    Privacy & Security → Automation", nil)
            add("Open Automation Settings…", #selector(openAutomationSettings))
        case .error(let e):
            add("⚠︎ \(e.prefix(60))", nil)
        }
        menu.addItem(.separator())
        add("Open YouTube Music", #selector(openYouTubeMusicAction), "o")
        if bridge.status == .ok {
            add(player.isPlaying ? "Pause" : "Play", #selector(playPause), " ")
            add("Next", #selector(nextTrack))
            add("Previous", #selector(prevTrack))
        }
        menu.addItem(.separator())
        let shortcuts = NSMenuItem(title: "App Shortcuts", action: nil, keyEquivalent: "")
        let sm = NSMenu()
        for path in switcher.pinnedPaths {
            let it = NSMenuItem(title: FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: ""), action: #selector(unpinApp(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = path
            let icon = NSWorkspace.shared.icon(forFile: path); icon.size = NSSize(width: 16, height: 16)
            it.image = icon
            it.toolTip = "Click to remove"
            sm.addItem(it)
        }
        if !switcher.pinnedPaths.isEmpty {
            let hint = NSMenuItem(title: "Click an app to remove it", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            sm.addItem(hint)
            sm.addItem(.separator())
        }
        let addItem = NSMenuItem(title: "Add App…", action: #selector(addApp), keyEquivalent: "")
        addItem.target = self
        sm.addItem(addItem)
        shortcuts.submenu = sm
        menu.addItem(shortcuts)
        if !AXIsProcessTrusted() {
            add("Enable Window Switching…", #selector(enableWindowSwitching))
        }
        menu.addItem(.separator())
        add("Open Clipboard History (\(hub.settings.hotkey.label))", #selector(openClipboardHistory))
        add(hub.recorder.isRecording ? "Stop Screen Recording" : "Start Screen Recording", #selector(toggleRecording))
        let floatItem = NSMenuItem(title: "Floating Player", action: #selector(toggleFloating), keyEquivalent: "")
        floatItem.target = self
        floatItem.state = hub.settings.floatingPlayer ? .on : .off
        menu.addItem(floatItem)
        add("Settings…", #selector(openSettings), ",")
        menu.addItem(.separator())
        let clipItem = NSMenuItem(title: "Clipboard History", action: #selector(toggleClipboard), keyEquivalent: "")
        clipItem.target = self
        clipItem.state = hub.clips.enabled ? .on : .off
        menu.addItem(clipItem)
        if !hub.clips.clips.isEmpty { add("Clear Clipboard History", #selector(clearClipboard)) }
        if !hub.shelf.items.isEmpty { add("Clear File Tray", #selector(clearShelf)) }
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        add("Quit Notchbeat", #selector(quit), "q")
    }

    func openYouTubeMusic() {
        let ws = NSWorkspace.shared
        if let pwa = ws.urlForApplication(withBundleIdentifier: Self.pwaID) {
            ws.openApplication(at: pwa, configuration: NSWorkspace.OpenConfiguration())
        } else if let chrome = ws.urlForApplication(withBundleIdentifier: ChromeBridge.chromeID) {
            ws.open([URL(string: "https://music.youtube.com")!], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
        } else {
            ws.open(URL(string: "https://music.youtube.com")!)
        }
    }

    private var explained = false
    func explainChromeSetting(force: Bool = false) {
        guard force || !explained else { return }
        explained = true
        let a = NSAlert()
        a.messageText = "One Chrome setting needed"
        a.informativeText = "To show and control YouTube Music, Notchbeat needs Chrome to accept commands.\n\n1. Click a normal Chrome window (not the YouTube Music app window — its menu bar has no Developer menu).\n2. In the menu bar choose: View → Developer → Allow JavaScript from Apple Events.\n\nThis is a one-time step."
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    @objc func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose apps to add to the island"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { switcher.addPinned($0) }
    }

    @objc func unpinApp(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        switcher.pinnedPaths.removeAll { $0 == path }
    }

    @objc func enableWindowSwitching() { switcher.requestAccessibility() }
    @objc func toggleClipboard() { hub.clips.enabled.toggle() }
    @objc func openClipboardHistory() { island.toggleClipboard() }
    @objc func toggleRecording() { hub.recorder.toggle() }
    @objc func toggleFloating() { hub.settings.floatingPlayer.toggle() }
    @objc func openSettings() { SettingsWindow.shared.show() }
    @objc func clearClipboard() { hub.clips.clear() }
    @objc func clearShelf() { hub.shelf.clear() }

    @objc func openYouTubeMusicAction() { openYouTubeMusic() }
    @objc func playPause() { player.toggle() }
    @objc func nextTrack() { player.next() }
    @objc func prevTrack() { player.previous() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSSound.beep() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

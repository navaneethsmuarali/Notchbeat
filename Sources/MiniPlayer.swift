// Floating music player (three sizes, drag anywhere, two-finger swipe to skip) + shared music views.
import Cocoa
import SwiftUI

struct QueueItem: Identifiable, Equatable {
    let id: Int          // index in YouTube Music's queue
    let title: String
    let artist: String
    let art: String
}

/// Animated waveform in the accent colour. It follows play/pause; it is not real audio analysis.
struct Waveform: View {
    var playing: Bool
    var color: Color
    var bars = 36

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<bars, id: \.self) { i in
                    let x = Double(i)
                    let beat = pow(abs(sin(t * 2.1)), 6)                  // a soft "kick" every ~1.5s
                    let h = playing
                        ? 0.18 + 0.5 * abs(sin(t * 3.2 + x * 0.45)) * abs(cos(t * 1.3 + x * 0.21)) + 0.32 * beat * abs(sin(x * 0.7))
                        : 0.12
                    Capsule().fill(color.opacity(0.35 + 0.65 * h)).frame(maxWidth: .infinity).frame(maxHeight: .infinity).scaleEffect(y: min(1, h))
                }
            }
        }
    }
}

struct QueueList: View {
    @ObservedObject var p: Player
    var compact = false

    var body: some View {
        if p.queue.isEmpty {
            Text("Up Next appears once YouTube Music has a queue.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(p.queue) { q in
                        Button { p.playQueueItem(q) } label: {
                            HStack(spacing: 8) {
                                AsyncImage(url: URL(string: q.art)) { img in img.resizable().aspectRatio(contentMode: .fill) }
                                    placeholder: { Color.white.opacity(0.1) }
                                    .frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 5))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(q.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                    Text(q.artist).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(.horizontal, 6).frame(height: 32).contentShape(Rectangle())
                        }
                        .buttonStyle(RowStyle())
                    }
                }
            }
        }
    }
}

enum MiniSize: String { case mini, player, expanded
    var size: CGSize {
        switch self {
        case .mini: return CGSize(width: 280, height: 64)
        case .player: return CGSize(width: 300, height: 156)
        case .expanded: return CGSize(width: 300, height: 380)
        }
    }
}

final class MiniState: ObservableObject {
    @Published var size: MiniSize = MiniSize(rawValue: UserDefaults.standard.string(forKey: "miniSize") ?? "") ?? .player {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: "miniSize") }
    }
}

struct MiniPlayerView: View {
    @ObservedObject var p: Player
    @ObservedObject var st: MiniState
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        let accent = settings.accent(album: p.accent)
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.55))
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Artwork(image: p.artwork, size: st.size == .mini ? 44 : 56, corner: 10)
                        .onTapGesture { p.openApp() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.hasTrack ? p.title : "Nothing playing").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(p.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if st.size == .mini {
                        btn(p.isPlaying ? "pause.fill" : "play.fill", 18) { p.toggle() }
                        btn("forward.fill", 13) { p.next() }
                    }
                    Menu {
                        Button("Mini") { st.size = .mini }
                        Button("Player") { st.size = .player }
                        Button("Player + Up Next") { st.size = .expanded }
                        Divider()
                        Button("Hide Floating Player") { AppSettings.shared.floatingPlayer = false }
                    } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.white.opacity(0.6)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                }
                if st.size != .mini {
                    if settings.showWaveform { Waveform(playing: p.isPlaying, color: accent, bars: 28).frame(height: 16) }
                    TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                        let pos = p.livePosition(at: ctx.date)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.18))
                                Capsule().fill(accent).frame(width: p.duration > 0 ? g.size.width * pos / p.duration : 0)
                            }
                        }
                        .frame(height: 4)
                    }
                    HStack(spacing: 36) {
                        btn("backward.fill", 16) { p.previous() }
                        btn(p.isPlaying ? "pause.fill" : "play.fill", 24) { p.toggle() }
                        btn("forward.fill", 16) { p.next() }
                    }
                }
                if st.size == .expanded {
                    HStack {
                        Text("UP NEXT").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                        Spacer()
                    }
                    QueueList(p: p)
                }
            }
            .padding(12)
        }
        .frame(width: st.size.size.width, height: st.size.size.height)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: st.size)
    }

    private func btn(_ s: String, _ size: CGFloat, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: s).font(.system(size: size, weight: .bold)).foregroundStyle(.white).frame(width: 30, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

final class MiniPlayerController {
    private let panel: NSPanel
    private let state = MiniState()
    private let player: Player
    private var swipeX: CGFloat = 0
    private var swiped = false
    private var monitor: Any?
    private var sizeObserver: Any?

    init(player: Player) {
        self.player = player
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: state.size.size),
                        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 22
        blur.layer?.masksToBounds = true
        let host = FirstMouseHostingView(rootView: MiniPlayerView(p: player, st: state))
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor), host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor), host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        panel.contentView = blur

        if !panel.setFrameUsingName("NotchbeatMiniPlayer") {
            let vf = NSScreen.main?.visibleFrame ?? .zero
            panel.setFrameOrigin(NSPoint(x: vf.maxX - state.size.size.width - 24, y: vf.minY + 24))
        }
        panel.setFrameAutosaveName("NotchbeatMiniPlayer")

        // Keep the window the right size, growing/shrinking from its top edge.
        sizeObserver = state.$size.sink { [weak self] s in
            guard let self else { return }
            var f = self.panel.frame
            let top = f.maxY
            f.size = s.size
            f.origin.y = top - f.height
            self.panel.setFrame(f, display: true, animate: true)
        }

        // Two-finger horizontal swipe on the player skips tracks.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, e.window === self.panel else { return e }
            if e.phase == .began { self.swipeX = 0; self.swiped = false }
            if !self.swiped, abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) {
                self.swipeX += e.scrollingDeltaX
                if self.swipeX > 80 { self.player.previous(); self.swiped = true }
                else if self.swipeX < -80 { self.player.next(); self.swiped = true }
            }
            if e.phase == .ended { self.swipeX = 0 }
            return e
        }
    }

    var expandedQueueVisible: Bool { panel.isVisible && state.size == .expanded }

    func setVisible(_ on: Bool) { on ? panel.orderFrontRegardless() : panel.orderOut(nil) }
}

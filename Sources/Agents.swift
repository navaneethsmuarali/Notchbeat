// Coding agent activity (Claude Code, Codex), read from their local session logs. Nothing is sent anywhere.
import Cocoa
import SwiftUI

struct AgentSession: Identifiable, Equatable {
    enum State: Equatable { case working, waiting, done }
    let id: String
    let tool: String          // "Claude Code" / "Codex"
    let project: String
    let title: String?
    let state: State
    let detail: String
    let updated: Date
}

final class AgentMonitor: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    /// (session, new state) whenever a session stops working.
    var onChange: (AgentSession) -> Void = { _ in }

    private var timer: Timer?
    private let queue = DispatchQueue(label: "agents")
    private var previous: [String: AgentSession.State] = [:]
    private let home = FileManager.default.homeDirectoryForCurrentUser

    var working: AgentSession? { sessions.first { $0.state == .working } }

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.scan() }
        scan()
    }

    func scan() {
        guard AppSettings.shared.agentsEnabled else {
            if !sessions.isEmpty { sessions = [] }
            return
        }
        queue.async {
            let found = (self.claudeSessions() + self.codexSessions()).sorted { $0.updated > $1.updated }
            DispatchQueue.main.async { self.apply(found) }
        }
    }

    private func apply(_ found: [AgentSession]) {
        for s in found {
            if let before = previous[s.id], before == .working, s.state != .working { onChange(s) }
            if previous[s.id] != s.state { ChromeBridge.log("agent: \(s.tool) · \(s.project) → \(s.state) (\(s.detail.prefix(40)))") }
            previous[s.id] = s.state
        }
        if found != sessions { sessions = found }
    }

    // MARK: Claude Code (~/.claude/projects/<project>/<session>.jsonl)

    private func recentFiles(in dir: URL, ext: String, within: TimeInterval, recursive: Bool) -> [(URL, Date)] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        var out: [(URL, Date)] = []
        let cutoff = Date().addingTimeInterval(-within)
        if recursive {
            guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
            for case let u as URL in e where u.pathExtension == ext {
                if let m = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, m > cutoff { out.append((u, m)) }
            }
        } else {
            for sub in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? [] {
                // Skip whole project folders that haven't changed recently.
                if let m = try? sub.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, m < cutoff.addingTimeInterval(-86400) { continue }
                for f in (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: keys)) ?? [] where f.pathExtension == ext {
                    if let m = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, m > cutoff { out.append((f, m)) }
                }
            }
        }
        return out
    }

    private func tailLines(_ url: URL, bytes: Int = 256 * 1024) -> [String] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        let data = h.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    private func headLine(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: 64 * 1024)) ?? Data()
        return String(decoding: data, as: UTF8.self).split(separator: "\n", maxSplits: 1).first.map(String.init)
    }

    /// True if any Claude Code process currently has a shell child (i.e. a Bash tool call is executing).
    private func claudeHasShellChild() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,ppid=,comm="]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return true }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        var claude = Set<String>()
        var rows: [(pid: String, ppid: String, comm: String)] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 3 else { continue }
            rows.append((parts[0], parts[1], parts[2]))
            if (parts[2] as NSString).lastPathComponent.lowercased().hasPrefix("claude") { claude.insert(parts[0]) }
        }
        let shells: Set<String> = ["zsh", "bash", "sh", "fish", "-zsh", "-bash"]
        return rows.contains { claude.contains($0.ppid) && shells.contains(($0.comm as NSString).lastPathComponent) }
    }

    private func claudeSessions() -> [AgentSession] {
        let root = home.appendingPathComponent(".claude/projects")
        var out: [AgentSession] = []
        let recent = recentFiles(in: root, ext: "jsonl", within: 15 * 60, recursive: false)
        if recent.isEmpty { return [] }
        let shellRunning = claudeHasShellChild()
        for (file, mtime) in recent {
            let lines = tailLines(file)
            var last: [String: Any]?
            var title: String?
            var cwd: String?
            for line in lines.reversed() {
                guard let d = line.data(using: .utf8), let e = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                let type = e["type"] as? String
                if title == nil, type == "ai-title" { title = e["aiTitle"] as? String }
                if cwd == nil { cwd = e["cwd"] as? String }
                if last == nil, type == "user" || type == "assistant" {
                    // Skip sidechain (sub-agent) entries; they don't describe the main session's state.
                    if (e["isSidechain"] as? Bool) == true { continue }
                    last = e
                }
                if last != nil && title != nil && cwd != nil { break }
            }
            guard let entry = last else { continue }
            let idle = Date().timeIntervalSince(mtime)
            let msg = entry["message"] as? [String: Any] ?? [:]
            let content = msg["content"] as? [[String: Any]] ?? []
            let tool = content.last { ($0["type"] as? String) == "tool_use" }
            var state: AgentSession.State
            var detail: String
            if (entry["type"] as? String) == "assistant", (msg["stop_reason"] as? String) == "end_turn" {
                state = .done; detail = "Finished — your turn"
            } else if let tool, (entry["type"] as? String) == "assistant" {
                let name = tool["name"] as? String ?? "tool"
                let input = tool["input"] as? [String: Any] ?? [:]
                let target = (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
                    ?? (input["description"] as? String) ?? (input["command"] as? String).map { String($0.prefix(40)) } ?? ""
                // A pending tool call is either running or waiting for your approval. Commands run in a shell, so a live
                // shell under Claude means "running"; file edits finish instantly, so a stuck one is almost always a prompt.
                let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
                let needsApproval: Bool
                if name == "Bash" { needsApproval = idle > 8 && !shellRunning }
                else if editTools.contains(name) { needsApproval = idle > 8 }
                else { needsApproval = false }
                if needsApproval {
                    state = .waiting; detail = "Waiting for your approval (\(name))"
                } else {
                    state = .working; detail = target.isEmpty ? name : "\(name) · \(target)"
                }
            } else if idle < 120 {
                state = .working; detail = "Thinking…"
            } else {
                state = .done; detail = "Idle"
            }
            let project = cwd.map { ($0 as NSString).lastPathComponent } ?? file.deletingLastPathComponent().lastPathComponent
            out.append(AgentSession(id: file.path, tool: "Claude Code", project: project, title: title, state: state, detail: detail, updated: mtime))
        }
        return out
    }

    // MARK: Codex (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl) — activity only

    private func codexSessions() -> [AgentSession] {
        let root = home.appendingPathComponent(".codex/sessions")
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let cal = Calendar.current
        let today = cal.dateComponents([.year, .month, .day], from: Date())
        let dayDir = root.appendingPathComponent(String(format: "%04d/%02d/%02d", today.year!, today.month!, today.day!))
        var out: [AgentSession] = []
        for (file, mtime) in recentFiles(in: dayDir, ext: "jsonl", within: 15 * 60, recursive: true) {
            var cwd: String?
            if let first = headLine(file), let d = first.data(using: .utf8),
               let e = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let payload = e["payload"] as? [String: Any] { cwd = payload["cwd"] as? String }
            let idle = Date().timeIntervalSince(mtime)
            out.append(AgentSession(id: file.path, tool: "Codex", project: cwd.map { ($0 as NSString).lastPathComponent } ?? "Codex",
                                    title: nil, state: idle < 10 ? .working : .done,
                                    detail: idle < 10 ? "Working…" : "Idle", updated: mtime))
        }
        return out
    }
}

struct Spinner: View {
    var color: Color = .orange
    @State private var spin = false
    var body: some View {
        Circle().trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}

struct AgentsView: View {
    @ObservedObject var agents: AgentMonitor

    var body: some View {
        if !AppSettings.shared.agentsEnabled {
            placeholder("Agent activity is turned off in Settings.")
        } else if agents.sessions.isEmpty {
            placeholder("No Claude Code or Codex sessions in the last 15 minutes.")
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(agents.sessions) { row($0) }
                }
            }
        }
    }

    private func placeholder(_ t: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 20)).foregroundStyle(.white.opacity(0.5))
            Text(t).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ s: AgentSession) -> some View {
        HStack(spacing: 10) {
            Group {
                switch s.state {
                case .working: Spinner(color: s.tool == "Codex" ? .cyan : .orange)
                case .waiting: Image(systemName: "hand.raised.fill").foregroundStyle(.yellow)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(s.tool) · \(s.project)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(s.title.map { "\($0) — \(s.detail)" } ?? s.detail)
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer()
            Text(s.updated, style: .relative).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).lineLimit(1).frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }
}

// Quick notes: a scratchpad in the island that saves as you type.
import Cocoa
import SwiftUI

final class NotesModel: ObservableObject {
    @Published var text: String { didSet { scheduleSave() } }
    private var saveWork: DispatchWorkItem?
    private let file: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Notchbeat")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.txt")
    }()

    init() { text = (try? String(contentsOf: file, encoding: .utf8)) ?? "" }

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            try? self.text.write(to: self.file, atomically: true, encoding: .utf8)
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Creates a new note in Apple Notes (macOS asks once for permission to control Notes).
    func sendToAppleNotes(done: @escaping (Bool) -> Void) {
        let body = text
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
        let script = """
        on run argv
          tell application "Notes" to make new note with properties {body:(item 1 of argv)}
        end run
        """
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script, "<div>" + body + "</div>"]
            p.standardError = FileHandle.nullDevice
            p.standardOutput = FileHandle.nullDevice
            let ok = (try? p.run()) != nil && { p.waitUntilExit(); return p.terminationStatus == 0 }()
            DispatchQueue.main.async { done(ok) }
        }
    }
}

struct NotesView: View {
    @ObservedObject var notes: NotesModel
    @State private var status: String?

    var body: some View {
        VStack(spacing: 6) {
            TextEditor(text: $notes.text)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
                .overlay(alignment: .topLeading) {
                    if notes.text.isEmpty {
                        Text("Jot something down…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
                            .padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false)
                    }
                }
            HStack(spacing: 12) {
                if let status { Text(status).font(.system(size: 10, weight: .semibold)).foregroundStyle(.green) }
                Spacer()
                small("Copy") { notes.copy(); flash("Copied") }
                small("Save to Apple Notes") {
                    notes.sendToAppleNotes { ok in flash(ok ? "Saved to Notes" : "Couldn't reach Notes") }
                }
                small("Clear") { notes.text = "" }
            }
        }
    }

    private func small(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(t, action: a).buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            .disabled(notes.text.isEmpty)
    }

    private func flash(_ s: String) {
        status = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if status == s { status = nil } }
    }
}

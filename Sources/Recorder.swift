// Screen recording from the island (ScreenCaptureKit). The island itself is left out of the video.
import Cocoa
import ScreenCaptureKit

final class Recorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var lastError: String?
    var onFinished: (URL) -> Void = { _ in }

    private var stream: SCStream?
    private var output: AnyObject?
    private var currentURL: URL?

    static var folder: URL {
        let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Notchbeat Recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var supported: Bool { if #available(macOS 15.0, *) { return true } else { return false } }

    func toggle() { isRecording ? stop() : start() }

    func start() {
        guard !isRecording else { return }
        guard #available(macOS 15.0, *) else { lastError = "Screen recording needs macOS 15 or newer"; return }
        lastError = nil
        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
                let screenID = (mouseScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                guard let display = content.displays.first(where: { $0.displayID == screenID }) ?? content.displays.first else {
                    throw NSError(domain: "Notchbeat", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
                }
                let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
                let cfg = SCStreamConfiguration()
                let scale = Int(mouseScreen?.backingScaleFactor ?? 2)
                cfg.width = display.width * scale
                cfg.height = display.height * scale
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                cfg.showsCursor = true
                cfg.capturesAudio = AppSettings.shared.recordAudio
                cfg.queueDepth = 6

                let name = "Recording " + Self.stamp() + ".mov"
                let url = Self.folder.appendingPathComponent(name)
                let rc = SCRecordingOutputConfiguration()
                rc.outputURL = url
                rc.outputFileType = .mov
                rc.videoCodecType = .h264
                let rec = SCRecordingOutput(configuration: rc, delegate: self)

                let s = SCStream(filter: filter, configuration: cfg, delegate: nil)
                try s.addRecordingOutput(rec)
                try await s.startCapture()
                stream = s
                output = rec
                currentURL = url
                startedAt = Date()
                isRecording = true
            } catch {
                lastError = (error as NSError).code == -3801
                    ? "Allow Notchbeat under Privacy & Security → Screen Recording, then try again"
                    : error.localizedDescription
                isRecording = false
            }
        }
    }

    func stop() {
        guard isRecording, let s = stream else { return }
        Task { @MainActor in
            try? await s.stopCapture()
            isRecording = false
            startedAt = nil
            stream = nil
            output = nil
            // The file is finished once capture stops; give the writer a beat to close it.
            if let url = currentURL {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    if FileManager.default.fileExists(atPath: url.path) { self?.onFinished(url) }
                }
            }
            currentURL = nil
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: Date())
    }

    static func elapsed(since d: Date?, now: Date) -> String {
        guard let d else { return "0:00" }
        let s = Int(now.timeIntervalSince(d))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

@available(macOS 15.0, *)
extension Recorder: SCRecordingOutputDelegate {
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        DispatchQueue.main.async { self.lastError = error.localizedDescription }
    }
}

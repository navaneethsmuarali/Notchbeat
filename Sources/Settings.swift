// User settings + the Settings window.
import Cocoa
import SwiftUI
import ServiceManagement
import Carbon.HIToolbox

enum Finish: String, CaseIterable, Identifiable {
    case black, glass
    var id: String { rawValue }
    var label: String { self == .black ? "Black" : "Glass" }
}

enum Glance: String, CaseIterable, Identifiable {
    case none, time, date, nextEvent, battery, cpu, memory
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Nothing"
        case .time: return "Time"
        case .date: return "Date"
        case .nextEvent: return "Next event"
        case .battery: return "Battery"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        }
    }
}

enum HotkeyPreset: String, CaseIterable, Identifiable {
    case shiftCmdV, optCmdV, ctrlOptV, ctrlCmdV, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .shiftCmdV: return "⇧⌘V"
        case .optCmdV: return "⌥⌘V"
        case .ctrlOptV: return "⌃⌥V"
        case .ctrlCmdV: return "⌃⌘V"
        case .off: return "Off"
        }
    }
    var keyCode: UInt32 { UInt32(kVK_ANSI_V) }
    var modifiers: UInt32? {
        switch self {
        case .shiftCmdV: return UInt32(shiftKey | cmdKey)
        case .optCmdV: return UInt32(optionKey | cmdKey)
        case .ctrlOptV: return UInt32(controlKey | optionKey)
        case .ctrlCmdV: return UInt32(controlKey | cmdKey)
        case .off: return nil
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var finish: Finish { didSet { d.set(finish.rawValue, forKey: "finish") } }
    @Published var useAlbumColor: Bool { didSet { d.set(useAlbumColor, forKey: "useAlbumColor") } }
    @Published var accentHex: String { didSet { d.set(accentHex, forKey: "accentHex") } }
    @Published var glanceLeft: Glance { didSet { d.set(glanceLeft.rawValue, forKey: "glanceLeft") } }
    @Published var glanceRight: Glance { didSet { d.set(glanceRight.rawValue, forKey: "glanceRight") } }
    @Published var showBubbles: Bool { didSet { d.set(showBubbles, forKey: "showBubbles") } }
    @Published var showWaveform: Bool { didSet { d.set(showWaveform, forKey: "showWaveform") } }
    @Published var hiddenTabs: Set<String> { didSet { d.set(Array(hiddenTabs), forKey: "hiddenTabs") } }
    @Published var hotkey: HotkeyPreset { didSet { d.set(hotkey.rawValue, forKey: "hotkey") } }
    @Published var lowBattery: Int { didSet { d.set(lowBattery, forKey: "lowBattery") } }
    @Published var deviceAlerts: Bool { didSet { d.set(deviceAlerts, forKey: "deviceAlerts") } }
    @Published var recordAudio: Bool { didSet { d.set(recordAudio, forKey: "recordAudio") } }
    @Published var agentsEnabled: Bool { didSet { d.set(agentsEnabled, forKey: "agentsEnabled") } }
    @Published var agentSound: Bool { didSet { d.set(agentSound, forKey: "agentSound") } }
    @Published var floatingPlayer: Bool { didSet { d.set(floatingPlayer, forKey: "floatingPlayer") } }

    private init() {
        finish = Finish(rawValue: d.string(forKey: "finish") ?? "") ?? .black
        useAlbumColor = d.object(forKey: "useAlbumColor") as? Bool ?? true
        accentHex = d.string(forKey: "accentHex") ?? "#FF3B5C"
        glanceLeft = Glance(rawValue: d.string(forKey: "glanceLeft") ?? "") ?? .time
        glanceRight = Glance(rawValue: d.string(forKey: "glanceRight") ?? "") ?? .battery
        showBubbles = d.object(forKey: "showBubbles") as? Bool ?? true
        showWaveform = d.object(forKey: "showWaveform") as? Bool ?? true
        hiddenTabs = Set(d.stringArray(forKey: "hiddenTabs") ?? [])
        hotkey = HotkeyPreset(rawValue: d.string(forKey: "hotkey") ?? "") ?? .shiftCmdV
        lowBattery = d.object(forKey: "lowBattery") as? Int ?? 20
        deviceAlerts = d.object(forKey: "deviceAlerts") as? Bool ?? true
        recordAudio = d.object(forKey: "recordAudio") as? Bool ?? false
        agentsEnabled = d.object(forKey: "agentsEnabled") as? Bool ?? true
        agentSound = d.object(forKey: "agentSound") as? Bool ?? true
        floatingPlayer = d.object(forKey: "floatingPlayer") as? Bool ?? false
    }

    var customAccent: Color { Color(nsColor: NSColor(hex: accentHex) ?? .systemPink) }
    func accent(album: Color) -> Color { useAlbumColor ? album : customAccent }
    var glanceCount: Int { (glanceLeft == .none ? 0 : 1) + (glanceRight == .none ? 0 : 1) }

    func isTabOn(_ t: IslandTab) -> Bool { t == .music || !hiddenTabs.contains(t.rawValue) }
    func setTab(_ t: IslandTab, on: Bool) {
        if on { hiddenTabs.remove(t.rawValue) } else { hiddenTabs.insert(t.rawValue) }
    }

    static let presets = ["#FF3B5C", "#FF9F0A", "#FFD60A", "#30D158", "#64D2FF", "#0A84FF", "#5E5CE6", "#BF5AF2", "#FF375F", "#AC8E68", "#FFFFFF", "#8E8E93"]
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

struct SettingsView: View {
    @ObservedObject var s: AppSettings
    @State private var loginOn = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Island finish", selection: $s.finish) {
                    ForEach(Finish.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Use album artwork colour", isOn: $s.useAlbumColor)
                if !s.useAlbumColor {
                    HStack(spacing: 6) {
                        ForEach(AppSettings.presets, id: \.self) { hex in
                            Circle().fill(Color(nsColor: NSColor(hex: hex)!))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(s.accentHex == hex ? 0.9 : 0.15), lineWidth: s.accentHex == hex ? 2 : 1))
                                .onTapGesture { s.accentHex = hex }
                        }
                        ColorPicker("", selection: Binding(
                            get: { s.customAccent },
                            set: { s.accentHex = NSColor($0).hexString }
                        ), supportsOpacity: false).labelsHidden()
                    }
                }
                Toggle("Waveform in the music player", isOn: $s.showWaveform)
            }
            Section("Island") {
                Picker("Left glance", selection: $s.glanceLeft) { ForEach(Glance.allCases) { Text($0.label).tag($0) } }
                Picker("Right glance", selection: $s.glanceRight) { ForEach(Glance.allCases) { Text($0.label).tag($0) } }
                Toggle("App bubbles when expanded", isOn: $s.showBubbles)
            }
            Section("Tabs") {
                ForEach(IslandTab.allCases.filter { $0 != .music }, id: \.self) { t in
                    Toggle(t.title, isOn: Binding(get: { s.isTabOn(t) }, set: { s.setTab(t, on: $0) }))
                }
            }
            Section("Clipboard") {
                Picker("Open clipboard history", selection: $s.hotkey) { ForEach(HotkeyPreset.allCases) { Text($0.label).tag($0) } }
                Text("Use ↑ ↓ to choose and Return to paste. Pasting needs Accessibility permission.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Devices") {
                Toggle("Show when Bluetooth devices connect and run low", isOn: $s.deviceAlerts)
                Stepper("Low battery alert at \(s.lowBattery)%", value: $s.lowBattery, in: 5...50, step: 5)
            }
            Section("Screen recording") {
                Toggle("Record system audio", isOn: $s.recordAudio)
                Button("Open Recordings Folder") { NSWorkspace.shared.open(Recorder.folder) }
            }
            Section("Coding agents") {
                Toggle("Show Claude Code and Codex activity", isOn: $s.agentsEnabled)
                Toggle("Play a sound when an agent finishes", isOn: $s.agentSound)
            }
            Section("General") {
                Toggle("Floating music player", isOn: $s.floatingPlayer)
                Toggle("Launch at login", isOn: Binding(get: { loginOn }, set: { on in
                    do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { NSSound.beep() }
                    loginOn = SMAppService.mainApp.status == .enabled
                }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
    }
}

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(s: AppSettings.shared)))
            w.title = "Notchbeat Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

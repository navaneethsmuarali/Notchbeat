// Bluetooth devices: AirPods / headphones / keyboards / mice battery levels, connect and low-battery alerts.
import Foundation

struct BTDevice: Identifiable, Equatable {
    let id: String          // name (system_profiler keys devices by name)
    let kind: String        // device_minorType, e.g. Headphones, Keyboard, Mouse
    let levels: [(String, Int)]

    static func == (a: BTDevice, b: BTDevice) -> Bool { a.id == b.id && a.levels.map(\.1) == b.levels.map(\.1) }

    var lowest: Int { levels.map(\.1).min() ?? 100 }
    var shortName: String { id.count > 16 ? String(id.prefix(15)) + "…" : id }
    var levelText: String {
        if levels.count == 1 { return "\(levels[0].1)%" }
        return levels.map { "\($0.0)\($0.1)" }.joined(separator: " ")
    }
    var symbol: String {
        let k = kind.lowercased(), n = id.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if k.contains("headphone") || k.contains("headset") { return "headphones" }
        if k.contains("keyboard") { return "keyboard" }
        if k.contains("mouse") { return "computermouse" }
        if k.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if k.contains("speaker") { return "hifispeaker" }
        if k.contains("gamepad") || k.contains("joystick") { return "gamecontroller" }
        return "dot.radiowaves.left.and.right"
    }
}

final class DeviceMonitor: ObservableObject {
    @Published private(set) var devices: [BTDevice] = []
    var onConnect: (BTDevice) -> Void = { _ in }
    var onLow: (BTDevice) -> Void = { _ in }

    private var known: Set<String>?
    private var warned = Set<String>()
    private var timer: Timer?
    private let queue = DispatchQueue(label: "devices")

    init() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.scan() }
    }

    func scan() {
        queue.async {
            let found = Self.read()
            DispatchQueue.main.async { self.update(found) }
        }
    }

    private func update(_ found: [BTDevice]) {
        let names = Set(found.map(\.id))
        if let known {
            for d in found where !known.contains(d.id) { onConnect(d) }
        }
        known = names
        let threshold = AppSettings.shared.lowBattery
        for d in found {
            if d.lowest <= threshold && !warned.contains(d.id) { warned.insert(d.id); onLow(d) }
            if d.lowest > threshold + 5 { warned.remove(d.id) }
        }
        if found != devices { devices = found }
    }

    /// system_profiler is quick (~0.1s) and needs no Bluetooth permission.
    private static func read() -> [BTDevice] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var result: [BTDevice] = []
        for sec in sections {
            for entry in sec["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let props = value as? [String: Any] else { continue }
                    var levels: [(String, Int)] = []
                    for (key, label) in [("device_batteryLevelLeft", "L"), ("device_batteryLevelRight", "R"),
                                         ("device_batteryLevelCase", "C"), ("device_batteryLevelMain", "")] {
                        if let s = props[key] as? String, let v = Int(s.replacingOccurrences(of: "%", with: "")) {
                            levels.append((label, v))
                        }
                    }
                    // Devices that report no battery (speakers, phones) still count as "connected" for the connect alert.
                    result.append(BTDevice(id: name, kind: props["device_minorType"] as? String ?? "", levels: levels))
                }
            }
        }
        return result.sorted { $0.id < $1.id }
    }
}

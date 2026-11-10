// System stats: CPU, memory, network and battery with rolling graphs.
import Cocoa
import SwiftUI
import IOKit.ps

final class SystemStats: ObservableObject {
    @Published private(set) var cpu: Double = 0              // 0...1
    @Published private(set) var memUsed: Double = 0          // bytes
    let memTotal = Double(ProcessInfo.processInfo.physicalMemory)
    @Published private(set) var netIn: Double = 0            // bytes/s
    @Published private(set) var netOut: Double = 0
    @Published private(set) var battery: Int?
    @Published private(set) var charging = false
    @Published private(set) var onAC = true
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memHistory: [Double] = []
    @Published private(set) var netHistory: [Double] = []

    /// (percent, plugged in) when the power adapter is connected/disconnected.
    var onPowerChange: (Int, Bool) -> Void = { _, _ in }
    var onLowBattery: (Int) -> Void = { _ in }

    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastNet: (inB: UInt64, outB: UInt64, at: Date)?
    private var timer: Timer?
    private var warnedLow = false
    private let historyLength = 40

    var memFraction: Double { memTotal > 0 ? memUsed / memTotal : 0 }

    init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
    }

    private func push(_ v: Double, _ arr: inout [Double]) {
        arr.append(v)
        if arr.count > historyLength { arr.removeFirst(arr.count - historyLength) }
    }

    private func sample() {
        // CPU (all cores together)
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        if kr == KERN_SUCCESS {
            let user = UInt64(load.cpu_ticks.0), sys = UInt64(load.cpu_ticks.1), idle = UInt64(load.cpu_ticks.2), nice = UInt64(load.cpu_ticks.3)
            let busy = user + sys + nice, total = busy + idle
            if let last = lastTicks, total > last.total {
                cpu = Double(busy - last.busy) / Double(total - last.total)
                push(cpu, &cpuHistory)
            }
            lastTicks = (busy, total)
        }

        // Memory, the way Activity Monitor counts "Memory Used"
        var vm = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr2 = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount) }
        }
        if kr2 == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            let app = Double(vm.internal_page_count) - Double(vm.purgeable_count)
            memUsed = (app + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
            push(memFraction, &memHistory)
        }

        // Network throughput across physical interfaces
        var inB: UInt64 = 0, outB: UInt64 = 0
        var ifap: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifap) == 0 {
            var p = ifap
            while let i = p {
                let name = String(cString: i.pointee.ifa_name)
                if let addr = i.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                   name.hasPrefix("en") || name.hasPrefix("pdp_ip"), let data = i.pointee.ifa_data {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    inB += UInt64(d.ifi_ibytes); outB += UInt64(d.ifi_obytes)
                }
                p = i.pointee.ifa_next
            }
            freeifaddrs(ifap)
        }
        let now = Date()
        if let last = lastNet, inB >= last.inB, outB >= last.outB {
            let dt = max(0.5, now.timeIntervalSince(last.at))
            netIn = Double(inB - last.inB) / dt
            netOut = Double(outB - last.outB) / dt
            push(netIn + netOut, &netHistory)
        }
        lastNet = (inB, outB, now)

        // Battery
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
           let src = list.first,
           let desc = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
           let cur = desc[kIOPSCurrentCapacityKey] as? Int, let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
            let pct = Int((Double(cur) / Double(max) * 100).rounded())
            let ac = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let wasAC = onAC, hadBattery = battery != nil
            battery = pct
            charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            onAC = ac
            if hadBattery && ac != wasAC { onPowerChange(pct, ac) }
            let threshold = AppSettings.shared.lowBattery
            if !ac && pct <= threshold && !warnedLow { warnedLow = true; onLowBattery(pct) }
            if ac || pct > threshold + 5 { warnedLow = false }
        } else {
            battery = nil
        }
    }

    static func rate(_ bps: Double) -> String {
        if bps < 1024 { return "\(Int(bps)) B/s" }
        if bps < 1024 * 1024 { return String(format: "%.0f KB/s", bps / 1024) }
        return String(format: "%.1f MB/s", bps / 1024 / 1024)
    }
    static func bytes(_ b: Double) -> String { String(format: "%.1f GB", b / 1_073_741_824) }
}

struct Sparkline: View {
    var values: [Double]
    var color: Color
    var maxValue: Double? = nil

    var body: some View {
        GeometryReader { g in
            let top = max(maxValue ?? (values.max() ?? 1), 0.0001)
            let step = g.size.width / CGFloat(max(1, 39))
            let pts = values.enumerated().map { i, v in
                CGPoint(x: g.size.width - CGFloat(values.count - 1 - i) * step, y: g.size.height * (1 - CGFloat(min(v / top, 1))))
            }
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: g.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { p in p.addLines(pts) }.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let history: [Double]
    let color: Color
    var maxValue: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(value).font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
            }
            Sparkline(values: history, color: color, maxValue: maxValue).frame(height: 22)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}

struct StatsView: View {
    @ObservedObject var stats: SystemStats
    @ObservedObject var devices: DeviceMonitor

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                StatTile(title: "CPU", value: "\(Int(stats.cpu * 100))%", history: stats.cpuHistory, color: .orange, maxValue: 1)
                StatTile(title: "MEMORY", value: SystemStats.bytes(stats.memUsed), history: stats.memHistory, color: .purple, maxValue: 1)
            }
            HStack(spacing: 6) {
                StatTile(title: "NETWORK", value: "↓\(SystemStats.rate(stats.netIn))", history: stats.netHistory, color: .cyan)
                batteryTile
            }
            devicesRow
        }
    }

    private var batteryTile: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("BATTERY").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                if let b = stats.battery {
                    Text("\(b)%\(stats.charging ? " ⚡︎" : "")").font(.system(size: 11, weight: .bold).monospacedDigit()).foregroundStyle(.white)
                } else {
                    Text("Power adapter").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill((stats.battery ?? 100) <= 20 && !stats.onAC ? Color.red : Color.green)
                        .frame(width: g.size.width * CGFloat(stats.battery ?? 100) / 100)
                }
            }
            .frame(height: 8)
            .padding(.vertical, 7)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }

    private var devicesRow: some View {
        HStack(spacing: 6) {
            let withBattery = devices.devices.filter { !$0.levels.isEmpty }
            if withBattery.isEmpty {
                Text("No Bluetooth devices with battery info connected")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(withBattery) { d in
                    HStack(spacing: 4) {
                        Image(systemName: d.symbol).font(.system(size: 10))
                        Text(d.shortName).lineLimit(1)
                        Text(d.levelText).fontWeight(.bold).monospacedDigit()
                            .foregroundStyle(d.lowest <= AppSettings.shared.lowBattery ? Color.red : Color.white)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

import Darwin
import Foundation
import IOKit.ps
import SwiftUI

/// CPU・メモリ・ディスク・バッテリー・通信量を1秒ごとに集める。
@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var now = Date()
    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryUsed: Double = 0
    @Published private(set) var memoryTotal: Double = 1
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var diskUsed: Double = 0
    @Published private(set) var diskTotal: Double = 1
    @Published private(set) var batteryLevel: Double?
    @Published private(set) var isCharging = false
    @Published private(set) var download: Double = 0
    @Published private(set) var upload: Double = 0
    @Published private(set) var downloadHistory: [Double] = []
    @Published private(set) var uploadHistory: [Double] = []

    let hostName = ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "")
    let processorCount = ProcessInfo.processInfo.processorCount
    private(set) var ipAddress = "—"
    var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private static let historyLength = 60

    private var previousTicks: (busy: Double, total: Double)?
    private var previousTraffic: (input: UInt64, output: UInt64, at: TimeInterval)?
    private var ticker: Timer?

    func start() {
        guard ticker == nil else { return }
        memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        sample()
        let timer = Timer(timeInterval: HUDConfig.systemInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func sample() {
        now = Date()
        cpu = sampleCPU()
        append(cpu, to: &cpuHistory)

        memoryUsed = sampleMemory()
        append(memoryTotal > 0 ? memoryUsed / memoryTotal : 0, to: &memoryHistory)

        let storage = sampleStorage()
        diskUsed = storage.used
        diskTotal = storage.total

        let power = samplePower()
        batteryLevel = power.level
        isCharging = power.charging

        sampleNetwork()
        ipAddress = Self.primaryAddress() ?? "—"
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    // MARK: - CPU

    private func sampleCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return cpu }

        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { previousTicks = (busy, total) }

        guard let previous = previousTicks else { return 0 }
        let busyDelta = busy - previous.busy
        let totalDelta = total - previous.total
        guard totalDelta > 0 else { return cpu }
        return min(1, max(0, busyDelta / totalDelta))
    }

    // MARK: - メモリ

    private func sampleMemory() -> Double {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return memoryUsed }
        let pageSize = Double(vm_kernel_page_size)
        let used = Double(statistics.active_count) + Double(statistics.wire_count) + Double(statistics.compressor_page_count)
        return used * pageSize
    }

    // MARK: - ストレージ

    private func sampleStorage() -> (used: Double, total: Double) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return (diskUsed, diskTotal) }
        let available = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
        return (max(0, Double(total) - available), Double(total))
    }

    // MARK: - バッテリー

    private func samplePower() -> (level: Double?, charging: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, false)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey as String] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey as String] as? Int,
                  maximum > 0 else { continue }
            let state = description[kIOPSPowerSourceStateKey as String] as? String
            return (Double(current) / Double(maximum), state == (kIOPSACPowerValue as String))
        }
        return (nil, false)
    }

    // MARK: - ネットワーク

    private func sampleNetwork() {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return }
        defer { freeifaddrs(pointer) }

        var input: UInt64 = 0
        var output: UInt64 = 0
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard interface.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.pointee.ifa_data else { continue }
            let statistics = data.assumingMemoryBound(to: if_data.self).pointee
            input += UInt64(statistics.ifi_ibytes)
            output += UInt64(statistics.ifi_obytes)
        }

        let timestamp = ProcessInfo.processInfo.systemUptime
        defer { previousTraffic = (input, output, timestamp) }
        guard let previous = previousTraffic else { return }
        let elapsed = timestamp - previous.at
        guard elapsed > 0, input >= previous.input, output >= previous.output else { return }

        download = Double(input - previous.input) / elapsed
        upload = Double(output - previous.output) / elapsed
        append(download, to: &downloadHistory)
        append(upload, to: &uploadHistory)
    }

    private static func primaryAddress() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var fallback: String?
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(cString: host)
            let name = String(cString: interface.pointee.ifa_name)
            if name == "en0" { return text }
            if fallback == nil { fallback = text }
        }
        return fallback
    }
}

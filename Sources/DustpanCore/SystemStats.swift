import Darwin
import Foundation
import IOKit

public enum MemoryPressure: Int, Sendable {
    case normal = 1, warning = 2, critical = 4

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Elevated"
        case .critical: "Critical"
        }
    }
}

public struct SystemSnapshot: Sendable, Equatable {
    /// 0...1 across all cores.
    public var cpu: Double
    /// 0...1, nil when the GPU doesn't report utilization.
    public var gpu: Double?
    /// Activity Monitor's "Memory Used": app memory + wired + compressed.
    public var memoryUsed: Int64
    public var memoryTotal: Int64
    public var swapUsed: Int64
    public var pressure: MemoryPressure

    public var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
}

/// Samples CPU, GPU and memory through Mach / IOKit — no subprocesses, cheap enough to run every few seconds.
public final class SystemSampler: @unchecked Sendable {
    private var previousTicks: (busy: UInt64, total: UInt64)?

    public init() {}

    public func sample() -> SystemSnapshot {
        let memory = Self.memory()
        return SystemSnapshot(cpu: cpu(), gpu: Self.gpu(), memoryUsed: memory.used,
                              memoryTotal: Int64(ProcessInfo.processInfo.physicalMemory),
                              swapUsed: Self.swapUsed(), pressure: Self.pressure())
    }

    /// CPU usage since the previous call (the first call measures since boot).
    func cpu() -> Double {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return 0 }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }

        var busy: UInt64 = 0, total: UInt64 = 0
        for cpu in 0..<Int(count) {
            let base = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(info[base + Int(CPU_STATE_USER)])
            let system = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            busy += user + system + nice
            total += user + system + nice + idle
        }
        defer { previousTicks = (busy, total) }
        guard let prev = previousTicks, total > prev.total else { return total > 0 ? Double(busy) / Double(total) : 0 }
        return Double(busy - prev.busy) / Double(total - prev.total)
    }

    static func memory() -> (used: Int64, free: Int64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        let page = Int64(vm_kernel_page_size)
        let app = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
        let used = (app + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        return (used, Int64(stats.free_count) * page)
    }

    static func swapUsed() -> Int64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Int64(usage.xsu_used)
    }

    static func pressure() -> MemoryPressure {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(rawValue: Int(level)) ?? .normal
    }

    /// Reads "Device Utilization %" from the GPU driver's performance statistics (works without root).
    static func gpu() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var best: Double?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let perf = dict["PerformanceStatistics"] as? [String: Any],
                  let util = (perf["Device Utilization %"] ?? perf["GPU Activity(%)"]) as? NSNumber
            else { continue }
            best = max(best ?? 0, util.doubleValue / 100)
        }
        return best
    }
}

// MARK: - Processes

public struct ProcessUsage: Identifiable, Hashable, Sendable {
    public let pid: Int32
    /// Full executable path.
    public let path: String
    /// % of one core, like Activity Monitor (can exceed 100).
    public let cpu: Double
    public let memory: Int64
    public var id: Int32 { pid }

    public var name: String { (path as NSString).lastPathComponent }

    /// Outermost `.app` bundle containing the executable — so Chrome's dozens of helpers count as Chrome.
    public var appBundle: URL? {
        guard let range = path.range(of: ".app/") else { return nil }
        return URL(fileURLWithPath: String(path[..<range.lowerBound]) + ".app")
    }
}

/// Processes rolled up by app.
public struct ProcessGroup: Identifiable, Hashable, Sendable {
    public let name: String
    public let appBundle: URL?
    public let cpu: Double
    public let memory: Int64
    public let pids: [Int32]
    public var id: String { appBundle?.path ?? name }
}

public enum ProcessList {
    /// Snapshot of every process via `ps`. Memory is resident size — close to, not identical to, Activity Monitor's footprint.
    public static func all() -> [ProcessUsage] {
        guard let out = Shell.run(["/bin/ps", "-Ao", "pid=,pcpu=,rss=,comm="]) else { return [] }
        return out.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let cpu = Double(parts[1]), let rss = Int64(parts[2]) else { return nil }
            return ProcessUsage(pid: pid, path: String(parts[3]), cpu: cpu, memory: rss * 1024)
        }
    }

    public static func grouped(_ processes: [ProcessUsage]) -> [ProcessGroup] {
        Dictionary(grouping: processes) { $0.appBundle?.path ?? $0.name }
            .map { _, members in
                let bundle = members[0].appBundle
                return ProcessGroup(name: bundle?.deletingPathExtension().lastPathComponent ?? members[0].name,
                                    appBundle: bundle,
                                    cpu: members.reduce(0) { $0 + $1.cpu },
                                    memory: members.reduce(0) { $0 + $1.memory },
                                    pids: members.map(\.pid))
            }
    }
}

/// Background dev tools that quietly hold gigabytes of RAM.
public enum DevMemoryHogs {
    public struct Hog: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let tip: String
        public let memory: Int64
        public let pids: [Int32]
    }

    public static func find(in processes: [ProcessUsage]) -> [Hog] {
        var hogs: [Hog] = []
        let sims = processes.filter { $0.name == "launchd_sim" }
        if !sims.isEmpty {
            // Everything a simulator runs lives under its runtime root (…/CoreSimulator/…/RuntimeRoot/…).
            let simFamily = processes.filter { $0.path.contains("RuntimeRoot") || $0.path.contains("/CoreSimulator/") || $0.name == "Simulator" }
            hogs.append(Hog(id: "simulators", title: "\(sims.count) booted simulator(s)",
                            tip: "Shuts down every simulator (`xcrun simctl shutdown all`). Apps and data stay installed.",
                            memory: simFamily.reduce(0) { $0 + $1.memory }, pids: []))
        }
        let gradle = Self.javaDaemons(matching: ["GradleDaemon", "KotlinCompileDaemon"])
        if !gradle.isEmpty {
            let memory = processes.filter { gradle.contains($0.pid) }.reduce(0) { $0 + $1.memory }
            hogs.append(Hog(id: "gradle", title: "\(gradle.count) Gradle / Kotlin daemon(s)",
                            tip: "Idle build daemons. Stopping them is harmless — the next build starts a fresh one.",
                            memory: memory, pids: gradle))
        }
        return hogs
    }

    /// `ps -c` shows only "java", so match on the full command line.
    static func javaDaemons(matching markers: [String]) -> [Int32] {
        guard let out = Shell.run(["/bin/ps", "-Ao", "pid=,command="]) else { return [] }
        return out.split(separator: "\n").compactMap { line in
            let trimmed = line.drop { $0 == " " }
            guard markers.contains(where: { trimmed.contains($0) }),
                  let pid = Int32(trimmed.prefix { $0 != " " }) else { return nil }
            return pid
        }
    }

    public static func stop(_ hog: Hog) {
        switch hog.id {
        case "simulators": _ = Shell.run(["/usr/bin/xcrun", "simctl", "shutdown", "all"])
        default: hog.pids.forEach { kill($0, SIGTERM) }   // graceful: daemons exit cleanly on TERM
        }
    }
}

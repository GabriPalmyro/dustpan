import Foundation

/// Snapshot of the startup volume's capacity.
public struct DiskStatus: Equatable, Sendable {
    public let total: Int64
    /// Space available for "important" usage — what Finder reports, purgeable space included.
    public let available: Int64

    public init(total: Int64, available: Int64) {
        self.total = total
        self.available = available
    }

    public var used: Int64 { max(total - available, 0) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public static func current(volume: URL = URL(fileURLWithPath: "/")) -> DiskStatus? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? volume.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return DiskStatus(total: Int64(total), available: available)
    }
}

public enum DiskHealth: Sendable {
    case healthy, low, critical

    /// `threshold` is the free-space floor the user configured. Critical is half of it.
    public init(available: Int64, threshold: Int64) {
        if available < threshold / 2 { self = .critical }
        else if available < threshold { self = .low }
        else { self = .healthy }
    }
}

public extension Int64 {
    static func gigabytes(_ n: Int) -> Int64 { Int64(n) * 1_000_000_000 }
    static func megabytes(_ n: Int) -> Int64 { Int64(n) * 1_000_000 }

    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

import Foundation

public struct AutoCleanRule: Codable, Identifiable, Hashable, Sendable {
    public enum Schedule: String, Codable, CaseIterable, Sendable {
        case daily = "Daily"
        case weekly = "Weekly"
        case whenLow = "When space is low"
    }

    /// A junk item id (see `JunkCatalog`, plus `simulator-logs` / `simulators-unavailable`), or `installers`.
    public let id: String
    public var enabled: Bool
    public var schedule: Schedule
    /// Installers only: leave anything newer than this alone.
    public var olderThanDays: Int
    public var lastRun: Date?

    public init(id: String, enabled: Bool = false, schedule: Schedule = .weekly, olderThanDays: Int = 30, lastRun: Date? = nil) {
        self.id = id
        self.enabled = enabled
        self.schedule = schedule
        self.olderThanDays = olderThanDays
        self.lastRun = lastRun
    }

    public static let installersID = "installers"

    public var title: String {
        switch id {
        case Self.installersID: "Old installers → Trash"
        case "simulator-logs": "Simulator logs & test attachments"
        case "simulators-unavailable": "Unavailable simulators"
        default: JunkCatalog.target(id: id)?.title ?? id
        }
    }

    public func isDue(now: Date, spaceIsLow: Bool) -> Bool {
        guard enabled else { return false }
        switch schedule {
        case .whenLow: return spaceIsLow
        case .daily: return lastRun.map { now.timeIntervalSince($0) >= 86_400 } ?? true
        case .weekly: return lastRun.map { now.timeIntervalSince($0) >= 7 * 86_400 } ?? true
        }
    }

    /// Opt-in. Nothing is cleaned automatically until the user flips a switch.
    public static let defaults: [AutoCleanRule] = [
        AutoCleanRule(id: "xcode-derived-data"),
        AutoCleanRule(id: "simulator-logs"),
        AutoCleanRule(id: "simulators-unavailable"),
        AutoCleanRule(id: "coresim-logs"),
        AutoCleanRule(id: "gradle", schedule: .whenLow),
        AutoCleanRule(id: "js-caches", schedule: .whenLow),
        AutoCleanRule(id: "homebrew"),
        AutoCleanRule(id: "cocoapods", schedule: .whenLow),
        AutoCleanRule(id: "app-logs"),
        AutoCleanRule(id: installersID, olderThanDays: 30),
    ]

    /// Keeps saved settings, adds rules introduced in newer versions.
    public static func merged(saved: [AutoCleanRule]) -> [AutoCleanRule] {
        let known = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        return defaults.map { known[$0.id] ?? $0 }
    }
}

public enum AutoCleaner {
    public struct Outcome: Sendable {
        public let ruleID: String
        public let result: CleanResult
    }

    /// Runs a single rule right now, regardless of schedule.
    public static func run(_ rule: AutoCleanRule, now: Date = .now) -> Outcome {
        if rule.id == AutoCleanRule.installersID {
            let cutoff = now.addingTimeInterval(-Double(rule.olderThanDays) * 86_400)
            let old = InstallerScanner.scan()
                .filter { $0.kind != .macOSInstaller && ($0.file.modified ?? now) < cutoff }
                .map(\.file.url)
            return Outcome(ruleID: rule.id, result: Cleaner.trash(old))
        }
        guard let item = JunkScanner.item(id: rule.id), item.action != .manual else {
            return Outcome(ruleID: rule.id, result: CleanResult())
        }
        return Outcome(ruleID: rule.id, result: Cleaner.clean(item))
    }
}

extension JunkScanner {
    /// Measures a single item by id.
    public static func item(id: String) -> CleanupItem? {
        switch id {
        case "simulator-logs": return SimulatorScanner.logsItem()
        case "simulators-unavailable": return SimulatorScanner.unavailableItem()
        default:
            guard let target = JunkCatalog.target(id: id) else { return nil }
            let owned = Set(JunkCatalog.targets.filter { !$0.isCatchAll }.flatMap { $0.urls() }.map(\.standardizedFileURL))
            return measure(target, home: .home, owned: owned)
        }
    }
}

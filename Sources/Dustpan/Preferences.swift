import DustpanCore
import Foundation

/// UserDefaults keys. Views bind with `@AppStorage(Pref.x)`; non-view code reads through `Preferences`.
enum Pref {
    static let thresholdGB = "thresholdGB"
    static let checkIntervalMinutes = "checkIntervalMinutes"
    static let notificationsEnabled = "notificationsEnabled"
    static let menuBarStyle = "menuBarStyle"
    static let largeFileMB = "largeFileMB"
    static let staleProjectDays = "staleProjectDays"
    static let rules = "autoCleanRules"
    static let lastLowSpaceAlert = "lastLowSpaceAlert"
}

enum Preferences {
    static let defaults: [String: Any] = [
        Pref.thresholdGB: 20,
        Pref.checkIntervalMinutes: 30,
        Pref.notificationsEnabled: true,
        Pref.menuBarStyle: MenuBarStyle.system.rawValue,
        Pref.largeFileMB: 500,
        Pref.staleProjectDays: 14,
    ]

    static func register() { UserDefaults.standard.register(defaults: defaults) }

    private static var store: UserDefaults { .standard }

    static var threshold: Int64 { .gigabytes(store.integer(forKey: Pref.thresholdGB)) }
    static var checkInterval: TimeInterval { TimeInterval(max(store.integer(forKey: Pref.checkIntervalMinutes), 5) * 60) }
    static var notificationsEnabled: Bool { store.bool(forKey: Pref.notificationsEnabled) }
    static var largeFileThreshold: Int64 { .megabytes(store.integer(forKey: Pref.largeFileMB)) }
    static var staleProjectDays: Int { store.integer(forKey: Pref.staleProjectDays) }

    static var lastLowSpaceAlert: Date? {
        get { store.object(forKey: Pref.lastLowSpaceAlert) as? Date }
        set { store.set(newValue, forKey: Pref.lastLowSpaceAlert) }
    }

    static var rules: [AutoCleanRule] {
        get {
            let saved = store.data(forKey: Pref.rules).flatMap { try? JSONDecoder().decode([AutoCleanRule].self, from: $0) } ?? []
            return AutoCleanRule.merged(saved: saved)
        }
        set { store.set(try? JSONEncoder().encode(newValue), forKey: Pref.rules) }
    }
}

enum MenuBarStyle: String, CaseIterable {
    case icon, freeSpace, system

    var title: String {
        switch self {
        case .icon: "Icon only"
        case .freeSpace: "Free disk space"
        case .system: "CPU & memory"
        }
    }
}

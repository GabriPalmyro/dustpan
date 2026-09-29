import Foundation

public enum CleanupGroup: String, CaseIterable, Codable, Sendable {
    case system = "System"
    case developer = "Developer"
    case simulators = "Simulators"
    case manual = "Review manually"
}

public enum CleanupAction: Hashable, Sendable {
    /// Remove everything inside each path, keeping the folder itself.
    case deleteContents
    /// Run a tool that knows how to clean safely (e.g. `simctl delete unavailable`).
    case command([String])
    /// Dustpan only measures and explains; the user decides.
    case manual
}

/// A measured thing that can be cleaned (or reviewed), with guidance.
public struct CleanupItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let group: CleanupGroup
    /// What this is.
    public let summary: String
    /// What happens if you delete it / how to handle it.
    public let tip: String
    public let size: Int64
    public let paths: [URL]
    /// Direct children of `paths` that belong to other items and must be left alone.
    public let excluding: Set<URL>
    public let action: CleanupAction

    public var isCleanable: Bool { action != .manual }
}

/// Static description of a junk location. Paths starting with `/` are absolute; others are relative to home.
public struct JunkTarget: Sendable {
    public let id: String
    public let title: String
    public let group: CleanupGroup
    public let paths: [String]
    public let summary: String
    public let tip: String
    public let action: CleanupAction
    /// A broad folder (e.g. `~/Library/Caches`) whose sub-folders may be owned by more specific targets.
    public let isCatchAll: Bool

    public init(_ id: String, _ title: String, _ group: CleanupGroup, paths: [String],
                summary: String, tip: String, action: CleanupAction = .deleteContents, catchAll: Bool = false) {
        self.id = id
        self.title = title
        self.group = group
        self.paths = paths
        self.summary = summary
        self.tip = tip
        self.action = action
        self.isCatchAll = catchAll
    }

    public func urls(home: URL = .home) -> [URL] {
        paths.map { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : home.appendingPathComponent($0) }
    }
}

public enum JunkCatalog {
    public static let targets: [JunkTarget] = [
        // MARK: System
        JunkTarget("app-caches", "App caches", .system,
                   paths: ["Library/Caches"],
                   summary: "Caches apps keep to launch and load faster.",
                   tip: "Safe to clear — apps rebuild what they need. Quit heavy apps first; their next launch may be a bit slower.",
                   catchAll: true),
        JunkTarget("app-logs", "App logs", .system,
                   paths: ["Library/Logs"],
                   summary: "Diagnostic logs written by apps and background services.",
                   tip: "Safe. Only useful when you're debugging a specific app.",
                   catchAll: true),
        JunkTarget("trash", "Trash", .system,
                   paths: [".Trash"],
                   summary: "Files you already deleted. They keep using space until the Trash is emptied.",
                   tip: "Glance through it first — emptying is permanent."),

        // MARK: Developer
        JunkTarget("xcode-derived-data", "Xcode DerivedData", .developer,
                   paths: ["Library/Developer/Xcode/DerivedData"],
                   summary: "Build products, intermediates and indexes for every project Xcode ever opened.",
                   tip: "Safe. Each project does one full rebuild afterwards. Usually the biggest item on an iOS dev Mac."),
        JunkTarget("xcode-device-support", "Xcode device support", .developer,
                   paths: ["Library/Developer/Xcode/iOS DeviceSupport",
                           "Library/Developer/Xcode/watchOS DeviceSupport",
                           "Library/Developer/Xcode/tvOS DeviceSupport",
                           "Library/Developer/Xcode/visionOS DeviceSupport"],
                   summary: "Debug symbols copied from each device and OS version you've plugged in.",
                   tip: "Safe. Xcode copies them again the next time you connect that device (a few minutes)."),
        JunkTarget("coresim-caches", "Simulator caches", .developer,
                   paths: ["Library/Developer/CoreSimulator/Caches"],
                   summary: "dyld shared caches for simulator runtimes.",
                   tip: "Safe. Regenerated on the next simulator boot."),
        JunkTarget("coresim-logs", "CoreSimulator logs", .developer,
                   paths: ["Library/Logs/CoreSimulator"],
                   summary: "Host-side logs from the simulator service.",
                   tip: "Safe."),
        JunkTarget("gradle", "Gradle caches", .developer,
                   paths: [".gradle/caches", ".gradle/daemon"],
                   summary: "Downloaded Android dependencies, transformed jars and old daemon logs.",
                   tip: "Safe. The next Android build downloads what it needs again."),
        JunkTarget("android-cache", "Android build cache", .developer,
                   paths: [".android/build-cache", ".android/cache"],
                   summary: "Android Gradle Plugin build cache.",
                   tip: "Safe."),
        JunkTarget("cocoapods", "CocoaPods cache", .developer,
                   paths: ["Library/Caches/CocoaPods"],
                   summary: "Every pod version ever downloaded.",
                   tip: "Safe. `pod install` re-downloads what a project needs."),
        JunkTarget("pub-cache", "Dart / Flutter pub cache", .developer,
                   paths: [".pub-cache/.cache", ".pub-cache/hosted-hashes"],
                   summary: "Temporary files and hashes from `pub get`.",
                   tip: "Safe. Packages themselves live in ~/.pub-cache/hosted (see Review manually)."),
        JunkTarget("js-caches", "npm / Yarn / pnpm caches", .developer,
                   paths: [".npm/_cacache", "Library/Caches/Yarn", "Library/pnpm/store"],
                   summary: "Package tarballs cached by JavaScript package managers.",
                   tip: "Safe. Installs get slower once, until the cache warms up again."),
        JunkTarget("homebrew", "Homebrew cache", .developer,
                   paths: ["Library/Caches/Homebrew"],
                   summary: "Downloaded bottles and source archives.",
                   tip: "Safe. Same as `brew cleanup -s`."),
        JunkTarget("swiftpm", "Swift Package Manager cache", .developer,
                   paths: ["Library/Caches/org.swift.swiftpm"],
                   summary: "Cloned package repositories shared across projects.",
                   tip: "Safe. Packages are fetched again on next resolve."),
        JunkTarget("pip", "pip cache", .developer,
                   paths: ["Library/Caches/pip"],
                   summary: "Downloaded Python wheels.",
                   tip: "Safe."),

        // MARK: Review manually
        JunkTarget("xcode-archives", "Xcode archives", .manual,
                   paths: ["Library/Developer/Xcode/Archives"],
                   summary: "Every .xcarchive you've built for distribution, dSYMs included.",
                   tip: "Keep archives of versions still live in the stores — you need their dSYMs to symbolicate crashes. Delete older ones in Xcode › Window › Organizer.",
                   action: .manual),
        JunkTarget("simulator-devices", "iOS simulators", .manual,
                   paths: ["Library/Developer/CoreSimulator/Devices"],
                   summary: "Every simulator plus the apps and data installed on it.",
                   tip: "Clean simulator logs first (Simulators section) — that's usually where the space went. Then delete simulators you don't use in Xcode › Window › Devices and Simulators.",
                   action: .manual),
        JunkTarget("fvm", "Flutter SDKs (FVM)", .manual,
                   paths: ["fvm/versions"],
                   summary: "Flutter SDK versions installed with FVM, ~1–2 GB each.",
                   tip: "Run `fvm list`, then `fvm remove <version>` for anything no project pins in its .fvmrc.",
                   action: .manual),
        JunkTarget("pub-hosted", "Dart packages", .manual,
                   paths: [".pub-cache/hosted"],
                   summary: "Every Dart/Flutter package version ever downloaded.",
                   tip: "`flutter pub cache clean` wipes it; each project re-downloads on its next `pub get`.",
                   action: .manual),
        JunkTarget("android-avd", "Android emulators", .manual,
                   paths: [".android/avd"],
                   summary: "Android Virtual Device disk images.",
                   tip: "Delete emulators you don't use in Android Studio › Device Manager.",
                   action: .manual),
        JunkTarget("ios-backups", "iPhone / iPad backups", .manual,
                   paths: ["Library/Application Support/MobileSync/Backup"],
                   summary: "Local device backups made through Finder.",
                   tip: "Manage them in Finder › your device › Manage Backups. Measuring needs Full Disk Access.",
                   action: .manual),
        JunkTarget("docker", "Docker", .manual,
                   paths: [],
                   summary: "Images, containers, volumes and build cache inside Docker's VM disk.",
                   tip: "Run `docker system df` to see usage, `docker system prune -a` to reclaim it.",
                   action: .manual),
        JunkTarget("sim-runtimes", "Simulator runtimes", .manual,
                   paths: [],
                   summary: "Downloaded iOS/watchOS/visionOS simulator runtimes, 5–10 GB each.",
                   tip: "Remove old versions in Xcode › Settings › Components, or `xcrun simctl runtime list` / `delete`.",
                   action: .manual),
    ]

    public static func target(id: String) -> JunkTarget? {
        targets.first { $0.id == id }
    }
}

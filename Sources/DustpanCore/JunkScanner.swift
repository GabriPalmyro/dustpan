import Foundation

public enum JunkScanner {
    /// Items below this size aren't worth showing as cleanable.
    public static let minimumCleanableSize: Int64 = .megabytes(10)

    /// Measures every catalog target plus simulator junk. Manual items are returned even when empty.
    public static func scan(home: URL = .home, targets: [JunkTarget] = JunkCatalog.targets) async -> [CleanupItem] {
        let owned = Set(targets.filter { !$0.isCatchAll }.flatMap { $0.urls(home: home) }.map(\.standardizedFileURL))

        let items = await withTaskGroup(of: CleanupItem?.self) { group in
            for target in targets {
                group.addTask { measure(target, home: home, owned: owned) }
            }
            group.addTask { SimulatorScanner.logsItem() }
            group.addTask { SimulatorScanner.unavailableItem() }
            var result: [CleanupItem] = []
            for await item in group { if let item { result.append(item) } }
            return result
        }

        return items
            .filter { $0.action != .deleteContents || $0.size >= minimumCleanableSize }
            .sorted { $0.size > $1.size }
    }

    static func measure(_ target: JunkTarget, home: URL, owned: Set<URL>) -> CleanupItem? {
        let urls = target.urls(home: home).filter(FileWalker.exists)
        if urls.isEmpty && target.action != .manual { return nil }

        var size: Int64 = 0
        var excluding: Set<URL> = []
        for url in urls {
            if target.isCatchAll {
                for child in FileWalker.children(of: url) {
                    if owned.contains(child.standardizedFileURL) { excluding.insert(child.standardizedFileURL); continue }
                    size += FileWalker.allocatedSize(of: child)
                }
            } else {
                size += FileWalker.allocatedSize(of: url)
            }
        }

        return CleanupItem(id: target.id, title: target.title, group: target.group,
                           summary: target.summary, tip: target.tip, size: size,
                           paths: urls, excluding: excluding, action: target.action)
    }
}

public enum SimulatorScanner {
    struct Device: Decodable {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool?
        let dataPath: String?
    }

    struct DeviceList: Decodable {
        let devices: [String: [Device]]
    }

    static func devices() -> [Device] {
        // Don't invoke xcrun on Macs without simulators — it can pop the "install tools" dialog.
        guard FileWalker.exists(URL.home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")),
              let out = Shell.run(["/usr/bin/xcrun", "simctl", "list", "devices", "-j"]),
              let list = try? JSONDecoder().decode(DeviceList.self, from: Data(out.utf8))
        else { return [] }
        return list.devices.values.flatMap { $0 }
    }

    /// Log folders inside simulators that are shut down. Never touches installed apps or their data.
    ///
    /// The big one is `testmanagerd`'s Attachments: screenshots and videos XCUITest records on
    /// every run, which Xcode never cleans up. One simulator can hoard 5–10 GB of them.
    static func logDirectories(for devices: [Device]? = nil) -> [URL] {
        let devices = devices ?? Self.devices()
        var result: [URL] = []
        for device in devices where device.state == "Shutdown" {
            guard let dataPath = device.dataPath else { continue }
            let data = URL(fileURLWithPath: dataPath)
            result.append(data.appendingPathComponent("var/db/diagnostics"))
            result.append(data.appendingPathComponent("var/db/uuidtext"))
            let daemons = data.appendingPathComponent("Containers/Data/InternalDaemon")
            for daemon in FileWalker.children(of: daemons) {
                result.append(daemon.appendingPathComponent("Attachments"))
            }
        }
        return result.filter(FileWalker.exists)
    }

    static func logsItem() -> CleanupItem? {
        let dirs = logDirectories()
        let size = dirs.reduce(Int64(0)) { $0 + FileWalker.allocatedSize(of: $1) }
        guard size > 0 else { return nil }
        return CleanupItem(
            id: "simulator-logs", title: "Simulator logs & test attachments", group: .simulators,
            summary: "os_log archives and XCUITest screenshots/videos inside shut-down simulators.",
            tip: "Safe — apps and their data stay installed. Booted simulators are skipped; shut them down to include them.",
            size: size, paths: dirs, excluding: [], action: .deleteContents)
    }

    static func unavailableItem() -> CleanupItem? {
        let unavailable = devices().filter { $0.isAvailable == false }
        guard !unavailable.isEmpty else { return nil }
        let dirs = unavailable.compactMap { $0.dataPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() } }
        let size = dirs.reduce(Int64(0)) { $0 + FileWalker.allocatedSize(of: $1) }
        return CleanupItem(
            id: "simulators-unavailable", title: "Unavailable simulators (\(unavailable.count))", group: .simulators,
            summary: "Simulators whose runtime was removed. They can't boot anymore.",
            tip: "Safe. Removed with `xcrun simctl delete unavailable`.",
            size: size, paths: dirs, excluding: [],
            action: .command(["/usr/bin/xcrun", "simctl", "delete", "unavailable"]))
    }
}

enum Shell {
    /// Runs a command and returns stdout, or nil if it failed to launch or exited non-zero.
    static func run(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

import AppKit
import DustpanCore
import Observation

@Observable
@MainActor
final class SystemMonitor {
    static let shared = SystemMonitor()
    static let historyLength = 60

    private(set) var snapshot: SystemSnapshot?
    /// Last `historyLength` samples, oldest first — for sparklines.
    private(set) var history: [SystemSnapshot] = []
    private(set) var groups: [ProcessGroup] = []
    private(set) var hogs: [DevMemoryHogs.Hog] = []

    private let sampler = SystemSampler()
    private var timer: Task<Void, Never>?
    /// Views that need the process list (popover, Activity section). Processes are only listed while > 0.
    private var processWatchers = 0

    func start() {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func tick() async {
        let sampler = sampler
        let wantProcesses = processWatchers > 0
        let (snap, procs, hogs) = await Task.detached(priority: .utility) {
            let snap = sampler.sample()
            guard wantProcesses else { return (snap, [ProcessUsage](), [DevMemoryHogs.Hog]()) }
            let procs = ProcessList.all()
            return (snap, procs, DevMemoryHogs.find(in: procs))
        }.value

        snapshot = snap
        history.append(snap)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
        if wantProcesses {
            groups = ProcessList.grouped(procs)
            self.hogs = hogs
        }
    }

    /// Call from `.task` in views that show processes; stops listing them when the view goes away.
    func watchProcesses() async {
        processWatchers += 1
        await tick()
        await withTaskCancellationHandler {
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
        } onCancel: {
            Task { @MainActor in self.processWatchers -= 1 }
        }
    }

    func topByMemory(_ n: Int) -> [ProcessGroup] { Array(groups.sorted { $0.memory > $1.memory }.prefix(n)) }
    func topByCPU(_ n: Int) -> [ProcessGroup] { Array(groups.sorted { $0.cpu > $1.cpu }.prefix(n)) }

    /// The running app behind a group, if it's one you can quit like ⌘Q. Never Finder or Dustpan itself.
    func quittableApp(_ group: ProcessGroup) -> NSRunningApplication? {
        guard let bundle = group.appBundle else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.standardizedFileURL == bundle.standardizedFileURL
                && $0.activationPolicy == .regular
                && $0.bundleIdentifier != "com.apple.finder"
                && $0 != .current
        }
    }

    func quit(_ group: ProcessGroup) {
        quittableApp(group)?.terminate()   // polite: the app can still ask to save documents
    }

    func stop(_ hog: DevMemoryHogs.Hog) async {
        await Task.detached { DevMemoryHogs.stop(hog) }.value
        await tick()
    }
}

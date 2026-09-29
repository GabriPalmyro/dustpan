import DustpanCore
import Observation
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview, activity, junk, installers, duplicates, projects, diskScan, rules

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .activity: "Activity"
        case .junk: "Junk"
        case .installers: "Installers"
        case .duplicates: "Duplicates"
        case .projects: "Project Artifacts"
        case .diskScan: "Disk Scan"
        case .rules: "Auto Clean"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "internaldrive"
        case .activity: "waveform.path.ecg"
        case .junk: "trash"
        case .installers: "shippingbox"
        case .duplicates: "doc.on.doc"
        case .projects: "hammer"
        case .diskScan: "chart.pie"
        case .rules: "clock.arrow.circlepath"
        }
    }
}

/// Something worth doing, surfaced on the Overview and in notifications.
struct Recommendation: Identifiable {
    let id: String
    let destination: SidebarItem
    let title: String
    let detail: String
    let size: Int64
}

@Observable
@MainActor
final class AppState {
    static let shared = AppState()

    var selection: SidebarItem? = .overview
    var disk: DiskStatus? = DiskStatus.current()
    var hasFullDiskAccess = Permissions.hasFullDiskAccess

    var junk: [CleanupItem] = []
    var installers: [InstallerFile] = []
    var duplicates: [DuplicateGroup] = []
    var artifacts: [ProjectArtifact] = []
    var scanning: Set<SidebarItem> = []
    var scanned: Set<SidebarItem> = []
    var duplicateFilesSeen = 0

    var rules: [AutoCleanRule] = Preferences.rules {
        didSet { Preferences.rules = rules }
    }

    /// Last thing a clean did, shown briefly in the UI.
    var lastResult: String?

    /// Captured from a SwiftUI view so non-view code (notifications, menu) can open the main window.
    var openMainWindow: (() -> Void)?
    var openOnboarding: (() -> Void)?

    private var monitor: Task<Void, Never>?

    var health: DiskHealth {
        guard let disk else { return .healthy }
        return DiskHealth(available: disk.available, threshold: Preferences.threshold)
    }

    // MARK: Monitoring

    func startMonitoring() {
        guard monitor == nil else { return }
        Notifier.shared.onOpen = { [weak self] in self?.openMainWindow?() }
        Notifier.shared.activate()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(Preferences.checkInterval))
            }
        }
    }

    /// One monitoring pass: refresh capacity, run due rules, alert if space is low.
    func tick() async {
        refreshDisk()
        let low = health != .healthy
        await runDueRules(spaceIsLow: low)
        if low { await alertLowSpaceIfNeeded() }
    }

    func refreshDisk() {
        disk = DiskStatus.current()
    }

    private func alertLowSpaceIfNeeded() async {
        guard Preferences.notificationsEnabled, let disk else { return }
        // Once every 6 hours at most — every 3 hours when critical.
        let cooldown: TimeInterval = health == .critical ? 3 * 3600 : 6 * 3600
        if let last = Preferences.lastLowSpaceAlert, Date.now.timeIntervalSince(last) < cooldown { return }

        await scanJunk()
        let top = junk.filter(\.isCleanable).prefix(3)
        let reclaimable = junk.filter(\.isCleanable).reduce(0) { $0 + $1.size }
        let tips = top.map { "\($0.title) \($0.size.formattedBytes)" }.joined(separator: " · ")

        Notifier.shared.post(
            id: "low-space",
            title: health == .critical ? "Disk almost full" : "Running low on space",
            body: "\(disk.available.formattedBytes) free. \(reclaimable.formattedBytes) can be cleaned safely — \(tips)."
        )
        Preferences.lastLowSpaceAlert = .now
    }

    // MARK: Scanning

    func scanAll() async {
        async let a: Void = scanJunk()
        async let b: Void = scanInstallers()
        async let c: Void = scanProjects()
        _ = await (a, b, c)
    }

    func scanJunk() async {
        await run(.junk) { self.junk = await JunkScanner.scan() }
    }

    func scanInstallers() async {
        await run(.installers) {
            self.installers = await Task.detached(priority: .utility) { InstallerScanner.scan() }.value
        }
    }

    func scanProjects() async {
        await run(.projects) {
            self.artifacts = await Task.detached(priority: .utility) { ProjectArtifactScanner.scan() }.value
        }
    }

    func scanDuplicates() async {
        duplicateFilesSeen = 0
        await run(.duplicates) {
            self.duplicates = await Task.detached(priority: .utility) {
                DuplicateScanner.scan { count in Task { @MainActor in self.duplicateFilesSeen = count } }
            }.value
        }
    }

    private func run(_ section: SidebarItem, _ work: () async -> Void) async {
        guard !scanning.contains(section) else { return }
        scanning.insert(section)
        await work()
        scanning.remove(section)
        scanned.insert(section)
    }

    // MARK: Cleaning

    func clean(_ items: [CleanupItem]) async {
        let result = await Task.detached(priority: .userInitiated) {
            items.reduce(CleanResult()) { $0 + Cleaner.clean($1) }
        }.value
        finish(result)
        await scanJunk()
    }

    func trash(_ urls: [URL]) async {
        let result = await Task.detached(priority: .userInitiated) { Cleaner.trash(urls) }.value
        finish(result, trashed: true)
        let removed = Set(urls)
        installers.removeAll { removed.contains($0.file.url) }
        duplicates = duplicates.compactMap { group in
            let files = group.files.filter { !removed.contains($0.url) }
            return files.count > 1 ? DuplicateGroup(id: group.id, size: group.size, files: files) : nil
        }
    }

    func delete(_ urls: [URL]) async {
        let result = await Task.detached(priority: .userInitiated) { Cleaner.delete(urls) }.value
        finish(result)
        let removed = Set(urls)
        artifacts.removeAll { removed.contains($0.url) }
    }

    private func finish(_ result: CleanResult, trashed: Bool = false) {
        refreshDisk()
        var message = trashed
            ? "Moved \(result.removed) item(s), \(result.freed.formattedBytes), to the Trash. Empty it to free the space."
            : "Freed \(result.freed.formattedBytes)."
        if !result.failures.isEmpty { message += " \(result.failures.count) item(s) couldn't be removed." }
        lastResult = message
    }

    // MARK: Auto clean

    func runDueRules(spaceIsLow: Bool) async {
        let due = rules.filter { $0.isDue(now: .now, spaceIsLow: spaceIsLow) }
        guard !due.isEmpty else { return }
        let outcomes = await Task.detached(priority: .utility) { due.map { AutoCleaner.run($0) } }.value
        markRun(due.map(\.id))

        let freed = outcomes.reduce(0) { $0 + $1.result.freed }
        refreshDisk()
        if freed > 0, Preferences.notificationsEnabled {
            Notifier.shared.post(id: "auto-clean", title: "Auto Clean freed \(freed.formattedBytes)",
                                 body: due.map(\.title).joined(separator: ", "))
        }
    }

    func runNow(_ rule: AutoCleanRule) async {
        let outcome = await Task.detached(priority: .userInitiated) { AutoCleaner.run(rule) }.value
        markRun([rule.id])
        finish(outcome.result, trashed: rule.id == AutoCleanRule.installersID)
    }

    private func markRun(_ ids: [String]) {
        for i in rules.indices where ids.contains(rules[i].id) { rules[i].lastRun = .now }
    }

    // MARK: Recommendations

    var recommendations: [Recommendation] {
        var result: [Recommendation] = junk.filter(\.isCleanable).prefix(4).map {
            Recommendation(id: $0.id, destination: .junk, title: $0.title, detail: $0.tip, size: $0.size)
        }
        let installerTotal = installers.reduce(0) { $0 + $1.file.size }
        if installerTotal > .megabytes(100) {
            result.append(Recommendation(id: "installers", destination: .installers,
                                         title: "\(installers.count) installers and builds",
                                         detail: "Disk images, packages and app builds you've probably already used.",
                                         size: installerTotal))
        }
        let stale = artifacts.filter { ($0.idleDays() ?? 0) >= Preferences.staleProjectDays }
        let staleTotal = stale.reduce(0) { $0 + $1.size }
        if staleTotal > .megabytes(500) {
            result.append(Recommendation(id: "projects", destination: .projects,
                                         title: "Build folders in \(Set(stale.map(\.project)).count) idle projects",
                                         detail: "node_modules, build, Pods… untouched for \(Preferences.staleProjectDays)+ days. Regenerated on next build.",
                                         size: staleTotal))
        }
        let wasted = duplicates.reduce(0) { $0 + $1.wasted }
        if wasted > .megabytes(100) {
            result.append(Recommendation(id: "duplicates", destination: .duplicates,
                                         title: "\(duplicates.count) sets of duplicate files",
                                         detail: "Identical copies in your personal folders.", size: wasted))
        }
        return result.sorted { $0.size > $1.size }
    }
}

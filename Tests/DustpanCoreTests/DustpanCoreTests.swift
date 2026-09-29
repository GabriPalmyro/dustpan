@testable import DustpanCore
import XCTest

final class DustpanCoreTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("dustpan-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func write(_ path: String, bytes: Int, seed: UInt8 = 0) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0) &+ seed }).write(to: url)
        return url
    }

    // MARK: Duplicates

    func testFindsIdenticalFilesAndKeepsOldestFirst() throws {
        let a = try write("a/photo.jpg", bytes: 200_000)
        try write("b/photo copy.jpg", bytes: 200_000)
        try write("c/different.jpg", bytes: 200_000, seed: 7)     // same size, different content
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: a.path)

        let groups = DuplicateScanner.scan(roots: [root], minimumSize: 1)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 2)
        XCTAssertEqual(groups[0].files.first?.url.lastPathComponent, "photo.jpg")
        XCTAssertEqual(groups[0].wasted, 200_000)
    }

    func testFilesDifferingOnlyAfterHeadAreNotDuplicates() throws {
        let a = try write("a.bin", bytes: 300_000)
        var data = try Data(contentsOf: a)
        data[250_000] ^= 0xFF
        try data.write(to: root.appendingPathComponent("b.bin"))

        XCTAssertTrue(DuplicateScanner.scan(roots: [root], minimumSize: 1).isEmpty)
    }

    func testHardLinksAreNotDuplicates() throws {
        let a = try write("a.bin", bytes: 100_000)
        try FileManager.default.linkItem(at: a, to: root.appendingPathComponent("b.bin"))
        XCTAssertTrue(DuplicateScanner.scan(roots: [root], minimumSize: 1).isEmpty)
    }

    // MARK: Junk

    func testCatchAllExcludesFoldersOwnedByOtherTargets() throws {
        try write("Library/Caches/SomeApp/blob", bytes: 50_000)
        try write("Library/Caches/Homebrew/bottle.tar.gz", bytes: 80_000)

        let caches = JunkTarget("caches", "Caches", .system, paths: ["Library/Caches"], summary: "", tip: "", catchAll: true)
        let brew = JunkTarget("brew", "Brew", .developer, paths: ["Library/Caches/Homebrew"], summary: "", tip: "")
        let owned = Set(brew.urls(home: root).map(\.standardizedFileURL))

        let item = try XCTUnwrap(JunkScanner.measure(caches, home: root, owned: owned))
        XCTAssertEqual(item.excluding.map(\.lastPathComponent), ["Homebrew"])
        XCTAssertLessThan(item.size, 80_000)

        _ = Cleaner.clean(item)
        XCTAssertFalse(FileWalker.exists(root.appendingPathComponent("Library/Caches/SomeApp")))
        XCTAssertTrue(FileWalker.exists(root.appendingPathComponent("Library/Caches/Homebrew/bottle.tar.gz")))
        XCTAssertTrue(FileWalker.exists(root.appendingPathComponent("Library/Caches")), "folder itself is kept")
    }

    func testMissingTargetIsSkippedButManualIsKept() {
        let missing = JunkTarget("x", "X", .developer, paths: ["nope"], summary: "", tip: "")
        let manual = JunkTarget("y", "Y", .manual, paths: [], summary: "", tip: "", action: .manual)
        XCTAssertNil(JunkScanner.measure(missing, home: root, owned: []))
        XCTAssertNotNil(JunkScanner.measure(manual, home: root, owned: []))
    }

    func testCatalogIdsAreUnique() {
        let ids = JunkCatalog.targets.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    // MARK: Cleaner safety

    func testCleanerRefusesProtectedLocations() {
        let result = Cleaner.delete([URL.home.appendingPathComponent("Documents")])
        XCTAssertEqual(result.removed, 0)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(FileWalker.exists(URL.home.appendingPathComponent("Documents")))
    }

    func testManualItemsAreNeverCleaned() throws {
        let file = try write("keep/me.txt", bytes: 10)
        let item = CleanupItem(id: "m", title: "", group: .manual, summary: "", tip: "", size: 10,
                               paths: [file.deletingLastPathComponent()], excluding: [], action: .manual)
        XCTAssertEqual(Cleaner.clean(item).removed, 0)
        XCTAssertTrue(FileWalker.exists(file))
    }

    // MARK: Project artifacts

    func testArtifactsNeedAProjectMarker() throws {
        try write("app/package.json", bytes: 2)
        try write("app/node_modules/lib/index.js", bytes: 10_000)
        try write("random/build/output.bin", bytes: 10_000)     // no marker → not a project build folder

        let found = ProjectArtifactScanner.scan(roots: [root], minimumSize: 1)
        XCTAssertEqual(found.map(\.kind), ["node_modules"])
        XCTAssertEqual(found.first?.regenerateHint, "npm / yarn / pnpm install")
    }

    func testDetectsGitWorktree() throws {
        try write("wt/pubspec.yaml", bytes: 2)
        try write("wt/.dart_tool/cache", bytes: 10_000)
        try "gitdir: /tmp/repo/.git/worktrees/wt".write(to: root.appendingPathComponent("wt/.git"), atomically: true, encoding: .utf8)

        let found = ProjectArtifactScanner.scan(roots: [root], minimumSize: 1)
        XCTAssertEqual(found.first?.isGitWorktree, true)
        XCTAssertEqual(ProjectArtifactScanner.gitDirectory(root.appendingPathComponent("wt")).path, "/tmp/repo/.git/worktrees/wt")
    }

    // MARK: Installers

    func testFindsInstallers() throws {
        try write("Downloads/Tool.dmg", bytes: 1_000)
        try write("Downloads/app-release.apk", bytes: 1_000)
        try write("Downloads/notes.txt", bytes: 1_000)

        let kinds = Set(InstallerScanner.scan(roots: [root]).filter { $0.file.url.isInside(root) }.map(\.kind))
        XCTAssertEqual(kinds, [.diskImage, .appBuild])
    }

    // MARK: Rules

    func testRuleScheduling() {
        let now = Date()
        var rule = AutoCleanRule(id: "x", enabled: true, schedule: .daily)
        XCTAssertTrue(rule.isDue(now: now, spaceIsLow: false), "never run → due")
        rule.lastRun = now.addingTimeInterval(-3600)
        XCTAssertFalse(rule.isDue(now: now, spaceIsLow: false))
        rule.lastRun = now.addingTimeInterval(-90_000)
        XCTAssertTrue(rule.isDue(now: now, spaceIsLow: false))

        rule.schedule = .whenLow
        XCTAssertFalse(rule.isDue(now: now, spaceIsLow: false))
        XCTAssertTrue(rule.isDue(now: now, spaceIsLow: true))

        rule.enabled = false
        XCTAssertFalse(rule.isDue(now: now, spaceIsLow: true))
    }

    func testRulesAreOffByDefaultAndMergeKeepsUserChoices() {
        XCTAssertTrue(AutoCleanRule.defaults.allSatisfy { !$0.enabled })
        let saved = [AutoCleanRule(id: "homebrew", enabled: true, schedule: .daily)]
        let merged = AutoCleanRule.merged(saved: saved)
        XCTAssertEqual(merged.count, AutoCleanRule.defaults.count)
        XCTAssertEqual(merged.first { $0.id == "homebrew" }?.enabled, true)
    }

    func testRuleIdsExistInCatalog() {
        let known = Set(JunkCatalog.targets.map(\.id) + ["simulator-logs", "simulators-unavailable", AutoCleanRule.installersID])
        for rule in AutoCleanRule.defaults { XCTAssertTrue(known.contains(rule.id), rule.id) }
    }

    // MARK: Disk

    func testHealthLevels() {
        let t: Int64 = .gigabytes(20)
        XCTAssertEqual(DiskHealth(available: .gigabytes(50), threshold: t), .healthy)
        XCTAssertEqual(DiskHealth(available: .gigabytes(15), threshold: t), .low)
        XCTAssertEqual(DiskHealth(available: .gigabytes(5), threshold: t), .critical)
        XCTAssertNotNil(DiskStatus.current())
    }

    // MARK: System

    func testHelpersRollUpIntoTheirApp() {
        let procs = [
            ProcessUsage(pid: 1, path: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", cpu: 10, memory: 100),
            ProcessUsage(pid: 2, path: "/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)", cpu: 5, memory: 300),
            ProcessUsage(pid: 3, path: "/usr/sbin/cfprefsd", cpu: 1, memory: 10),
        ]
        let groups = ProcessList.grouped(procs).sorted { $0.memory > $1.memory }
        XCTAssertEqual(groups.map(\.name), ["Google Chrome", "cfprefsd"])
        XCTAssertEqual(groups[0].memory, 400)
        XCTAssertEqual(groups[0].pids.sorted(), [1, 2])
    }

    func testSamplerReturnsSaneValues() {
        let sampler = SystemSampler()
        _ = sampler.sample()
        let s = sampler.sample()
        XCTAssert((0...1).contains(s.cpu))
        XCTAssertGreaterThan(s.memoryUsed, 0)
        XCTAssertLessThanOrEqual(s.memoryUsed, s.memoryTotal)
        XCTAssertFalse(ProcessList.all().isEmpty)
    }
}

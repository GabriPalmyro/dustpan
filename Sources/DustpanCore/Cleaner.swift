import Foundation

public struct CleanResult: Sendable {
    public var freed: Int64 = 0
    public var removed: Int = 0
    public var failures: [String] = []

    public init() {}

    public static func + (a: CleanResult, b: CleanResult) -> CleanResult {
        var r = a
        r.freed += b.freed
        r.removed += b.removed
        r.failures += b.failures
        return r
    }
}

public enum CleanerError: LocalizedError {
    case protected(URL)

    public var errorDescription: String? {
        switch self {
        case .protected(let url): "Refusing to touch protected location \(url.abbreviatedPath)"
        }
    }
}

public enum Cleaner {
    /// Folders Dustpan must never delete or empty wholesale, no matter what an item says.
    static var protectedLocations: Set<String> {
        let home = URL.home
        let top = ["", "Library", "Documents", "Desktop", "Downloads", "Movies", "Music", "Pictures",
                   "Developer", "Library/Application Support", "Library/Containers", "Library/Mobile Documents"]
        return Set(top.map { home.appendingPathComponent($0).standardizedFileURL.path } + ["/", "/Applications", "/System", "/Users", "/Library"])
    }

    static func guardSafe(_ url: URL) throws {
        if protectedLocations.contains(url.standardizedFileURL.path) { throw CleanerError.protected(url) }
    }

    /// Cleans a junk item according to its action. Manual items are never touched.
    public static func clean(_ item: CleanupItem) -> CleanResult {
        switch item.action {
        case .manual:
            return CleanResult()
        case .command(let args):
            var result = CleanResult()
            if Shell.run(args) != nil { result.freed = item.size; result.removed = 1 }
            else { result.failures.append("\(args.joined(separator: " ")) failed") }
            return result
        case .deleteContents:
            var result = CleanResult()
            for path in item.paths {
                for child in FileWalker.children(of: path) where !item.excluding.contains(child.standardizedFileURL) {
                    do {
                        try guardSafe(child)
                        try FileManager.default.removeItem(at: child)
                        result.removed += 1
                    } catch {
                        result.failures.append("\(child.abbreviatedPath): \(error.localizedDescription)")
                    }
                }
            }
            // Measuring every child twice would double the cost; estimate from what was left behind.
            let leftover = item.paths.reduce(Int64(0)) { total, path in
                total + FileWalker.children(of: path)
                    .filter { !item.excluding.contains($0.standardizedFileURL) }
                    .reduce(0) { $0 + FileWalker.allocatedSize(of: $1) }
            }
            result.freed = max(item.size - leftover, 0)
            return result
        }
    }

    /// Moves files to the Trash — recoverable, but space is only freed once the Trash is emptied.
    public static func trash(_ urls: [URL]) -> CleanResult {
        var result = CleanResult()
        for url in urls {
            do {
                try guardSafe(url)
                let size = FileWalker.allocatedSize(of: url)
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                result.freed += size
                result.removed += 1
            } catch {
                result.failures.append("\(url.abbreviatedPath): \(error.localizedDescription)")
            }
        }
        return result
    }

    /// Permanently deletes regenerable folders (node_modules, build…). Skips the Trash on purpose:
    /// trashing a 2 GB node_modules frees nothing until the Trash is emptied.
    public static func delete(_ urls: [URL]) -> CleanResult {
        var result = CleanResult()
        for url in urls {
            do {
                try guardSafe(url)
                let size = FileWalker.allocatedSize(of: url)
                try FileManager.default.removeItem(at: url)
                result.freed += size
                result.removed += 1
            } catch {
                result.failures.append("\(url.abbreviatedPath): \(error.localizedDescription)")
            }
        }
        return result
    }
}

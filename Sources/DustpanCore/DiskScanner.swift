import Foundation

public struct DiskNode: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let size: Int64
    public let isDirectory: Bool

    public var name: String { url.lastPathComponent }
}

public struct DiskScan: Sendable {
    public let root: URL
    public let children: [DiskNode]   // largest first
    public let largeFiles: [FileEntry] // largest first

    public var total: Int64 { children.reduce(0) { $0 + $1.size } }
}

/// "Where did my disk go?" — sizes every child of a folder in parallel and collects large files on the way.
public enum DiskScanner {
    public static func scan(_ root: URL, largeFileThreshold: Int64 = .megabytes(500)) async -> DiskScan {
        let children = FileWalker.children(of: root)
        let results = await withTaskGroup(of: (DiskNode, [FileEntry]).self) { group in
            for child in children {
                group.addTask {
                    let summary = FileWalker.summarize(child, collectingFilesLargerThan: largeFileThreshold)
                    return (DiskNode(url: child, size: summary.size, isDirectory: FileWalker.isDirectory(child)), summary.largeFiles)
                }
            }
            var all: [(DiskNode, [FileEntry])] = []
            for await r in group { all.append(r) }
            return all
        }
        return DiskScan(
            root: root,
            children: results.map(\.0).filter { $0.size > 0 }.sorted { $0.size > $1.size },
            largeFiles: results.flatMap(\.1).sorted { $0.size > $1.size }
        )
    }
}

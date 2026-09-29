import Foundation

/// A single file found on disk.
public struct FileEntry: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let size: Int64
    public let modified: Date?

    public init(url: URL, size: Int64, modified: Date?) {
        self.url = url
        self.size = size
        self.modified = modified
    }

    public var name: String { url.lastPathComponent }
}

/// Filesystem traversal helpers. Everything here is synchronous — call from a background task.
public enum FileWalker {
    static let sizeKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey,
    ]

    /// Bytes actually allocated on disk by `url` (recursively). Symlinks are not followed.
    public static func allocatedSize(of url: URL) -> Int64 {
        summarize(url, collectingFilesLargerThan: nil).size
    }

    /// Walks `url` once, returning its total size and (optionally) every file above `threshold`.
    public static func summarize(_ url: URL, collectingFilesLargerThan threshold: Int64?) -> (size: Int64, largeFiles: [FileEntry]) {
        guard let values = try? url.resourceValues(forKeys: Set(sizeKeys)) else { return (0, []) }
        if values.isSymbolicLink == true { return (0, []) }
        if values.isDirectory != true {
            let size = fileSize(values)
            let large = threshold.map { size >= $0 } == true
            return (size, large ? [FileEntry(url: url, size: size, modified: values.contentModificationDate)] : [])
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: sizeKeys, options: [], errorHandler: { _, _ in true }
        ) else { return (0, []) }

        var total: Int64 = 0
        var large: [FileEntry] = []
        for case let child as URL in enumerator {
            if Task.isCancelled { break }
            guard let v = try? child.resourceValues(forKeys: Set(sizeKeys)), v.isRegularFile == true else { continue }
            let size = fileSize(v)
            total += size
            if let threshold, size >= threshold {
                large.append(FileEntry(url: child, size: size, modified: v.contentModificationDate))
            }
        }
        return (total, large)
    }

    /// Immediate children of a directory, hidden ones included.
    public static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    public static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    public static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func fileSize(_ v: URLResourceValues) -> Int64 {
        Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
    }
}

public extension URL {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// `~/...` style path for display.
    var abbreviatedPath: String { (path as NSString).abbreviatingWithTildeInPath }

    func isInside(_ other: URL) -> Bool {
        let a = standardizedFileURL.path, b = other.standardizedFileURL.path
        return a == b || a.hasPrefix(b.hasSuffix("/") ? b : b + "/")
    }
}

import CryptoKit
import Foundation

public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: String            // content hash
    public let size: Int64           // size of one copy
    public let files: [FileEntry]    // oldest first — the likely original

    public init(id: String, size: Int64, files: [FileEntry]) {
        self.id = id
        self.size = size
        self.files = files
    }

    /// Space freed by keeping a single copy.
    public var wasted: Int64 { size * Int64(files.count - 1) }
}

/// Finds files with identical content. Three passes so only real candidates are fully hashed:
/// same size → same first 64 KB → same SHA-256.
public enum DuplicateScanner {
    public static var defaultRoots: [URL] {
        ["Downloads", "Desktop", "Documents", "Movies", "Music", "Pictures"].map { URL.home.appendingPathComponent($0) }
    }

    public static func scan(roots: [URL] = defaultRoots, minimumSize: Int64 = .megabytes(1),
                            progress: (@Sendable (Int) -> Void)? = nil) -> [DuplicateGroup] {
        // Pass 1 — group by size.
        var bySize: [Int64: [FileEntry]] = [:]
        var seenInodes = Set<NSObject>()   // hard links point at the same data; count them once
        var scanned = 0
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]

        for root in roots where FileWalker.exists(root) {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if Task.isCancelled { return [] }
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                      let size = v.fileSize.map(Int64.init), size >= minimumSize else { continue }
                if let inode = v.fileResourceIdentifier as? NSObject {
                    if seenInodes.contains(inode) { continue }
                    seenInodes.insert(inode)
                }
                bySize[size, default: []].append(FileEntry(url: url, size: size, modified: v.contentModificationDate))
                scanned += 1
                if scanned % 500 == 0 { progress?(scanned) }
            }
        }
        progress?(scanned)

        // Pass 2 & 3 — narrow by head hash, confirm by full hash.
        var groups: [DuplicateGroup] = []
        for (size, candidates) in bySize where candidates.count > 1 {
            if Task.isCancelled { return [] }
            for headGroup in bucket(candidates, by: { hash($0.url, limit: 64 * 1024) }) where headGroup.value.count > 1 {
                let full = size <= 64 * 1024 ? [headGroup.key: headGroup.value]
                                             : bucket(headGroup.value, by: { hash($0.url, limit: nil) })
                for (digest, files) in full where files.count > 1 {
                    let sorted = files.sorted { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
                    groups.append(DuplicateGroup(id: digest, size: size, files: sorted))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    static func bucket(_ files: [FileEntry], by key: (FileEntry) -> String?) -> [String: [FileEntry]] {
        var result: [String: [FileEntry]] = [:]
        for file in files { if let k = key(file) { result[k, default: []].append(file) } }
        return result
    }

    /// SHA-256 of the first `limit` bytes (or the whole file), streamed in 1 MB chunks.
    static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? .max
        while remaining > 0 {
            let chunk = autoreleasepool { try? handle.read(upToCount: min(1 << 20, remaining)) }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

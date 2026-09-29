import Foundation

public struct InstallerFile: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case diskImage = "Disk image"
        case package = "Installer package"
        case archive = "Xcode archive"
        case macOSInstaller = "macOS installer"
        case appBuild = "App build"
    }

    public var id: URL { file.url }
    public let file: FileEntry
    public let kind: Kind

    public func age(now: Date = .now) -> Int? {
        file.modified.map { Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0 }
    }
}

/// Finds installers and build outputs that are almost always safe to delete once used:
/// .dmg / .pkg / .xip / .iso, app builds (.ipa / .apk / .aab) and "Install macOS" apps.
public enum InstallerScanner {
    static let kinds: [String: InstallerFile.Kind] = [
        "dmg": .diskImage, "iso": .diskImage, "sparseimage": .diskImage,
        "pkg": .package, "mpkg": .package,
        "xip": .archive,
        "ipa": .appBuild, "apk": .appBuild, "aab": .appBuild,
    ]

    public static var defaultRoots: [URL] {
        ["Downloads", "Desktop", "Documents"].map { URL.home.appendingPathComponent($0) }
    }

    public static func scan(roots: [URL] = defaultRoots, maxDepth: Int = 4) -> [InstallerFile] {
        var found: [InstallerFile] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]

        for root in roots where FileWalker.exists(root) {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if Task.isCancelled { return found }
                if enumerator.level > maxDepth { enumerator.skipDescendants(); continue }
                guard let kind = kinds[url.pathExtension.lowercased()] else { continue }
                // .pkg can be a bundle directory; size it either way.
                let size = FileWalker.allocatedSize(of: url)
                found.append(InstallerFile(file: FileEntry(url: url, size: size, modified: FileWalker.modificationDate(of: url)), kind: kind))
            }
        }

        let apps = URL(fileURLWithPath: "/Applications")
        for app in FileWalker.children(of: apps) where app.lastPathComponent.hasPrefix("Install macOS") {
            found.append(InstallerFile(file: FileEntry(url: app, size: FileWalker.allocatedSize(of: app),
                                                       modified: FileWalker.modificationDate(of: app)),
                                       kind: .macOSInstaller))
        }

        return found.sorted { $0.file.size > $1.file.size }
    }
}

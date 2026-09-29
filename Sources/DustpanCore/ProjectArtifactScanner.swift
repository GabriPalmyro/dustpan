import Foundation

/// A regenerable folder inside a code project (node_modules, build, Pods…).
public struct ProjectArtifact: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let project: URL
    public let size: Int64
    /// Last time the project was worked on (last commit/checkout, falling back to the folder's mtime).
    public let lastTouched: Date?
    public let isGitWorktree: Bool

    public var kind: String { url.lastPathComponent }
    public var regenerateHint: String { ProjectArtifactScanner.rules[kind]?.hint ?? "" }

    public func idleDays(now: Date = .now) -> Int? {
        lastTouched.map { Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0 }
    }
}

public enum ProjectArtifactScanner {
    struct Rule {
        /// The artifact only counts if its parent has one of these files — "build" alone is too generic.
        let markers: [String]
        let hint: String
    }

    static let rules: [String: Rule] = [
        "node_modules": Rule(markers: ["package.json"], hint: "npm / yarn / pnpm install"),
        ".dart_tool":   Rule(markers: ["pubspec.yaml"], hint: "flutter pub get"),
        "build":        Rule(markers: ["pubspec.yaml", "build.gradle", "build.gradle.kts", "package.json", "CMakeLists.txt"],
                             hint: "rebuilt on next build"),
        "Pods":         Rule(markers: ["Podfile"], hint: "pod install"),
        ".gradle":      Rule(markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
                             hint: "rebuilt on next Gradle build"),
        ".build":       Rule(markers: ["Package.swift"], hint: "swift build"),
        ".next":        Rule(markers: ["package.json"], hint: "next build"),
        "DerivedData":  Rule(markers: [], hint: "rebuilt by Xcode"),
    ]

    public static var defaultRoots: [URL] {
        ["Desktop", "Documents", "Developer", "Projects", "Code", "src"]
            .map { URL.home.appendingPathComponent($0) }
            .filter(FileWalker.exists)
    }

    public static func scan(roots: [URL] = defaultRoots, maxDepth: Int = 7,
                            minimumSize: Int64 = .megabytes(50)) -> [ProjectArtifact] {
        var found: [ProjectArtifact] = []
        let library = URL.home.appendingPathComponent("Library")

        for root in roots where FileWalker.exists(root) {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsPackageDescendants], errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if Task.isCancelled { return found }
                guard let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      v.isDirectory == true, v.isSymbolicLink != true else { continue }
                if url.isInside(library) || enumerator.level > maxDepth { enumerator.skipDescendants(); continue }

                let name = url.lastPathComponent
                if let rule = rules[name] {
                    let project = url.deletingLastPathComponent()
                    let hasMarker = rule.markers.isEmpty
                        || rule.markers.contains { FileWalker.exists(project.appendingPathComponent($0)) }
                    guard hasMarker else { continue }
                    enumerator.skipDescendants()
                    let size = FileWalker.allocatedSize(of: url)
                    guard size >= minimumSize else { continue }
                    found.append(ProjectArtifact(url: url, project: project, size: size,
                                                 lastTouched: lastTouched(project),
                                                 isGitWorktree: isWorktree(project)))
                } else if name.hasPrefix(".") {
                    // Hidden folders (.git, .cache, .venv…) never contain projects worth descending into.
                    enumerator.skipDescendants()
                }
            }
        }
        return found.sorted { $0.size > $1.size }
    }

    /// `logs/HEAD` only changes on commit, checkout, merge… — unlike `index`, which IDEs touch
    /// constantly just by running `git status`.
    static func lastTouched(_ project: URL) -> Date? {
        FileWalker.modificationDate(of: gitDirectory(project).appendingPathComponent("logs/HEAD"))
            ?? FileWalker.modificationDate(of: project)
    }

    /// `.git` folder, or for a worktree the directory its `.git` file points to (`gitdir: …`).
    static func gitDirectory(_ project: URL) -> URL {
        let git = project.appendingPathComponent(".git")
        if isWorktree(project),
           let line = try? String(contentsOf: git, encoding: .utf8),
           let path = line.split(separator: "\n").first?.split(separator: " ", maxSplits: 1).last {
            return URL(fileURLWithPath: String(path), relativeTo: project).standardizedFileURL
        }
        return git
    }

    /// Git worktrees have a `.git` *file* pointing at the main repository.
    static func isWorktree(_ project: URL) -> Bool {
        let git = project.appendingPathComponent(".git")
        return FileWalker.exists(git) && !FileWalker.isDirectory(git)
    }
}

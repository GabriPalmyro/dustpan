import DustpanCore
import SwiftUI

struct ProjectsView: View {
    @Environment(AppState.self) private var state
    @AppStorage(Pref.staleProjectDays) private var staleDays = 14
    @State private var selection: Set<URL> = []
    @State private var confirming = false
    @State private var sortOrder = [KeyPathComparator(\ProjectArtifact.size, order: .reverse)]

    private var rows: [ProjectArtifact] { state.artifacts.sorted(using: sortOrder) }
    private var selected: [ProjectArtifact] { state.artifacts.filter { selection.contains($0.id) } }
    private var selectedSize: Int64 { selected.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Project Artifacts",
                          subtitle: "node_modules, build, Pods, .dart_tool… inside your code projects. All regenerable — worth clearing on projects you're not touching.",
                          isScanning: state.scanning.contains(.projects)) {
                Task { await state.scanProjects() }
            }

            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Project", value: \.project.lastPathComponent) { a in
                    HStack(spacing: 6) {
                        Text(a.project.lastPathComponent)
                        if a.isGitWorktree {
                            Text("worktree").font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    .help(a.project.abbreviatedPath)
                }
                .width(min: 160, ideal: 240)
                TableColumn("Folder", value: \.kind) { Text($0.kind).monospaced().foregroundStyle(.secondary) }
                    .width(ideal: 100)
                TableColumn("Idle", value: \.lastTouched, comparator: OptionalDateComparator(order: .reverse)) { a in
                    let days = a.idleDays() ?? 0
                    Text(days == 0 ? "today" : "\(days)d")
                        .foregroundStyle(days >= staleDays ? .primary : .secondary)
                }
                .width(ideal: 60)
                TableColumn("Regenerate with") { Text($0.regenerateHint).foregroundStyle(.secondary) }
                    .width(ideal: 150)
                TableColumn("Size", value: \.size) { SizeText($0.size) }
                    .width(ideal: 80)
            }
            .contextMenu(forSelectionType: URL.self) { urls in
                if let url = urls.first { Button("Reveal in Finder") { Finder.reveal(url) } }
            } primaryAction: { urls in
                urls.first.map(Finder.reveal)
            }
            .overlay {
                if state.artifacts.isEmpty && !state.scanning.contains(.projects) {
                    ContentUnavailableView("No build artifacts found", systemImage: "hammer",
                                           description: Text("Looks in Desktop, Documents, Developer, Projects, Code and src."))
                }
            }

            ActionBar {
                Button("Select Idle \(staleDays)+ Days") {
                    selection = Set(state.artifacts.filter { ($0.idleDays() ?? 0) >= staleDays }.map(\.id))
                }
                Spacer()
                Button(selectedSize.labeled("Delete")) { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty)
            }
        }
        .navigationTitle("Project Artifacts")
        .confirmationDialog("Delete \(selected.count) folder(s), \(selectedSize.formattedBytes)?", isPresented: $confirming) {
            Button("Delete", role: .destructive) {
                let urls = Array(selection)
                selection = []
                Task { await state.delete(urls) }
            }
        } message: {
            Text("They're deleted permanently (trashing them wouldn't free any space). Each project rebuilds them on its next install or build.")
        }
    }
}

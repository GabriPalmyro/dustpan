import DustpanCore
import SwiftUI

struct InstallersView: View {
    @Environment(AppState.self) private var state
    @State private var selection: Set<URL> = []
    @State private var sortOrder = [KeyPathComparator(\InstallerFile.file.size, order: .reverse)]

    private var rows: [InstallerFile] { state.installers.sorted(using: sortOrder) }
    private var selectedSize: Int64 { state.installers.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.file.size } }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Installers",
                          subtitle: "Disk images, packages and app builds in Downloads, Desktop and Documents. Once installed or shipped, you rarely need them.",
                          isScanning: state.scanning.contains(.installers)) {
                Task { await state.scanInstallers() }
            }

            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \.file.name) { Text($0.file.name).help($0.file.url.abbreviatedPath) }
                TableColumn("Kind", value: \.kind.rawValue) { Text($0.kind.rawValue).foregroundStyle(.secondary) }
                    .width(ideal: 110)
                TableColumn("Folder") { Text($0.file.url.deletingLastPathComponent().abbreviatedPath).foregroundStyle(.secondary) }
                TableColumn("Modified", value: \.file.modified, comparator: OptionalDateComparator()) {
                    Text($0.file.modified?.relative ?? "—").foregroundStyle(.secondary)
                }
                .width(ideal: 110)
                TableColumn("Size", value: \.file.size) { SizeText($0.file.size) }
                    .width(ideal: 80)
            }
            .contextMenu(forSelectionType: URL.self) { urls in
                if let url = urls.first { Button("Reveal in Finder") { Finder.reveal(url) } }
            } primaryAction: { urls in
                urls.first.map(Finder.reveal)
            }
            .overlay {
                if state.installers.isEmpty && !state.scanning.contains(.installers) {
                    ContentUnavailableView("No installers lying around", systemImage: "shippingbox")
                }
            }

            ActionBar {
                Button("Select Older Than 30 Days") {
                    let cutoff = Date.now.addingTimeInterval(-30 * 86_400)
                    selection = Set(state.installers.filter { ($0.file.modified ?? .now) < cutoff }.map(\.id))
                }
                Spacer()
                Button(selectedSize.labeled("Move", suffix: " to Trash")) {
                    let urls = Array(selection)
                    selection = []
                    Task { await state.trash(urls) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection.isEmpty)
            }
        }
        .navigationTitle("Installers")
    }
}

/// Sorts nil dates last.
struct OptionalDateComparator: SortComparator {
    var order: SortOrder = .forward

    func compare(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        let l = lhs ?? .distantPast, r = rhs ?? .distantPast
        let result: ComparisonResult = l < r ? .orderedAscending : (l > r ? .orderedDescending : .orderedSame)
        return order == .forward ? result : result.reversed
    }
}

private extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }
}

import DustpanCore
import SwiftUI

struct JunkView: View {
    @Environment(AppState.self) private var state
    @State private var selected: Set<String> = []
    @State private var confirming = false

    private var chosen: [CleanupItem] { state.junk.filter { selected.contains($0.id) && $0.isCleanable } }
    private var chosenSize: Int64 { chosen.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Junk",
                          subtitle: "Caches, logs and build leftovers that apps regenerate on their own.",
                          isScanning: state.scanning.contains(.junk)) {
                Task { await state.scanJunk() }
            }

            List {
                ForEach(CleanupGroup.allCases, id: \.self) { group in
                    let items = state.junk.filter { $0.group == group }
                    if !items.isEmpty {
                        Section {
                            ForEach(items) { item in
                                JunkRow(item: item, isOn: binding(for: item))
                            }
                        } header: {
                            Text(group.rawValue)
                        } footer: {
                            if group == .manual {
                                Text("Dustpan measures these but won't delete them — follow the tip for each.")
                            }
                        }
                    }
                }
            }
            .overlay {
                if state.junk.isEmpty && !state.scanning.contains(.junk) {
                    ContentUnavailableView("No junk found", systemImage: "sparkles")
                }
            }

            ActionBar {
                Button(selected.isEmpty ? "Select All" : "Deselect All") {
                    // The Trash is user data — always an explicit choice.
                    selected = selected.isEmpty ? Set(state.junk.filter { $0.isCleanable && $0.id != "trash" }.map(\.id)) : []
                }
                Spacer()
                Button(chosenSize.labeled("Clean")) { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(chosen.isEmpty)
            }
        }
        .navigationTitle("Junk")
        .confirmationDialog("Permanently delete \(chosenSize.formattedBytes)?", isPresented: $confirming) {
            Button("Clean", role: .destructive) {
                let items = chosen
                selected = []
                Task { await state.clean(items) }
            }
        } message: {
            Text(chosen.map(\.title).joined(separator: ", ") + ".\nThis skips the Trash.")
        }
    }

    private func binding(for item: CleanupItem) -> Binding<Bool> {
        Binding(
            get: { selected.contains(item.id) },
            set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } }
        )
    }
}

private struct JunkRow: View {
    let item: CleanupItem
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if item.isCleanable {
                Toggle("", isOn: $isOn).toggleStyle(.checkbox).labelsHidden()
            } else {
                Image(systemName: "hand.point.right").foregroundStyle(.secondary).frame(width: 16)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                Text(item.tip)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            if item.size > 0 { SizeText(item.size) }
        }
        .padding(.vertical, 4)
        .help(item.summary)
        .contextMenu {
            ForEach(item.paths.prefix(8), id: \.self) { path in
                Button("Reveal \(path.abbreviatedPath)") { Finder.reveal(path) }
            }
        }
    }
}

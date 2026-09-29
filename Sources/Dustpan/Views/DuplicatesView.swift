import DustpanCore
import SwiftUI

struct DuplicatesView: View {
    @Environment(AppState.self) private var state
    /// Files marked for removal. By default: every copy except the oldest in each group.
    @State private var marked: Set<URL> = []

    private var markedSize: Int64 {
        state.duplicates.flatMap(\.files).filter { marked.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Duplicates",
                          subtitle: "Identical files (1 MB+) in Downloads, Desktop, Documents, Movies, Music and Pictures. The oldest copy is kept by default.",
                          isScanning: state.scanning.contains(.duplicates)) {
                Task { await scan() }
            }

            if state.scanning.contains(.duplicates) {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Comparing files… \(state.duplicateFilesSeen) read").foregroundStyle(.secondary)
                }
                .padding(40)
                Spacer()
            } else if !state.scanned.contains(.duplicates) {
                ContentUnavailableView {
                    Label("Find duplicate files", systemImage: "doc.on.doc")
                } description: {
                    Text("Reads and compares files in your personal folders. Takes a minute or two.")
                } actions: {
                    Button("Scan") { Task { await scan() } }.buttonStyle(.borderedProminent)
                }
            } else if state.duplicates.isEmpty {
                ContentUnavailableView("No duplicates", systemImage: "checkmark.circle")
            } else {
                List {
                    ForEach(state.duplicates) { group in
                        Section {
                            ForEach(group.files) { file in
                                DuplicateRow(file: file, isOn: binding(for: file, in: group))
                            }
                        } header: {
                            Text("\(group.files.count) copies · \(group.size.formattedBytes) each")
                        }
                    }
                }
            }

            ActionBar {
                Text("Moves files to the Trash, so nothing is lost until you empty it.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(markedSize.labeled("Move", suffix: " to Trash")) {
                    let urls = Array(marked)
                    marked = []
                    Task { await state.trash(urls) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(marked.isEmpty)
            }
        }
        .navigationTitle("Duplicates")
    }

    private func scan() async {
        await state.scanDuplicates()
        marked = Set(state.duplicates.flatMap { $0.files.dropFirst().map(\.url) })
    }

    /// Never lets every copy in a group be marked — one always survives.
    private func binding(for file: FileEntry, in group: DuplicateGroup) -> Binding<Bool> {
        Binding(
            get: { marked.contains(file.url) },
            set: { mark in
                if !mark { marked.remove(file.url); return }
                let others = group.files.filter { $0.url != file.url }
                if others.allSatisfy({ marked.contains($0.url) }) { return }
                marked.insert(file.url)
            }
        )
    }
}

private struct DuplicateRow: View {
    let file: FileEntry
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $isOn).toggleStyle(.checkbox).labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                Text(file.url.deletingLastPathComponent().abbreviatedPath)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(file.modified?.relative ?? "").font(.caption).foregroundStyle(.secondary)
        }
        .contextMenu { Button("Reveal in Finder") { Finder.reveal(file.url) } }
    }
}

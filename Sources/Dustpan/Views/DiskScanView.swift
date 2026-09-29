import DustpanCore
import SwiftUI

struct DiskScanView: View {
    @Environment(AppState.self) private var state
    @State private var path: [URL] = [.home]
    @State private var cache: [URL: DiskScan] = [:]
    @State private var loading = false
    @State private var showLargeFiles = false

    private var current: URL { path.last ?? .home }
    private var scan: DiskScan? { cache[current] }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Disk Scan",
                          subtitle: "Where the space actually goes. Double-click a folder to open it.",
                          isScanning: loading) {
                cache[current] = nil
                Task { await load() }
            }

            HStack(spacing: 6) {
                Button("Back", systemImage: "chevron.left") { path.removeLast() }
                    .labelStyle(.iconOnly)
                    .disabled(path.count < 2)
                Text(current.abbreviatedPath).font(.callout.monospaced()).lineLimit(1).truncationMode(.head)
                Spacer()
                Menu("Location") {
                    Button("Home") { path = [.home] }
                    Button("Macintosh HD") { path = [URL(fileURLWithPath: "/")] }
                    Button("Choose…") { choose() }
                }
                .fixedSize()
                Picker("", selection: $showLargeFiles) {
                    Text("Folders").tag(false)
                    Text("Large Files").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            Group {
                if let scan {
                    if showLargeFiles { largeFiles(scan) } else { folders(scan) }
                } else {
                    ProgressView("Measuring \(current.lastPathComponent)…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Disk Scan")
        .task(id: current) { await load() }
    }

    private func folders(_ scan: DiskScan) -> some View {
        List(scan.children) { node in
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path))
                    .resizable().frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(node.name)
                    ProgressView(value: Double(node.size), total: Double(max(scan.total, 1)))
                        .progressViewStyle(.linear)
                        .tint(.secondary)
                }
                SizeText(node.size).frame(width: 80, alignment: .trailing)
                if node.isDirectory {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { if node.isDirectory { path.append(node.url) } }
            .contextMenu { fileMenu(node.url) }
        }
    }

    private func largeFiles(_ scan: DiskScan) -> some View {
        List(scan.largeFiles) { file in
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                    .resizable().frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                    Text(file.url.deletingLastPathComponent().abbreviatedPath)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                SizeText(file.size)
            }
            .contextMenu { fileMenu(file.url) }
        }
        .overlay {
            if scan.largeFiles.isEmpty {
                ContentUnavailableView("No large files here", systemImage: "doc",
                                       description: Text("Files bigger than the threshold in Settings show up here."))
            }
        }
    }

    @ViewBuilder
    private func fileMenu(_ url: URL) -> some View {
        Button("Reveal in Finder") { Finder.reveal(url) }
        Button("Move to Trash") {
            Task {
                await state.trash([url])
                cache = [:]
                await load()
            }
        }
    }

    private func load() async {
        guard cache[current] == nil else { return }
        loading = true
        let url = current
        cache[url] = await DiskScanner.scan(url, largeFileThreshold: Preferences.largeFileThreshold)
        loading = false
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { path = [url] }
    }
}

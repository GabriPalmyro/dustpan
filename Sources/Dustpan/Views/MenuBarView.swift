import DustpanCore
import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @State private var monitor = SystemMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SystemMeters(monitor: monitor)

            ForEach(monitor.hogs) { HogRow(hog: $0, monitor: monitor) }

            if !monitor.groups.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Using the most memory").font(.caption).foregroundStyle(.secondary)
                    ForEach(monitor.topByMemory(4)) { ProcessGroupRow(group: $0, monitor: monitor) }
                }
            }

            Divider()

            if let disk = state.disk {
                DiskSummary(disk: disk, health: state.health, compact: true)
            }

            if let top = state.recommendations.first {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Biggest win").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(top.title)
                        Spacer()
                        SizeText(top.size)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                MenuButton("Open Dustpan…", symbol: "macwindow") { state.openMainWindow?() }
                MenuButton(state.scanning.isEmpty ? "Scan Now" : "Scanning…", symbol: "magnifyingglass") {
                    Task { await state.scanAll() }
                }
                .disabled(!state.scanning.isEmpty)
                SettingsLink {
                    Label("Settings…", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                MenuButton("Quit", symbol: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
        .task { state.refreshDisk() }
        .task { await monitor.watchProcesses() }
    }
}

private struct MenuButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

import DustpanCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let disk = state.disk {
                    DiskSummary(disk: disk, health: state.health)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recommendations").font(.headline)
                        Spacer()
                        if !state.scanning.isEmpty {
                            ProgressView().controlSize(.small)
                            Text("Scanning…").foregroundStyle(.secondary)
                        } else {
                            Button("Scan Again") { Task { await state.scanAll() } }
                        }
                    }

                    if state.recommendations.isEmpty && state.scanning.isEmpty {
                        ContentUnavailableView("Nothing worth cleaning",
                                               systemImage: "checkmark.circle",
                                               description: Text("Your disk is in good shape."))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(state.recommendations) { rec in
                                RecommendationRow(rec: rec) { state.selection = rec.destination }
                                if rec.id != state.recommendations.last?.id { Divider() }
                            }
                        }
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                Text("Duplicates and Disk Scan are on-demand — they read a lot of files.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("Overview")
        .task { state.refreshDisk() }
    }
}

private struct RecommendationRow: View {
    let rec: Recommendation
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: rec.destination.symbol)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(rec.title)
                    Text(rec.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 16)
                SizeText(rec.size)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

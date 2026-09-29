import AppKit
import DustpanCore
import SwiftUI

struct SizeText: View {
    let bytes: Int64
    init(_ bytes: Int64) { self.bytes = bytes }

    var body: some View {
        Text(bytes.formattedBytes)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

extension DiskHealth {
    var tint: Color {
        switch self {
        case .healthy: .accentColor
        case .low: .orange
        case .critical: .red
        }
    }

    var label: String {
        switch self {
        case .healthy: "Healthy"
        case .low: "Low on space"
        case .critical: "Almost full"
        }
    }
}

struct DiskSummary: View {
    let disk: DiskStatus
    let health: DiskHealth
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(disk.available.formattedBytes) free")
                    .font(compact ? .headline : .largeTitle.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Text(health.label)
                    .font(compact ? .caption : .callout)
                    .foregroundStyle(health == .healthy ? .secondary : health.tint)
            }
            Gauge(value: disk.usedFraction) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .tint(health.tint)
            Text("\(disk.used.formattedBytes) of \(disk.total.formattedBytes) used")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Bottom bar with the section's primary action.
struct ActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
    }
}

/// Header shown above each section: what it is, plus rescan.
struct SectionHeader: View {
    let title: String
    let subtitle: String
    let isScanning: Bool
    let scan: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            if isScanning {
                ProgressView().controlSize(.small)
            } else {
                Button("Rescan", systemImage: "arrow.clockwise", action: scan)
                    .labelStyle(.iconOnly)
                    .help("Rescan")
            }
        }
        .padding([.horizontal, .top], 20)
        .padding(.bottom, 12)
    }
}

extension Int64 {
    /// "Clean 1.2 GB", or just "Clean" when nothing is selected.
    func labeled(_ verb: String, suffix: String = "") -> String {
        self > 0 ? "\(verb) \(formattedBytes)\(suffix)" : verb
    }
}

enum Finder {
    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

extension Date {
    var relative: String {
        RelativeDateTimeFormatter().localizedString(for: self, relativeTo: .now)
    }
}

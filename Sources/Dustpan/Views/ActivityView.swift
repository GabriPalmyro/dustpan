import Charts
import DustpanCore
import SwiftUI

/// CPU / GPU / Memory meters. Used compact in the menu bar popover and full-size in the Activity section.
struct SystemMeters: View {
    let monitor: SystemMonitor
    var showCharts = false

    var body: some View {
        if let s = monitor.snapshot {
            VStack(alignment: .leading, spacing: showCharts ? 16 : 8) {
                Meter(title: "CPU", value: s.cpu, detail: s.cpu.percent,
                      history: showCharts ? monitor.history.map(\.cpu) : nil)
                if let gpu = s.gpu {
                    Meter(title: "GPU", value: gpu, detail: gpu.percent,
                          history: showCharts ? monitor.history.map { $0.gpu ?? 0 } : nil)
                }
                Meter(title: "Memory", value: s.memoryFraction,
                      detail: "\(s.memoryUsed.formattedBytes) of \(s.memoryTotal.formattedBytes)",
                      tint: s.pressure.tint,
                      history: showCharts ? monitor.history.map(\.memoryFraction) : nil)
                HStack(spacing: 4) {
                    Text("Pressure \(s.pressure.label)")
                        .foregroundStyle(s.pressure == .normal ? AnyShapeStyle(.secondary) : AnyShapeStyle(s.pressure.tint))
                    if s.swapUsed > 0 { Text("· Swap \(s.swapUsed.formattedBytes)").foregroundStyle(.secondary) }
                }
                .font(.caption)
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }
}

private struct Meter: View {
    let title: String
    let value: Double
    let detail: String
    var tint: Color = .accentColor
    var history: [Double]?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(detail).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(history == nil ? .callout : .body)
            if let history {
                // Newest sample pinned to the right edge, like Activity Monitor.
                let start = SystemMonitor.historyLength - history.count
                Chart(Array(history.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("t", start + i), y: .value(title, v))
                        .foregroundStyle(tint.opacity(0.25))
                    LineMark(x: .value("t", start + i), y: .value(title, v))
                        .foregroundStyle(tint)
                }
                .chartYScale(domain: 0...1)
                .chartXScale(domain: 0...(SystemMonitor.historyLength - 1))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 44)
            } else {
                Gauge(value: min(max(value, 0), 1)) { EmptyView() }
                    .gaugeStyle(.linearCapacity)
                    .tint(tint)
            }
        }
    }
}

/// One app (or process) with its usage and, when it's a regular app, a Quit button.
struct ProcessGroupRow: View {
    let group: ProcessGroup
    let monitor: SystemMonitor
    var metric: KeyPath<ProcessGroup, String> = \.memoryLabel

    var body: some View {
        HStack(spacing: 8) {
            icon.resizable().frame(width: 16, height: 16)
            Text(group.name).lineLimit(1)
            Spacer()
            Text(group[keyPath: metric]).monospacedDigit().foregroundStyle(.secondary)
            if monitor.quittableApp(group) != nil {
                Button("Quit", systemImage: "xmark.circle.fill") { monitor.quit(group) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Quit \(group.name)")
            } else {
                Color.clear.frame(width: 16, height: 1)
            }
        }
    }

    private var icon: Image {
        if let bundle = group.appBundle { return Image(nsImage: NSWorkspace.shared.icon(forFile: bundle.path)) }
        return Image(systemName: "gearshape")
    }
}

struct HogRow: View {
    let hog: DevMemoryHogs.Hog
    let monitor: SystemMonitor
    @State private var stopping = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hammer").frame(width: 16).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(hog.title)
                Text(hog.tip).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if hog.memory > 0 { SizeText(hog.memory) }
            Button(stopping ? "Stopping…" : "Stop") {
                stopping = true
                Task { await monitor.stop(hog); stopping = false }
            }
            .disabled(stopping)
        }
    }
}

struct ActivityView: View {
    @State private var monitor = SystemMonitor.shared
    @State private var sortByCPU = false

    private var rows: [ProcessGroup] { sortByCPU ? monitor.topByCPU(25) : monitor.topByMemory(25) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SystemMeters(monitor: monitor, showCharts: true)

                if !monitor.hogs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dev tools holding memory").font(.headline)
                        ForEach(monitor.hogs) { HogRow(hog: $0, monitor: monitor) }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Top apps").font(.headline)
                        Spacer()
                        Picker("", selection: $sortByCPU) {
                            Text("Memory").tag(false)
                            Text("CPU").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    VStack(spacing: 6) {
                        ForEach(rows) { group in
                            ProcessGroupRow(group: group, monitor: monitor,
                                            metric: sortByCPU ? \.cpuLabel : \.memoryLabel)
                        }
                    }
                }

                Label("macOS keeps unused RAM busy as cache, so a full bar is normal. What matters is pressure: when it turns yellow or red and swap grows, quit the heaviest app above.",
                      systemImage: "lightbulb")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("Activity")
        .task { await monitor.watchProcesses() }
    }
}

extension ProcessGroup {
    var memoryLabel: String { memory.formattedBytes }
    var cpuLabel: String { String(format: "%.0f%%", cpu) }
}

extension MemoryPressure {
    var tint: Color {
        switch self {
        case .normal: .accentColor
        case .warning: .orange
        case .critical: .red
        }
    }
}

extension Double {
    var percent: String { String(format: "%.0f%%", self * 100) }
}

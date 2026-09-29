import DustpanCore
import SwiftUI

struct RulesView: View {
    @Environment(AppState.self) private var state
    @State private var running: String?

    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                ForEach($state.rules) { $rule in
                    RuleRow(rule: $rule, isRunning: running == rule.id) {
                        running = rule.id
                        Task {
                            await state.runNow(rule)
                            running = nil
                        }
                    }
                }
            } header: {
                Text("Rules")
            } footer: {
                Text("Rules run in the background while Dustpan is in the menu bar. \"When space is low\" uses the threshold from Settings. Everything starts off — turn on what you trust.")
                    .foregroundStyle(.secondary)
            }

            Section("Tip") {
                Label("Finder can empty old Trash items for you: Finder › Settings › Advanced › Remove items from the Trash after 30 days.",
                      systemImage: "lightbulb")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Auto Clean")
    }
}

private struct RuleRow: View {
    @Binding var rule: AutoCleanRule
    let isRunning: Bool
    let runNow: () -> Void

    var body: some View {
        HStack {
            Toggle(isOn: $rule.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.title)
                    if let last = rule.lastRun {
                        Text("Last run \(last.relative)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Spacer()

            if rule.id == AutoCleanRule.installersID {
                Stepper("older than \(rule.olderThanDays)d", value: $rule.olderThanDays, in: 7...365, step: 7)
                    .fixedSize()
                    .foregroundStyle(.secondary)
            }
            Picker("", selection: $rule.schedule) {
                ForEach(AutoCleanRule.Schedule.allCases, id: \.self) { Text($0.rawValue) }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(!rule.enabled)

            Button(action: runNow) {
                if isRunning { ProgressView().controlSize(.small) } else { Text("Run Now") }
            }
            .disabled(isRunning)
        }
    }
}

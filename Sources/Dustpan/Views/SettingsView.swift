import DustpanCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage(Pref.thresholdGB) private var thresholdGB = 20
    @AppStorage(Pref.checkIntervalMinutes) private var interval = 30
    @AppStorage(Pref.notificationsEnabled) private var notifications = true
    @AppStorage(Pref.menuBarStyle) private var menuBarStyle = MenuBarStyle.system
    @AppStorage(Pref.largeFileMB) private var largeFileMB = 500
    @AppStorage(Pref.staleProjectDays) private var staleDays = 14
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Monitoring") {
                Stepper("Warn when free space drops below \(thresholdGB) GB", value: $thresholdGB, in: 5...500, step: 5)
                Picker("Check every", selection: $interval) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("3 hours").tag(180)
                }
                Toggle("Send notifications", isOn: $notifications)
            }

            Section("Scanning") {
                Stepper("Large files are \(largeFileMB) MB+", value: $largeFileMB, in: 50...10_000, step: 50)
                Stepper("Projects are idle after \(staleDays) days", value: $staleDays, in: 1...365)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Picker("Menu bar shows", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.title) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
        .onChange(of: thresholdGB) { state.refreshDisk() }
    }
}

import DustpanCore
import ServiceManagement
import SwiftUI
import UserNotifications

/// First-launch checklist: the permissions Dustpan needs to work fully. Nothing is scanned until it's done,
/// so macOS doesn't throw permission dialogs at you before you know why.
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var fullDiskAccess = Permissions.hasFullDiskAccess
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @State private var loginItem = SMAppService.mainApp.status

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                Text("Welcome to Dustpan").font(.title.weight(.semibold))
                Text("Three quick things so Dustpan can watch your Mac from the menu bar.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 28)
            .padding(.bottom, 24)

            VStack(spacing: 0) {
                PermissionRow(
                    symbol: "lock.shield",
                    title: "Full Disk Access",
                    detail: "Lets Dustpan measure every folder in one go, instead of macOS asking separately for Documents, Desktop, Downloads… Dustpan only deletes what you confirm.",
                    recommended: true,
                    isDone: fullDiskAccess
                ) {
                    Button("Open Settings") { NSWorkspace.shared.open(Permissions.fullDiskAccessSettings) }
                }
                Divider().padding(.leading, 52)
                PermissionRow(
                    symbol: "bell.badge",
                    title: "Notifications",
                    detail: "A heads-up when free space runs low, with the biggest safe wins.",
                    isDone: notifications == .authorized || notifications == .provisional
                ) {
                    if notifications == .denied {
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    } else {
                        Button("Allow") { Task { await requestNotifications() } }
                    }
                }
                Divider().padding(.leading, 52)
                PermissionRow(
                    symbol: "power",
                    title: "Launch at login",
                    detail: "Keeps monitoring after a restart. It lives quietly in the menu bar.",
                    isDone: loginItem == .enabled
                ) {
                    if loginItem == .requiresApproval {
                        Button("Approve") { SMAppService.openSystemSettingsLoginItems() }
                    } else {
                        Button("Enable") {
                            try? SMAppService.mainApp.register()
                            loginItem = SMAppService.mainApp.status
                        }
                    }
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 28)

            Spacer(minLength: 20)

            HStack {
                if !fullDiskAccess {
                    Text("After enabling Full Disk Access, macOS may ask to quit and reopen Dustpan — that's expected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(fullDiskAccess ? "Start Using Dustpan" : "Continue Without") { finish() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 560, height: 580)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            // Back to menu-bar-only unless the main window is taking over.
            if !NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        // Permissions change in System Settings; poll cheaply while this window is open.
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh() async {
        fullDiskAccess = Permissions.hasFullDiskAccess
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        loginItem = SMAppService.mainApp.status
    }

    private func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Pref.onboardingDone)
        state.hasFullDiskAccess = fullDiskAccess
        dismissWindow(id: "onboarding")
        state.openMainWindow?()
    }
}

private struct PermissionRow<Action: View>: View {
    let symbol: String
    let title: String
    let detail: String
    var recommended = false
    let isDone: Bool
    @ViewBuilder let action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(isDone ? .green : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if recommended && !isDone {
                        Text("Recommended").font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if isDone {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                action
            }
        }
        .padding(14)
    }
}

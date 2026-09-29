import DustpanCore
import SwiftUI

@main
struct DustpanApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var state = AppState.shared
    @AppStorage(Pref.menuBarStyle) private var menuBarStyle = MenuBarStyle.system

    init() {
        Preferences.register()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(state)
        } label: {
            MenuBarLabel(style: menuBarStyle)
                .environment(state)
        }
        .menuBarExtraStyle(.window)

        Window("Dustpan", id: "main") {
            MainView()
                .environment(state)
        }
        .defaultSize(width: 860, height: 580)
        .windowResizability(.contentMinSize)

        Window("Welcome to Dustpan", id: "onboarding") {
            OnboardingView()
                .environment(state)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}

/// Always alive while the app runs, so it's where monitoring starts and `openWindow` gets captured.
private struct MenuBarLabel: View {
    let style: MenuBarStyle
    @State private var monitor = SystemMonitor.shared
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: state.health == .healthy ? "internaldrive" : "externaldrive.badge.exclamationmark")
            switch style {
            case .icon: EmptyView()
            case .freeSpace: if let disk = state.disk { Text(disk.available.formattedBytes) }
            case .system:
                if let s = monitor.snapshot {
                    Text("CPU \(s.cpu.percent)  MEM \(s.memoryFraction.percent)").monospacedDigit()
                }
            }
        }
        .task {
            state.openMainWindow = {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            state.openOnboarding = {
                openWindow(id: "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }
            state.startMonitoring()
            monitor.start()
            if !Preferences.onboardingDone {
                state.openOnboarding?()
            } else if CommandLine.arguments.contains("--open") {
                state.openMainWindow?()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Launching the app again from Finder / Spotlight while it's running opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated { AppState.shared.openMainWindow?() }
        return true
    }

    /// Granting Full Disk Access makes System Settings ask to "Quit & Reopen", but the reopen is unreliable
    /// for menu bar apps. When the quit request comes from System Settings, relaunch ourselves.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           let senderPID = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value,
           NSRunningApplication(processIdentifier: senderPID)?.bundleIdentifier == "com.apple.systempreferences" {
            relaunch()
        }
        return .terminateNow
    }

    private func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Outlives us: waits for this instance to exit, then opens the bundle again.
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$1\"", "sh", Bundle.main.bundlePath]
        try? process.run()
    }
}

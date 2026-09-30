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
    /// Set by the menu bar's "Quit Dustpan" — the one in-app way to really quit.
    private static var quitRequested = false

    static func quit() {
        quitRequested = true
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Closing the last window (red X, ⌘W) leaves Dustpan running in the menu bar, out of the Dock.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
            let closing = note.object as? NSWindow
            DispatchQueue.main.async {
                let open = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) }
                if !open { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Launching the app again from Finder / Spotlight while it's running opens the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated { AppState.shared.openMainWindow?() }
        return true
    }

    /// Granting Full Disk Access makes System Settings ask to "Quit & Reopen", but the reopen is unreliable
    /// for menu bar apps. When the quit request comes from System Settings, relaunch ourselves.
    ///
    /// ⌘Q from the app menu doesn't quit either: it closes the windows and keeps monitoring in the background.
    /// Real quits come from the menu bar's "Quit Dustpan", the Dock, or logout/shutdown (those arrive as Apple Events).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.quitRequested { return .terminateNow }
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }.forEach { $0.close() }
            NSApp.setActivationPolicy(.accessory)
            return .terminateCancel
        }
        if let senderPID = event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value,
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

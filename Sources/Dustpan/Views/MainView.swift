import DustpanCore
import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $state.selection) { item in
                Label(item.title, systemImage: item.symbol)
                    .badge(badge(for: item))
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            detail(for: state.selection ?? .overview)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 480)
        .overlay(alignment: .bottom) { toast }
        .onAppear {
            // Show in the Dock and ⌘-Tab while the window is open; menu-bar-only otherwise.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .task {
            // No scanning (and no folder-permission dialogs) until onboarding is done.
            guard Preferences.onboardingDone else { state.openOnboarding?(); return }
            if state.scanned.isEmpty { await state.scanAll() }
        }
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .overview: OverviewView()
        case .activity: ActivityView()
        case .junk: JunkView()
        case .installers: InstallersView()
        case .duplicates: DuplicatesView()
        case .projects: ProjectsView()
        case .diskScan: DiskScanView()
        case .rules: RulesView()
        }
    }

    private func badge(for item: SidebarItem) -> Text? {
        let bytes: Int64 = switch item {
        case .junk: state.junk.filter(\.isCleanable).reduce(0) { $0 + $1.size }
        case .installers: state.installers.reduce(0) { $0 + $1.file.size }
        case .duplicates: state.duplicates.reduce(0) { $0 + $1.wasted }
        case .projects: state.artifacts.reduce(0) { $0 + $1.size }
        default: 0
        }
        return bytes > 0 ? Text(bytes.formattedBytes) : nil
    }

    @ViewBuilder
    private var toast: some View {
        if let message = state.lastResult {
            Text(message)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 56)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(6))
                    withAnimation { state.lastResult = nil }
                }
        }
    }
}

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: GestaltStore
    @ObservedObject private var respring = RespringHelper.shared
    @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false

    /// Onboarding only makes sense on a supported device.
    private var supportsOnboarding: Bool {
        if case .supported = DeviceCompatibility.currentStatus { return true }
        return false
    }

    var body: some View {
        Group {
            switch DeviceCompatibility.currentStatus {
            case .supported:
                MainTabView()
            case .unsupported(let reason):
                UnsupportedView(reason: reason)
            }
        }
        .overlay {
            if respring.isRespringing {
                NeoSpringView()
            }
        }
        .fullScreenCover(isPresented: .constant(!hasAcceptedDisclaimer)) {
            DisclaimerView { hasAcceptedDisclaimer = true }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
            }
        }
        .onAppear {
            if hasAcceptedDisclaimer && !hasSeenOnboarding && supportsOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: hasAcceptedDisclaimer) { _, newValue in
            // The disclaimer cover dismisses first; present onboarding after.
            if newValue && !hasSeenOnboarding && supportsOnboarding {
                showOnboarding = true
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Tweaks", systemImage: "switch.2") }
            PosterBoardView()
                .tabItem { Label("PosterBoard", systemImage: "square.stack.3d.up") }
            NavigationStack {
                LiquidGlassApplyView()
            }
            .tabItem { Label("Liquid Glass 26.2+", systemImage: "drop.fill") }
            NavigationStack {
                AirLiftPairingView()
            }
            .tabItem { Label("AirLift", systemImage: "cable.connector") }
            NavigationStack {
                AppDataView()
            }
            .tabItem { Label("App Data", systemImage: "folder") }
            NavigationStack {
                OtherExploitView()
            }
            .tabItem { Label("Other Exploit", systemImage: "hammer") }
            SystemHubView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

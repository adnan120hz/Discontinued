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
                MainNavView()
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

// MARK: - Sections

/// The six top-level sections reachable from the floating menu panel.
/// Tapping a menu item swaps the main content area to that section; the
/// section views themselves are untouched — only this navigation chrome
/// changed.
enum AppSection: String, CaseIterable, Identifiable {
    case tweaks
    case posterBoard
    case liquidGlass
    case airLift
    case appData
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tweaks: return "Tweaks"
        case .posterBoard: return "PosterBoard"
        case .liquidGlass: return "Liquid Glass"
        case .airLift: return "AirLift"
        case .appData: return "App Data"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .tweaks: return "switch.2"
        case .posterBoard: return "square.stack.3d.up"
        case .liquidGlass: return "drop.fill"
        case .airLift: return "cable.connector"
        case .appData: return "folder"
        case .settings: return "gearshape"
        }
    }

    /// The content view for this section. Navigation stacks are preserved
    /// exactly as they were under the old tab bar.
    @ViewBuilder
    var destination: some View {
        switch self {
        case .tweaks:
            HomeView()
        case .posterBoard:
            PosterBoardView()
        case .liquidGlass:
            NavigationStack { LiquidGlassApplyView() }
        case .airLift:
            NavigationStack { AirLiftPairingView() }
        case .appData:
            AppDataView()
        case .settings:
            SystemHubView()
        }
    }
}

// MARK: - Floating menu navigation

/// Single-screen root: the selected section fills the screen and a floating
/// Liquid Glass menu panel sits near the top. Portrait shows the full menu
/// box; landscape falls back to a compact horizontal chip row.
struct MainNavView: View {
    @State private var section: AppSection = .tweaks
    @State private var panelHeight: CGFloat = 320
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// The floating box is portrait-only; landscape gets the chip row.
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            ZStack(alignment: .top) {
                // Main content area, pushed below the floating panel so the
                // panel never covers a section's navigation bar or buttons.
                section.destination
                    .padding(.top, topInset + 8 + panelHeight + 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Floating menu panel overlay, near the top of the screen.
                Group {
                    if isLandscape {
                        landscapeChips
                    } else {
                        portraitMenuBox
                    }
                }
                .padding(.top, topInset + 8)
                .padding(.horizontal, 16)
            }
            .background(Theme.page.ignoresSafeArea())
        }
        .onPreferenceChange(PanelHeightKey.self) { panelHeight = $0 }
        .animation(.snappy, value: section)
    }

    // MARK: Portrait menu box

    private var portraitMenuBox: some View {
        VStack(spacing: 2) {
            ForEach(AppSection.allCases) { item in
                menuRow(for: item)
            }
        }
        .padding(10)
        .wsGlassPanel(cornerRadius: 24)
        .background(PanelHeightReader())
    }

    private func menuRow(for item: AppSection) -> some View {
        let isSelected = item == section
        return Button {
            section = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : Theme.wsBlue)
                    .frame(width: 34, height: 34)
                    .background(
                        isSelected ? Theme.wsBlue : Theme.tintWash,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                // No lineLimit: titles wrap freely and are never cropped.
                Text(item.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.wsBlueDeep : .primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isSelected ? 1 : 0.45)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 46)
            .background(
                isSelected ? Theme.wsBlue.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }

    // MARK: Landscape chip row

    private var landscapeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(AppSection.allCases) { item in
                    chip(for: item)
                }
            }
            .padding(10)
        }
        .wsGlassPanel(cornerRadius: 22)
        .background(PanelHeightReader())
    }

    private func chip(for item: AppSection) -> some View {
        let isSelected = item == section
        return Button {
            section = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(item.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSelected ? Theme.wsBlue : Theme.tintWash,
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : Theme.wsBlueDeep)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }
}

// MARK: - Panel height measurement

/// Reports the floating panel's height so the content area can sit below it.
private struct PanelHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PanelHeightReader: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
        }
    }
}

// MARK: - Liquid Glass surface

extension View {
    /// Liquid-glass surface for the navigation chrome (menu panel, chips):
    /// the iOS 26 glass material with fluid continuous corners. On older
    /// releases it falls back to the solid lifted WorkSlop panel, so the
    /// iOS 17 deployment target keeps working.
    @ViewBuilder
    func wsGlassPanel(cornerRadius: CGFloat = 24) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self.wsFloat(cornerRadius: cornerRadius)
        }
    }
}

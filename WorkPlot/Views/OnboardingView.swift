import SwiftUI

/// First-launch tutorial: five swipeable pages covering what WorkSlop is,
/// the iOS support matrix, AirLift pairing, the backup & apply flow, and
/// the tweak categories.
///
/// Shown automatically after the disclaimer on first launch (see
/// `RootView`, gated by the `hasSeenOnboarding` AppStorage flag) and
/// re-openable from Settings > Tutorial. `onDone`, when set, is called on
/// finish/skip; otherwise the view dismisses itself via the environment.
struct OnboardingView: View {
    var onDone: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $page) {
                ForEach(0..<pageCount, id: \.self) { index in
                    ScrollView {
                        pageContent(index)
                            .padding(.horizontal, Theme.pagePadding)
                            .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            bottomBar
        }
        .background(Theme.page)
    }

    private func finish() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("WorkSlop")
                    .font(.headline)
                    .foregroundStyle(Theme.wsBlue)
                Text("Step \(page + 1) of \(pageCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if page < pageCount - 1 {
                Button("Skip") { finish() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var bottomBar: some View {
        Button {
            if page < pageCount - 1 {
                withAnimation(.snappy) { page += 1 }
            } else {
                finish()
            }
        } label: {
            Text(page < pageCount - 1 ? "Next" : "Get Started")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 28)
    }

    // MARK: - Pages

    @ViewBuilder
    private func pageContent(_ index: Int) -> some View {
        switch index {
        case 0: welcomePage
        case 1: supportMatrixPage
        case 2: pairingPage
        case 3: backupPage
        case 4: categoriesPage
        default: EmptyView()
        }
    }

    private func pageHero(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Theme.wsBlue.opacity(0.3), radius: 10, x: 0, y: 4)
                .padding(.top, 14)
            Text(title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    private func infoCard<Content: View>(title: String? = nil, titleIcon: String? = nil, titleTint: Color = .primary, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Label(title, systemImage: titleIcon ?? "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(titleTint)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .wsCard(cornerRadius: 16)
    }

    // MARK: Page 1 — What is WorkSlop + safety

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHero(symbol: "flask.fill",
                     title: "Welcome to WorkSlop",
                     subtitle: "An iOS customization toolkit. Stage tweaks, review them, then write them to your device.")
            infoCard(title: "What it does") {
                Text("WorkSlop stages changes — MobileGestalt values, preference keys, themes — and applies them with the bad_query exploit and AirLift pairing. Every change is reversible from its backup.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            infoCard(title: "Safety first", titleIcon: "exclamationmark.triangle.fill", titleTint: Theme.caution) {
                Text("WorkSlop modifies system files. Apply one change at a time, keep a backup, and never apply tweaks you don't understand. You are responsible for your device and your data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Page 2 — iOS support matrix

    private var supportMatrixPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHero(symbol: "iphone",
                     title: "iOS support matrix",
                     subtitle: "What works depends on your iOS version. Unsupported versions hide tweaks and refuse writes.")
            infoCard {
                matrixRow(version: "iOS 27.0",
                          detail: "Full features. bad_query MobileGestalt writes plus AirLift pairing. Covers dev beta 1–5, public beta 1–3, RC and stable.",
                          supported: true)
                Divider()
                matrixRow(version: "iOS 26.6 – 26.7.x",
                          detail: "AirLift pairing plus PosterBoard and dialer theming via bad_query.",
                          supported: true)
                Divider()
                matrixRow(version: "Older or newer",
                          detail: "Not supported. The app explains why and blocks applying.",
                          supported: false)
            }
            infoCard {
                Text("Your device: \(WorkSlopSupport.deviceLabel())")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func matrixRow(version: String, detail: String, supported: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: supported ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(supported ? Theme.affirmative : Theme.caution)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(version)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Page 3 — AirLift pairing

    private var pairingPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHero(symbol: "cable.connector",
                     title: "AirLift pairing",
                     subtitle: "Pairing unlocks file writes outside the app sandbox. The steps depend on your iOS version.")
            infoCard(title: "On iOS 27 — in-app code flow") {
                VStack(alignment: .leading, spacing: 8) {
                    pairingStep(1, "Tap Start Pairing in the AirLift tab. WorkSlop generates a 6-digit pairing code.")
                    pairingStep(2, "Open Settings > Privacy & Security > Developer Mode, select WorkSlop, then Pairing File.")
                    pairingStep(3, "Enter the pairing code shown in WorkSlop.")
                    pairingStep(4, "Tap Confirm Pairing in WorkSlop. Pairing completes automatically.")
                }
            }
            infoCard(title: "On iOS 26.6 – 26.7 — pairing-file flow") {
                VStack(alignment: .leading, spacing: 8) {
                    pairingStep(1, "On your PC or Mac, use iLoader or iDevicePairing to generate a pairing file for this iPhone.")
                    pairingStep(2, "Transfer the file to this iPhone — for example with AirDrop, an email to yourself, or the Files app.")
                    pairingStep(3, "Tap Import Pairing File in the AirLift tab and choose the transferred file.")
                }
            }
        }
    }

    private func pairingStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.wsBlue, in: Circle())
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Page 4 — Backup & apply

    private var backupPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHero(symbol: "externaldrive.fill",
                     title: "Backup & apply",
                     subtitle: "Every apply starts from a pristine backup, so any change can be undone exactly.")
            infoCard(title: "How applying works") {
                Text("The first apply snapshots the untouched files. Writes are verified on read-back, and a failed write restores the backup automatically — the device is never left half-modified.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            infoCard(title: "Liquid Glass on iOS 27") {
                Text("Uses the full backup flow: full backup → modify → full restore.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Label("For iOS 27 you must press Backup first", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.caution)
                    .padding(.top, 2)
            }
            infoCard(title: "Liquid Glass on iOS 26") {
                Text("Uses the partial-restore flow: it applies directly with no backup step, and the last apply can be undone from the same screen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Page 5 — Tweak categories

    private var categoriesPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            pageHero(symbol: "square.grid.2x2.fill",
                     title: "Tweak categories",
                     subtitle: "Pick capabilities in the Tweaks tab, review them, then apply. These are the categories you'll find.")
            infoCard {
                VStack(spacing: 0) {
                    categoryRow(symbol: "display", name: "Display", detail: "Screen, wallpaper and visual options.")
                    Divider().padding(.leading, 44)
                    categoryRow(symbol: "iphone", name: "Device", detail: "Model identity and hardware options.")
                    Divider().padding(.leading, 44)
                    categoryRow(symbol: "gearshape", name: "System", detail: "SpringBoard and system behavior.")
                    Divider().padding(.leading, 44)
                    categoryRow(symbol: "drop.fill", name: "Liquid Glass", detail: "Disable Apple's glass effects, key by key.")
                    Divider().padding(.leading, 44)
                    categoryRow(symbol: "ipad", name: "iPad", detail: "iPad-only options.")
                    Divider().padding(.leading, 44)
                    categoryRow(symbol: "slider.horizontal.3", name: "Gestalt", detail: "Raw MobileGestalt field editing and presets.")
                    Divider().padding(.leading, 44)
                    categoryRow(symbol: "brain.head.profile", name: "Intelligence", detail: "Apple Intelligence region setup.")
                }
            }
            infoCard {
                Label("After applying, respring so the changes take effect.", systemImage: "arrow.clockwise")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func categoryRow(symbol: String, name: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.wsBlue.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

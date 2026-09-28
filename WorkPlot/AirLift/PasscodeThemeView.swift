import SwiftUI
import UniformTypeIdentifiers

// MARK: - PasscodeThemeView

/// "Passcode Theme (AirLift)": import a mandatory `.passthm` theme file and
/// apply it via `AirLiftFileWriter`.
///
/// Gated on BOTH conditions:
/// 1. `AirLiftManager` is paired (in-app RPPairing host flow on iOS 27 /
///    pairing-file import on iOS 26).
/// 2. `VPNCheck.requireVPN()` passes — the passcode-theme flow writes through
///    a local developer VPN tunnel. When no `utun*` interface is up, the UI
///    blocks with an explanatory message instead of failing silently.
///
/// On iOS 26.x, writes go through the bad_query fallback in
/// `AirLiftFileWriter` — never presented as AirLift.
struct PasscodeThemeView: View {
    @ObservedObject private var manager = AirLiftManager.shared
    @State private var showPicker = false
    @State private var themeName: String?
    @State private var themeData: Data?
    @State private var status: String?
    @State private var isApplying = false

    /// Custom document type for passcode theme files. `.passthm` is not a
    /// system-registered extension, so `UTType(filenameExtension:)` returns a
    /// dynamic exported type — good enough as the document picker filter.
    private static let passthmType = UTType(filenameExtension: "passthm") ?? .data

    // MARK: Destination (per AirCard-iOS)
    //
    /// Passcode theme asset location, per AirCard-iOS (Mak5er/AirCard-iOS,
    /// MIT): a `.passthm` file is a zip of keypad PNGs. AirCard-iOS extracts
    /// it and writes the PNGs to `/var/mobile/Library/Caches/TelephonyUI-10`
    /// — the same location iOS reads telephony UI assets from on iOS 18+.
    /// `__MACOSX/` metadata entries are skipped.
    static let passcodeThemeDestinationPath = "/var/mobile/Library/Caches/TelephonyUI-10"

    /// Gate state evaluated live for the UI.
    private var gate: PasscodeGate {
        if !manager.isPaired { return .notPaired }
        do {
            try VPNCheck.requireVPN()
            return .open
        } catch {
            return .noVPN(error.localizedDescription)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Passcode Theme (AirLift)")
                if !WorkSlopSupport.isIOS27() {
                    fallbackNoticeCard
                }
                gateCard
                if gate == .open {
                    pickerCard
                    if themeData != nil { applyCard }
                }
                if let status { statusLine(status) }
                infoCard
            }
            .padding(Theme.pagePadding)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Passcode Theme")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            AirLiftDocumentPicker(
                allowedTypes: [Self.passthmType],
                onPick: { url in
                    importTheme(from: url)
                    showPicker = false
                },
                onCancel: { showPicker = false }
            )
        }
    }

    // MARK: Gate

    /// Honest fallback notice: on iOS 26.x the on-device AirLift exploit is
    /// unavailable, so writes go through the bad_query fallback — never
    /// labeled as AirLift.
    private var fallbackNoticeCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.caution)
                .font(.title2)
            Text("iOS 26.x fallback: the AirLift exploit needs iOS 27+. On this device, writes go through the bad_query fallback instead — not AirLift.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private enum PasscodeGate: Equatable {
        case open
        case notPaired
        case noVPN(String)
    }

    @ViewBuilder
    private var gateCard: some View {
        switch gate {
        case .open:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(Theme.affirmative)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready").font(.headline)
                    Text("Paired with AirLift and a local dev VPN is active.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(Color(uiColor: .tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .notPaired:
            blockingCard(
                icon: "link.badge.plus",
                title: "Pairing required",
                body: "AirLift is not paired. Go to AirLift Pairing first — pair this iPhone with itself (iOS 27) or import your pairing file (iOS 26.6–26.7) — then come back."
            )
        case .noVPN(let detail):
            blockingCard(
                icon: "network.slash",
                title: "Local dev VPN required — blocked",
                body: detail + " The passcode-theme flow is blocked until a dev VPN tunnel is up; nothing will be written."
            )
        }
    }

    private func blockingCard(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.caution)
                    .font(.title2)
                Text(title).font(.headline)
            }
            Text(body)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Picker / Apply

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Theme File", detail: ".passthm required")
            if let themeName {
                HStack {
                    Image(systemName: "doc.fill").foregroundStyle(Theme.accent)
                    Text(themeName).font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    if let themeData {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(themeData.count),
                                                       countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("You must import a .passthm passcode theme file. Other file types are rejected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ActionButton(title: themeName == nil ? "Import .passthm File" : "Replace .passthm File",
                         systemImage: "square.and.arrow.down") {
                showPicker = true
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var applyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Apply")
            Text("Extracts the .passthm and writes the keypad assets to \(Self.passcodeThemeDestinationPath) via AirLiftFileWriter (per AirCard-iOS).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            ActionButton(title: "Apply Passcode Theme",
                         systemImage: "lock.fill",
                         isBusy: isApplying) {
                apply()
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Info")
            Text("The theme MUST be a .passthm file — other extensions are rejected with an explanation. The VPN gate is enforced with VPNCheck.requireVPN() (utun interface detection, no entitlements needed) and the flow blocks with an explanation when no local dev VPN is active. The .passthm is extracted on-device and its assets are written to /var/mobile/Library/Caches/TelephonyUI-10 (per AirCard-iOS).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusLine(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(message.hasPrefix("Failed") ? Theme.caution : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func importTheme(from url: URL) {
        // Mandatory extension check (case-insensitive): the passcode theme
        // MUST be a .passthm file, whatever the picker filter allowed.
        guard url.pathExtension.lowercased() == "passthm" else {
            themeData = nil
            themeName = nil
            status = "Failed: \"\(url.lastPathComponent)\" is not a .passthm file. " +
                     "Please import a passcode theme file ending in .passthm."
            return
        }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            themeData = try Data(contentsOf: url)
            themeName = url.lastPathComponent
            status = "Imported \"\(url.lastPathComponent)\"."
        } catch {
            themeData = nil
            themeName = nil
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func apply() {
        // Re-check the gate at apply time — the VPN can drop between
        // rendering and tapping.
        guard gate == .open else {
            status = "Failed: gate no longer open. Re-check pairing and VPN."
            return
        }
        guard let data = themeData, let name = themeName else { return }
        isApplying = true
        status = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let message: String
            do {
                // A .passthm is a zip of keypad PNGs (per AirCard-iOS).
                // Extract on-device, skip __MACOSX/, and write the assets
                // to TelephonyUI-10 — the location iOS reads them from.
                let entries = try ZipExtractor.extract(data)
                let pairs = themeWritePairs(from: entries)
                guard !pairs.isEmpty else {
                    throw ZipExtractorError.invalidArchive("no theme assets found in \(name)")
                }
                var failures: [String] = []
                for (relPath, fileData) in pairs {
                    let dest = (Self.passcodeThemeDestinationPath as NSString)
                        .appendingPathComponent(relPath)
                    do {
                        try AirLiftFileWriter.writeFile(data: fileData, to: dest)
                    } catch {
                        failures.append("\(relPath): \(error.localizedDescription)")
                    }
                }
                if failures.isEmpty {
                    message = "Applied \(name) (\(pairs.count) assets). Respring to take effect."
                } else {
                    message = "Failed: \(failures.count) of \(pairs.count) writes failed. First: \(failures[0])"
                }
            } catch {
                message = "Failed: \(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                status = message
                isApplying = false
            }
        }
    }
}

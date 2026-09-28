import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared Document Picker

/// `UIDocumentPickerViewController` wrapped for SwiftUI. Shared by the
/// AirLift views (pairing-file import, dialer zip, passcode theme, wallet
/// card). Handles the security-scoped resource dance around `onPick`.
struct AirLiftDocumentPicker: UIViewControllerRepresentable {
    var allowedTypes: [UTType]
    var onPick: (URL) -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: allowedTypes)
        vc.delegate = context.coordinator
        vc.allowsMultipleSelection = false
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController,
                                context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

// MARK: - Card Style (matches app views)

private struct AirLiftCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(18)
            .background(Color(uiColor: .tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct NumberedStep: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: Circle())
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - AirLiftPairingView

/// AirLift pairing: two flows depending on the iOS version.
///
/// - iOS 27+: the phone pairs with ITSELF. WorkSlop runs an RPPairing host,
///   advertises it over Bonjour, and shows a PIN. The user confirms the PIN
///   in Settings → Privacy & Security → Developer Mode. Writes then go
///   through the genuine on-device AirLift exploit (no Mac involved).
/// - iOS 26.6–26.7: manual pairing-file import (file generated on a PC via
///   iDevicePairing / iLoader). Writes on iOS 26.x go through the bad_query
///   fallback — that path is NOT AirLift and the UI says so.
struct AirLiftPairingView: View {
    @ObservedObject private var manager = AirLiftManager.shared
    @State private var showPicker = false
    @State private var tunnelUp: Bool?
    @State private var tunnelDetail: String = ""

    private var isIOS27: Bool { WorkSlopSupport.isIOS27() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("AirLift Pairing",
                              detail: WorkSlopSupport.deviceLabel())
                statusCard
                tunnelCard
                if isIOS27 {
                    hostFlowCard
                } else {
                    fileFlowCard
                }
                if let message = manager.statusMessage {
                    statusLine(message)
                }
                themesCard
                disclaimerCard
            }
            .padding(Theme.pagePadding)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("AirLift Pairing")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refreshTunnel)
        .sheet(isPresented: $showPicker) {
            AirLiftDocumentPicker(
                allowedTypes: [.data],
                onPick: { url in
                    manager.importPairingFile(from: url)
                    showPicker = false
                },
                onCancel: { showPicker = false }
            )
        }
    }

    // MARK: Status

    private var statusCard: some View {
        AirLiftCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: manager.isPaired ? "link.circle.fill" : "link.circle")
                        .font(.system(size: 34))
                        .foregroundStyle(manager.isPaired ? Theme.affirmative : .secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(manager.isPaired ? "Paired" : "Not paired")
                            .font(.headline)
                        Text(statusDetail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if manager.state == .pairing || manager.pairingStatus != "Not paired" {
                    Text(manager.pairingStatus)
                        .font(.footnote)
                        .foregroundStyle(manager.pairingStatus.hasPrefix("Failed")
                                         ? Theme.caution : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var statusDetail: String {
        if let name = manager.pairedDeviceName {
            return "This iPhone paired with itself (\(name))."
        }
        if let file = manager.importedFile {
            return "Pairing file: \(file.name)"
        }
        if manager.state == .pairing {
            return "Pairing in progress — follow the steps below."
        }
        return "AirLift writes are unavailable until you pair."
    }

    // MARK: Loopback tunnel

    /// The exploit reaches the phone's own services over a loopback tunnel
    /// (LocalDevVPN → 10.7.0.1, 127.0.0.1 fallback). This card reports the
    /// heuristic tunnel state — it is informational, and a down tunnel is
    /// shown as-is instead of being hidden.
    private var tunnelCard: some View {
        AirLiftCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: tunnelUp == true ? "checkmark.shield.fill" : "network.slash")
                        .foregroundStyle(tunnelUp == true ? Theme.affirmative : Theme.caution)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Loopback tunnel")
                            .font(.headline)
                        Text(tunnelUp == true
                             ? "A tunnel interface is up — the phone can reach its own services."
                             : "No tunnel interface detected. AirLift writes will fail until a loopback VPN app (e.g. LocalDevVPN) is active.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        refreshTunnel()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .font(.footnote)
                }
                if !tunnelDetail.isEmpty {
                    Text(tunnelDetail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                }
            }
        }
    }

    private func refreshTunnel() {
        // LocalDevVPN exposes the loopback tunnel on 10.7.0.1; the exploit
        // also tries 127.0.0.1. Report the 10.7.0.1 heuristic.
        let (vpn, _, detail) = NetworkStatus.summarize(deviceIP: "10.7.0.1")
        tunnelUp = vpn
        tunnelDetail = detail
    }

    // MARK: iOS 27+ — RPPairing host flow

    private var hostFlowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Pair This iPhone With Itself")
            VStack(alignment: .leading, spacing: 12) {
                NumberedStep(number: 1, text: "Tap Start Pairing. WorkSlop asks for Local Network permission and starts an on-device pairing host.")
                NumberedStep(number: 2, text: "Open Settings › Privacy & Security › Developer Mode and choose “Pair with WorkSlop”.")
                NumberedStep(number: 3, text: "Enter the PIN shown below when the phone asks for it.")
                NumberedStep(number: 4, text: "Return here — pairing completes automatically and the pairing file is saved in the app.")
            }
            if let pin = manager.pairingPIN {
                VStack(spacing: 6) {
                    Text("Enter this PIN in Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pin)
                        .font(.system(size: 44, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack(spacing: 12) {
                if manager.state == .pairing {
                    Button("Cancel", role: .cancel) { manager.cancelPairing() }
                        .buttonStyle(.bordered)
                } else if manager.isPaired {
                    Button("Unpair", role: .destructive) { manager.unpair() }
                        .buttonStyle(.bordered)
                } else {
                    ActionButton(title: "Start Pairing", systemImage: "qrcode") {
                        manager.startPairing()
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Already have a pairing file?")
                    .font(.footnote.weight(.semibold))
                Text("Drop an existing SideStore, iTunes, AltStore, or Jitterbug lockdown pairing file into WorkSlop's Documents folder, or import one here — it is adopted automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(manager.importedFile == nil ? "Import Pairing File" : "Replace Pairing File") {
                    showPicker = true
                }
                .buttonStyle(.bordered)
                .font(.footnote)
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: iOS 26.x — manual file import (bad_query fallback, NOT AirLift)

    private var fileFlowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Pairing File Import")
            Text("On iOS 26.x the on-device AirLift exploit is unavailable. Importing a pairing file unlocks the bad_query fallback writes — that path is not AirLift and is never labeled as such.")
                .font(.footnote)
                .foregroundStyle(Theme.caution)
            VStack(alignment: .leading, spacing: 12) {
                NumberedStep(number: 1, text: "On your PC or Mac, use iLoader or iDevicePairing to generate a pairing file for this iPhone.")
                NumberedStep(number: 2, text: "Transfer the pairing file to this iPhone — for example with AirDrop, an email to yourself, or the Files app.")
                NumberedStep(number: 3, text: "Tap Import Pairing File below and choose the transferred file.")
                NumberedStep(number: 4, text: "Once imported, fallback writes are unlocked on this iPhone.")
            }
            if let file = manager.importedFile {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading) {
                        Text(file.name).font(.subheadline.weight(.medium))
                        Text("\(file.size) bytes • imported \(file.importedAt, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Remove", role: .destructive) { manager.removeImportedFile() }
                        .buttonStyle(.bordered)
                        .font(.footnote)
                }
            }
            HStack(spacing: 12) {
                ActionButton(title: manager.importedFile == nil ? "Import Pairing File" : "Replace Pairing File",
                             systemImage: "square.and.arrow.down") {
                    showPicker = true
                }
                if manager.isPaired {
                    Button("Unpair", role: .destructive) { manager.unpair() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Themes & tools

    private var themesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Themes & Tools")
            themeRow(title: "Dialer Theme", detail: "Telephony UI assets (.zip), iOS 26.6–26.7",
                     icon: "phone.fill", tint: .green) {
                DialerThemeView()
            }
            Divider()
            themeRow(title: "Dialer Theme (AirLift)", detail: "iOS 27.0 RC / beta / stable only",
                     icon: "phone.badge.waveform.fill", tint: .blue) {
                AirLiftDialerThemeView()
            }
            Divider()
            themeRow(title: "Passcode Theme", detail: "Lock-screen passcode UI",
                     icon: "lock.fill", tint: .orange) {
                PasscodeThemeView()
            }
            Divider()
            themeRow(title: "Wallet Image", detail: "Apple Wallet card artwork",
                     icon: "wallet.pass.fill", tint: .purple) {
                WalletThemeView()
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func themeRow<Destination: View>(title: String, detail: String,
                                             icon: String, tint: Color,
                                             @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Misc

    private func statusLine(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(message.hasPrefix("Failed") || message.contains("failed")
                             ? Theme.caution : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Experimental — read first")
            Text("AirLift is experimental and not device-verified by us. On iOS 27+ it performs a genuine on-device sandbox escape (the AirTraffic Books-sync path from 0xjohnnydev/airlift, ported via AirCard-iOS): the phone talks to itself over a loopback tunnel. It requires Apple Books installed and opened at least once, a loopback VPN app active, and this iPhone paired with itself. Failures (pairing rejected, tunnel down, Books missing) are reported as-is. You bear all risk.")
                .font(.footnote)
                .foregroundStyle(Theme.caution)
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

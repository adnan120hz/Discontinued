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
/// - iOS 27: in-app pairing-code flow — Developer Mode steps, the generated
///   6-digit code shown big, then Confirm Pairing.
/// - iOS 26.6–26.7: pairing-file import — the file is generated on a PC via
///   iDevicePairing / iLoader, then imported here with the document picker.
struct AirLiftPairingView: View {
    @ObservedObject private var manager = AirLiftManager.shared
    @State private var showPicker = false

    private var isIOS27: Bool { WorkSlopSupport.isIOS27() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("AirLift Pairing",
                              detail: WorkSlopSupport.deviceLabel())
                statusCard
                if isIOS27 {
                    codeFlowCard
                } else {
                    fileFlowCard
                }
                if let message = manager.statusMessage {
                    statusLine(message)
                }
                themesCard
                infoCard
            }
            .padding(Theme.pagePadding)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("AirLift Pairing")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: Status

    private var statusCard: some View {
        AirLiftCard {
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
        }
    }

    private var statusDetail: String {
        if let record = manager.pairedRecord {
            return "\(record.deviceName) • code \(record.code)"
        }
        if let file = manager.importedFile {
            return "Pairing file: \(file.name)"
        }
        return "AirLift writes are unavailable until you pair."
    }

    // MARK: iOS 27 code flow

    private var codeFlowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Pairing Steps")
            VStack(alignment: .leading, spacing: 12) {
                NumberedStep(number: 1, text: "Tap Start Pairing below. WorkSlop generates a 6-digit pairing code.")
                NumberedStep(number: 2, text: "Open Settings > Privacy & Security > Developer Mode > select WorkSlop > Pairing File.")
                NumberedStep(number: 3, text: "Enter the pairing code shown in WorkSlop.")
                NumberedStep(number: 4, text: "Tap Confirm Pairing in WorkSlop. Pairing completes automatically.")
            }
            if let code = manager.pairingCode {
                Text(code)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            HStack(spacing: 12) {
                if manager.state == .pairing {
                    ActionButton(title: "Confirm Pairing", systemImage: "checkmark.circle.fill") {
                        manager.confirmPairing()
                    }
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
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: iOS 26 file flow

    private var fileFlowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Pairing File Import")
            VStack(alignment: .leading, spacing: 12) {
                NumberedStep(number: 1, text: "On your PC or Mac, use iLoader or iDevicePairing to generate a pairing file for this iPhone.")
                NumberedStep(number: 2, text: "Transfer the pairing file to this iPhone — for example with AirDrop, an email to yourself, or the Files app.")
                NumberedStep(number: 3, text: "Tap Import Pairing File below and choose the transferred file.")
                NumberedStep(number: 4, text: "Once imported, AirLift writes are unlocked on this iPhone. This import happens only on this screen.")
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
            ActionButton(title: manager.importedFile == nil ? "Import Pairing File" : "Replace Pairing File",
                         systemImage: "square.and.arrow.down") {
                showPicker = true
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Misc

    private func statusLine(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(message.hasPrefix("Failed") || message.contains("failed")
                             ? Theme.caution : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Info")
            Text("AirLift pairing enables file writes outside the app sandbox on iOS 26.6–27.x. The full Mac-hosted AirTraffic write path is still being device-tested; today writes go through the on-device bad_query primitive (see AirLiftFileWriter).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

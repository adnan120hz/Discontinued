import SwiftUI
import UniformTypeIdentifiers

// MARK: - WalletThemeView

/// "Wallet Image (AirLift)": attach a wallet card (`.pkpass`) first, then
/// pick a custom image and apply it via `AirLiftFileWriter`.
///
/// The Apply button stays disabled until a card is attached
/// (`AirLiftManager.requiresAttachedCard`) AND a local dev VPN is active
/// (`VPNCheck.isVPNActive()`), matching the passcode-theme gate: the
/// wallet-image flow writes through a local developer VPN tunnel.
struct WalletThemeView: View {
    @ObservedObject private var manager = AirLiftManager.shared
    @State private var showCardPicker = false
    @State private var showImagePicker = false
    @State private var imageName: String?
    @State private var imageData: Data?
    @State private var status: String?
    @State private var isApplying = false

    private static let pkpassType =
        UTType(filenameExtension: "pkpass") ?? .data

    // MARK: Destination (NOT device-verified)
    //
    /// Staging path for the custom wallet card image.
    ///
    /// NOT device-verified: the exact Wallet card-art location on
    /// iOS 26.6–27.x still needs on-device confirmation. The image is staged
    /// here so the flow (attach → pick → write) is reviewable end-to-end;
    /// narrow this path once the real asset location is confirmed on a test
    /// device.
    static let walletImageStagingPath = "/var/mobile/Library/Caches/WorkSlopWalletTheme"

    private var canApply: Bool {
        !manager.requiresAttachedCard && imageData != nil && vpnActive && !isApplying
    }

    /// Local dev-VPN state. Gated like the passcode-theme flow: the wallet
    /// image is written through a local developer VPN tunnel (utun).
    private var vpnActive: Bool { VPNCheck.isVPNActive() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Wallet Image (AirLift)")
                cardAttachCard
                vpnGateCard
                imagePickerCard
                applyCard
                if let status { statusLine(status) }
                infoCard
            }
            .padding(Theme.pagePadding)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Wallet Image")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCardPicker) {
            AirLiftDocumentPicker(
                allowedTypes: [Self.pkpassType],
                onPick: { url in
                    manager.attachWalletCard(from: url)
                    showCardPicker = false
                },
                onCancel: { showCardPicker = false }
            )
        }
        .sheet(isPresented: $showImagePicker) {
            AirLiftDocumentPicker(
                allowedTypes: [.image],
                onPick: { url in
                    importImage(from: url)
                    showImagePicker = false
                },
                onCancel: { showImagePicker = false }
            )
        }
    }

    // MARK: Cards

    private var cardAttachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Wallet Card", detail: "required")
            if let card = manager.walletCard {
                HStack {
                    Image(systemName: "creditcard.fill")
                        .foregroundStyle(Theme.affirmative)
                    VStack(alignment: .leading) {
                        Text(card.name).font(.subheadline.weight(.medium))
                        Text("Attached \(card.attachedAt, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Detach", role: .destructive) { manager.detachWalletCard() }
                        .buttonStyle(.bordered)
                        .font(.footnote)
                }
            } else {
                Text("Attach the wallet card (.pkpass) you want to theme. Apply stays disabled until a card is attached.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ActionButton(title: manager.walletCard == nil ? "Attach Wallet Card" : "Replace Wallet Card",
                         systemImage: "creditcard") {
                showCardPicker = true
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: VPN gate

    private var vpnGateCard: some View {
        Group {
            if vpnActive {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Theme.affirmative)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dev VPN active").font(.headline)
                        Text("A local dev VPN tunnel (utun) is up.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "network.slash")
                            .foregroundStyle(Theme.caution)
                            .font(.title2)
                        Text("Local dev VPN required — blocked").font(.headline)
                    }
                    Text("No local dev VPN detected. The wallet-image flow writes through a local developer VPN tunnel (utun interface). Connect your dev VPN profile, then try again. Nothing will be written until then.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var imagePickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Custom Image")
            if let imageName {
                HStack {
                    Image(systemName: "photo.fill").foregroundStyle(Theme.accent)
                    Text(imageName).font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    if let imageData {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(imageData.count),
                                                       countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Pick the replacement card image.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ActionButton(title: imageName == nil ? "Choose Image" : "Replace Image",
                         systemImage: "photo") {
                showImagePicker = true
            }
        }
        .padding(18)
        .background(Color(uiColor: .tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var applyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Apply")
            if manager.requiresAttachedCard {
                Text("Attach a wallet card above to enable Apply.")
                    .font(.footnote)
                    .foregroundStyle(Theme.caution)
            } else if !vpnActive {
                Text("Connect a local dev VPN profile to enable Apply.")
                    .font(.footnote)
                    .foregroundStyle(Theme.caution)
            } else {
                Text("Writes the custom image for \(manager.walletCard?.name ?? "the attached card") via AirLiftFileWriter.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ActionButton(title: "Apply Wallet Image",
                         systemImage: "wallet.pass.fill",
                         isBusy: isApplying,
                         disabled: !canApply) {
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
            Text("Card attachment is persisted across launches (the .pkpass is copied into the app sandbox). The VPN gate is enforced with VPNCheck.requireVPN()-style utun detection (no entitlements needed) and the flow blocks with an explanation when no local dev VPN is active. The custom image is written through AirLiftFileWriter; the exact Wallet card-art path is not device-verified yet (see code comment).")
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

    private func importImage(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            imageData = try Data(contentsOf: url)
            imageName = url.lastPathComponent
            status = nil
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func apply() {
        // Re-check the gate at apply time — the VPN can drop between
        // rendering and tapping, same as the passcode-theme flow.
        guard !manager.requiresAttachedCard, VPNCheck.isVPNActive() else {
            status = "Failed: gate no longer open. Re-check the attached card and the dev VPN."
            return
        }
        guard canApply,
              let data = imageData,
              let name = imageName
        else { return }
        isApplying = true
        status = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let dest = (Self.walletImageStagingPath as NSString)
                .appendingPathComponent(name)
            let message: String
            do {
                try AirLiftFileWriter.writeFile(data: data, to: dest)
                message = "Applied \(name). Respring to take effect."
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

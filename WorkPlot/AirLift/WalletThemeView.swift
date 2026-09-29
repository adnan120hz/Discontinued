import SwiftUI
import UniformTypeIdentifiers

// MARK: - WalletThemeView

/// "Wallet Image (AirLift)": attach a wallet card (`.pkpass`) first, then
/// pick a custom image and apply it via `AirLiftFileWriter` (genuine
/// on-device AirLift on iOS 26.x and 27.x — no bad_query fallback).
///
/// The Apply button stays disabled until a card is attached
/// (`AirLiftManager.requiresAttachedCard`). A missing local dev VPN is a
/// warning, not a blocker.
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

    // MARK: Destination (per AirCard-iOS)
    //
    /// Wallet card-art destination, per AirCard-iOS (Mak5er/AirCard-iOS,
    /// MIT, `AppViewModel.swift`): card skins are written into
    /// `/var/mobile/Library/Passes/Cards/<card-id>.pkpass`, where
    /// `<card-id>` is the card identifier (filename without extension).
    /// AirCard-iOS also invalidates `<card-id>.cache` / `<card-id>.pkcache`.
    static let walletCardsRootPath = "/var/mobile/Library/Passes/Cards"

    /// Destination directory for the attached card's artwork.
    static func cardArtDirectory(forCardNamed cardName: String) -> String {
        let cardID = (cardName as NSString).deletingPathExtension
        return (walletCardsRootPath as NSString)
            .appendingPathComponent("\(cardID).pkpass")
    }

    private var canApply: Bool {
        !manager.requiresAttachedCard && imageData != nil && manager.isPaired && !isApplying
    }

    /// Local dev-VPN state. A warning, not a blocker: the exploit tries
    /// 127.0.0.1:49152 first.
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

    // MARK: VPN gate (warning, not blocker)

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
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.caution)
                            .font(.title2)
                        Text("No local dev VPN — may still work").font(.headline)
                    }
                    Text("No local dev VPN detected. The exploit tries 127.0.0.1:49152 first and may still succeed — this is a warning, not a blocker.")
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
            } else if !manager.isPaired {
                Text("Pair in AirLift Pairing to enable Apply.")
                    .font(.footnote)
                    .foregroundStyle(Theme.caution)
            } else {
                Text("Writes the custom image into \(Self.cardArtDirectory(forCardNamed: manager.walletCard?.name ?? "card")) via the genuine AirLift exploit.")
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
            Text("Card attachment is persisted across launches (the .pkpass is copied into the app sandbox). Writes go through the genuine on-device AirLift exploit (iOS 26.x and 27.x). A missing local dev VPN is a warning, not a blocker. The custom image is written into /var/mobile/Library/Passes/Cards/<card-id>.pkpass (per AirCard-iOS).")
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
        // Re-check pairing at apply time — it can be revoked between
        // rendering and tapping. VPN is a warning, not a blocker.
        guard !manager.requiresAttachedCard, manager.isPaired else {
            status = "Failed: gate no longer open. Re-check the attached card and pairing."
            return
        }
        guard canApply,
              let data = imageData,
              let name = imageName,
              let card = manager.walletCard
        else { return }
        isApplying = true
        status = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let dest = (Self.cardArtDirectory(forCardNamed: card.name) as NSString)
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

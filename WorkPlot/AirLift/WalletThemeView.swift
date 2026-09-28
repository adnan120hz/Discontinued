import SwiftUI
import UniformTypeIdentifiers

// MARK: - WalletThemeView

/// "Wallet Image (AirLift)": attach a wallet card (`.pkpass`) first, then
/// pick a custom image and apply it via `AirLiftFileWriter`.
///
/// The Apply button stays disabled until a card is attached
/// (`AirLiftManager.requiresAttachedCard`).
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
        !manager.requiresAttachedCard && imageData != nil && !isApplying
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader("Wallet Image (AirLift)")
                cardAttachCard
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
            Text("Card attachment is persisted across launches (the .pkpass is copied into the app sandbox). The custom image is written through AirLiftFileWriter; the exact Wallet card-art path is not device-verified yet (see code comment).")
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

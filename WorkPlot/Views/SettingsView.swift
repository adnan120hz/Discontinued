import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// WorkSlop preferences: this device, appearance, the PosterBoard
/// container connection, and MobileGestalt backup import/export.
struct SettingsView: View {
    @EnvironmentObject private var store: GestaltStore
    @AppStorage("pbHash") private var pbHash = ""
    @AppStorage("accentColor") private var accentColor = AppAccent.blue.rawValue
    @AppStorage("customColor") private var customColor: Double = 0
    @AppStorage("useCustomColor") private var useCustomColor = false
    @AppStorage("appearanceScheme") private var appearanceScheme = 0
    @State private var detectingHash = false
    @State private var showHashError = false
    @State private var hashErrorMessage = ""
    @State private var showBackupImporter = false
    @State private var pendingImportData: Data?
    @State private var showReplaceBackupConfirm = false
    @State private var showBackupError = false
    @State private var backupErrorMessage = ""
    @State private var showBackupImportedToast = false

    private var os: DeviceCompatibility.OSInfo { DeviceCompatibility.currentInfo }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                deviceCard
                appearance
                connection
                backup
                supportInfo
            }
            .padding(Theme.pagePadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.page)
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Could not detect PosterBoard hash", isPresented: $showHashError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(hashErrorMessage)
        }
        .fileImporter(isPresented: $showBackupImporter, allowedContentTypes: [.propertyList], onCompletion: handleBackupImport)
        .confirmationDialog("Replace existing backup?", isPresented: $showReplaceBackupConfirm, titleVisibility: .visible) {
            Button("Replace", role: .destructive, action: commitPendingImport)
            Button("Cancel", role: .cancel) { pendingImportData = nil }
        } message: {
            Text("This overwrites your pristine recovery point with the imported file. This can't be undone.")
        }
        .alert("Could not import backup", isPresented: $showBackupError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupErrorMessage)
        }
        .toast(isPresented: $showBackupImportedToast, message: "Backup imported")
    }

    // MARK: - Shared row styles

    private func iconTile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.wsBlue)
            .frame(width: 32, height: 32)
            .background(Theme.tintWash, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// A labeled setting row: icon + title on top, control indented below.
    private func settingRow<Control: View>(icon: String, title: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                iconTile(icon)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            control()
                .padding(.leading, 44)
        }
        .padding(.vertical, 12)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            iconTile(icon)
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 10)
    }

    // MARK: - This device

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("This device")
            VStack(spacing: 0) {
                infoRow(icon: "iphone", title: "Model", value: WorkSlopSupport.deviceLabel())
                Divider().padding(.leading, 44)
                infoRow(icon: "apple.logo", title: "iOS version",
                        value: "\(os.version.majorVersion).\(os.version.minorVersion).\(os.version.patchVersion)")
                Divider().padding(.leading, 44)
                infoRow(icon: "number", title: "Build", value: os.build ?? "Unknown")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .wsCard(cornerRadius: 18)
        }
    }

    // MARK: - Appearance

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Appearance")
            VStack(spacing: 0) {
                settingRow(icon: "paintpalette.fill", title: "Accent color") {
                    HStack(spacing: 12) {
                        ForEach(AppAccent.allCases) { accent in
                            Button {
                                useCustomColor = false
                                accentColor = accent.rawValue
                            } label: {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if !useCustomColor && accentColor == accent.rawValue {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.name)
                        }
                    }
                }
                Divider().padding(.leading, 44)
                settingRow(icon: "eyedropper.halffull", title: "Custom color") {
                    HStack(spacing: 14) {
                        ColorPicker("", selection: Binding(
                            get: {
                                Color(hue: customColor, saturation: 0.75, brightness: 0.9)
                            },
                            set: { newColor in
                                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                                UIColor(newColor).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                                customColor = h
                                useCustomColor = true
                            }
                        ))
                        .labelsHidden()
                        Circle()
                            .fill(Color(hue: customColor, saturation: 0.75, brightness: 0.9))
                            .frame(width: 30, height: 30)
                            .overlay {
                                if useCustomColor {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        if useCustomColor {
                            Button("Reset") {
                                useCustomColor = false
                                accentColor = AppAccent.blue.rawValue
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.wsBlue)
                        }
                    }
                }
                Divider().padding(.leading, 44)
                settingRow(icon: "circle.lefthalf.filled", title: "Appearance mode") {
                    Picker("Mode", selection: $appearanceScheme) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .wsCard(cornerRadius: 18)
        }
    }

    // MARK: - PosterBoard connection

    private var connection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("PosterBoard container")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    iconTile("link")
                    Text("Container UUID")
                        .font(.subheadline.weight(.semibold))
                }
                TextField("Container UUID", text: $pbHash)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .padding(.leading, 44)
                HStack(spacing: 10) {
                    Button("Detect on device", systemImage: "scope", action: detectPosterBoardHash)
                        .wsAction()
                        .disabled(detectingHash)
                    if detectingHash { ProgressView() }
                    if !pbHash.isEmpty {
                        Button("Clear", role: .destructive) { pbHash = "" }
                            .wsAction()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.leading, 44)
                if !BadQuery.isAvailable {
                    Text("Detection is unavailable on this iOS version.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 44)
                }
            }
            .padding(16)
            .wsCard(cornerRadius: 18)
        }
    }

    // MARK: - Backup

    private var backup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Backup")
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: store.backup.hasBackup ? "checkmark.shield.fill" : "shield")
                        .foregroundStyle(store.backup.hasBackup ? Theme.affirmative : Theme.wsBlue)
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background(Theme.tintWash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.backup.hasBackup ? "Pristine backup available" : "Backup will be created on first apply")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        if let info = store.backup.info {
                            Text("\(info.createdAt.formatted(date: .abbreviated, time: .shortened))  |  \(ByteCountFormatter.string(fromByteCount: Int64(info.byteCount), countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("This is the recovery point for all tweak changes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if store.backup.hasBackup {
                        ShareLink(item: store.backup.fileURL) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .wsAction()
                    }
                    Button { showBackupImporter = true } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .wsAction()
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(16)
            .wsCard(cornerRadius: 18)
        }
    }

    // MARK: - Supported iOS

    private var supportInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Supported iOS")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    iconTile("info.circle")
                    Text("Compatibility")
                        .font(.subheadline.weight(.semibold))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Full features need iOS 27.")
                        .font(.subheadline.weight(.medium))
                    Text("Reads work on any iOS 27 build. Writes depend on the bad_query exploit, which is verified against iOS 27 developer betas 1 to 4.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 44)
            }
            .padding(16)
            .wsCard(cornerRadius: 18)
        }
    }

    // MARK: - Helpers

    private func detectPosterBoardHash() {
        guard !detectingHash else { return }
        detectingHash = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let hash = try BadQuery.findPosterBoardHash().trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    pbHash = hash
                    detectingHash = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } catch {
                DispatchQueue.main.async {
                    detectingHash = false
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    hashErrorMessage = error.localizedDescription
                    showHashError = true
                }
            }
        }
    }

    private func handleBackupImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if store.backup.hasBackup {
                    pendingImportData = data
                    showReplaceBackupConfirm = true
                } else {
                    try store.backup.importBackup(from: data)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showBackupImportedToast = true
                }
            } catch {
                backupErrorMessage = error.localizedDescription
                showBackupError = true
            }
        case .failure(let error):
            backupErrorMessage = error.localizedDescription
            showBackupError = true
        }
    }

    private func commitPendingImport() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            try store.backup.importBackup(from: data)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showBackupImportedToast = true
        } catch {
            backupErrorMessage = error.localizedDescription
            showBackupError = true
        }
    }
}

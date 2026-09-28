import SwiftUI

/// "User Data Backup" screen — the iOS 27 user-data backup task
/// (photos/videos + settings).
///
/// This is a DISTINCT backup mode in the Backup feature, separate from:
///   - the MobileGestalt stock snapshot (the pristine MobileGestalt plist), and
///   - the Liquid Glass Backup (liquid-glass preference files only,
///     owned by the Liquid Glass menu).
///
/// Reached from Settings > Tools > User Data Backup. iOS 27 only.
struct UserDataBackupView: View {
    @StateObject private var model = UserDataBackupModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                explainerCard
                statusCard
                actionsCard
            }
            .padding(Theme.pagePadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.page)
        .navigationTitle("User Data Backup")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.refresh() }
        .overlay {
            if model.isBusy {
                ProgressOverlay(message: model.busyTask == .backingUp ? "Backing up…" : "Restoring…")
            }
        }
    }

    // MARK: - Explainer

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("What this backs up")
            Text("Snapshots your photos and videos (newest first) plus your settings files into this app. It is a separate backup task — not the MobileGestalt stock snapshot and not the Liquid Glass Backup. Large camera rolls are capped (300 files / 1.5 GB); anything beyond the cap is listed as skipped, never silently dropped.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !model.isIOS27 {
                Label("The User Data Backup needs iOS 27.", systemImage: "exclamationmark.triangle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.caution)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .wsCard(cornerRadius: 18)
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Backup status")
            HStack(spacing: 14) {
                Image(systemName: model.backupInfo != nil ? "checkmark.shield.fill" : "shield")
                    .foregroundStyle(model.backupInfo != nil ? Theme.affirmative : Theme.wsBlue)
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Theme.wsBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    if let info = model.backupInfo {
                        Text("User Data Backup available")
                            .font(.subheadline.weight(.semibold))
                        let size = ByteCountFormatter.string(fromByteCount: info.totalBytes, countStyle: .file)
                        Text("\(info.createdAt.formatted(date: .abbreviated, time: .shortened))  |  \(info.fileCount) files  |  \(size)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if info.skippedCount > 0 {
                            Text("\(info.skippedCount) files skipped (size caps)")
                                .font(.caption)
                                .foregroundStyle(Theme.caution)
                        }
                    } else {
                        Text("No User Data Backup yet")
                            .font(.subheadline.weight(.semibold))
                        Text("Press Backup to snapshot your photos, videos and settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .wsCard(cornerRadius: 18)
        }
    }

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Backup actions")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    ActionButton(title: "Backup",
                                 systemImage: "externaldrive.fill",
                                 isBusy: model.busyTask == .backingUp,
                                 disabled: !model.isIOS27) {
                        model.createBackup()
                    }
                    ActionButton(title: "Restore",
                                 systemImage: "arrow.uturn.backward",
                                 isBusy: model.busyTask == .restoring,
                                 disabled: !model.isIOS27 || model.backupInfo == nil) {
                        model.restoreBackup()
                    }
                }
                Text("Backup snapshots your current photos, videos and settings. Restore writes that snapshot back. A full reboot is required afterwards.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if model.backupInfo != nil {
                Button("Delete this backup", role: .destructive, action: model.deleteBackup)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .disabled(model.isBusy)
            }
            if let status = model.statusMessage {
                Label(status, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.affirmative)
            }
            if !model.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.warnings.indices, id: \.self) { index in
                        Label(model.warnings[index], systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.caution)
                    }
                }
            }
        }
        .padding(16)
        .wsCard(cornerRadius: 18)
    }
}

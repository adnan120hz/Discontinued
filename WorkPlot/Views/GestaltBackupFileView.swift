import SwiftUI
import UniformTypeIdentifiers

/// "Mobile Gestalt Backup File" screen — create, import, and restore
/// MobileGestalt backup (.plist) files.
///
/// Reached from System Hub > Tools > Mobile Gestalt Backup File.
/// Storage goes through the existing `GestaltBackupStore` (Documents/
/// "MobileGestalt Backups") and restore goes through the existing
/// `WPExploitManager.restore(_:)` path — nothing is reimplemented here.
///
/// The ⋯ button in the top-right opens the menu for the two backup tasks:
/// "Create Backup" (reads the live MobileGestalt cache and snapshots it)
/// and "Import Mobile Gestalt" (.plist files only).
struct GestaltBackupFileView: View {
    @ObservedObject private var manager = WPExploitManager.shared
    @State private var showImporter = false
    @State private var isBusy = false
    @State private var feedback: Feedback? = nil
    @State private var backupToRestore: GestaltBackup? = nil
    @State private var backupToDelete: GestaltBackup? = nil

    private struct Feedback {
        let text: String
        let isError: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                explainerCard
                backupsCard
                if let feedback {
                    feedbackRow(feedback)
                }
            }
            .padding(Theme.pagePadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.page)
        .navigationTitle("Mobile Gestalt Backup File")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        createBackup()
                    } label: {
                        Label("Create Backup", systemImage: "plus")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Mobile Gestalt", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Backup options")
                }
            }
        }
        .onAppear { manager.refreshBackups() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.propertyList],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importPlist(from: url) }
            case .failure(let error):
                setFeedback("Could not pick a file: \(error.localizedDescription)", isError: true)
            }
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(
                get: { backupToRestore != nil },
                set: { if !$0 { backupToRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                if let backup = backupToRestore { restore(backup) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces the current MobileGestalt cache with the backup. A full reboot is required afterwards.")
        }
        .confirmationDialog(
            "Delete this backup?",
            isPresented: Binding(
                get: { backupToDelete != nil },
                set: { if !$0 { backupToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let backup = backupToDelete { deleteBackup(backup) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The backup file is removed from this device. This cannot be undone.")
        }
        .overlay {
            if isBusy {
                ProgressOverlay(message: "Working…")
            }
        }
    }

    // MARK: - Explainer

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("What this is")
            Text("Snapshots of the MobileGestalt cache, stored as .plist files on this device. Create a backup before applying tweaks, import a .plist backup from another device, or restore a backup to roll back. Use the ⋯ button at the top right to create or import.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .wsCard(cornerRadius: 18)
    }

    // MARK: - Backups list

    private var backupsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Backups")
            if manager.backups.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No backups yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Use the ⋯ button to create a MobileGestalt backup or import a .plist file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(manager.backups) { backup in
                        backupRow(backup)
                        if backup != manager.backups.last {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
            }
        }
        .padding(16)
        .wsCard(cornerRadius: 18)
    }

    private func backupRow(_ backup: GestaltBackup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.badge.clock")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(backup.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(backup.createdAt.formatted(date: .abbreviated, time: .shortened))  |  \(ByteCountFormatter.string(fromByteCount: backup.byteCount, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Restore") { backupToRestore = backup }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .disabled(isBusy)
            Button(role: .destructive) { backupToDelete = backup } label: {
                Image(systemName: "trash")
            }
            .font(.footnote)
            .buttonStyle(.bordered)
            .disabled(isBusy)
        }
        .padding(.vertical, 8)
    }

    private func feedbackRow(_ feedback: Feedback) -> some View {
        Label(feedback.text, systemImage: feedback.isError ? "exclamationmark.triangle" : "checkmark.circle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(feedback.isError ? Theme.caution : Theme.affirmative)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Create / import / restore

    private func createBackup() {
        isBusy = true
        defer { isBusy = false }
        do {
            guard let data = manager.readGestaltData() else {
                throw NSError(
                    domain: "GestaltBackupFileView", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not read the MobileGestalt cache. Sandbox access may be unavailable."]
                )
            }
            _ = try GestaltBackupStore.create(from: data)
            manager.refreshBackups()
            setFeedback("Backup created.", isError: false)
        } catch {
            setFeedback("Backup failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func importPlist(from url: URL) {
        // The picker is already restricted to .plist, but validate the
        // extension explicitly — the user must never import another format.
        guard url.pathExtension.lowercased() == "plist" else {
            setFeedback("Only .plist files are supported.", isError: true)
            return
        }
        isBusy = true
        defer { isBusy = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            guard (try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]) != nil else {
                throw NSError(
                    domain: "GestaltBackupFileView", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "This file is not a valid MobileGestalt backup."]
                )
            }
            _ = try GestaltBackupStore.create(from: data)
            manager.refreshBackups()
            setFeedback("Imported. Tap Restore on the backup to apply it.", isError: false)
        } catch {
            setFeedback("Import failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func restore(_ backup: GestaltBackup) {
        isBusy = true
        defer { isBusy = false }
        if manager.restore(backup) {
            setFeedback("Restored. A full reboot is required to complete the restore.", isError: false)
        } else {
            setFeedback("Restore failed: \(manager.statusText.isEmpty ? "unknown error" : manager.statusText)", isError: true)
        }
    }

    private func deleteBackup(_ backup: GestaltBackup) {
        do {
            try GestaltBackupStore.delete(backup)
            manager.refreshBackups()
            setFeedback("Backup deleted.", isError: false)
        } catch {
            setFeedback("Delete failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func setFeedback(_ text: String, isError: Bool) {
        feedback = Feedback(text: text, isError: isError)
    }
}

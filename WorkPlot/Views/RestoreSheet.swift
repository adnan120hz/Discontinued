import SwiftUI

struct RestoreSheet: View {
    @EnvironmentObject private var store: GestaltStore
    @Environment(\.dismiss) private var dismiss
    @State private var done = false
    @State private var showConfirm = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: done ? "checkmark" : "arrow.counterclockwise")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(done ? Theme.affirmative : Theme.wsBlue)
                        .frame(width: 52, height: 52)
                        .background(Theme.tintWash, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(done ? "Original file restored" : "Return to baseline")
                            .font(.title3.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(done ? "Recovery" : "Recovery point")
                            .font(.caption.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                Text(done ? "Restart your device to complete the recovery." : "Replace the edited MobileGestalt cache with the pristine file captured before your first change.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let info = store.backup.info {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MOBILEGESTALT STOCK SNAPSHOT")
                            .font(.caption.weight(.bold))
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        Text(info.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.body.weight(.medium))
                        Text(ByteCountFormatter.string(fromByteCount: Int64(info.byteCount), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .wsCard(cornerRadius: 16)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !done && errorMessage == nil {
                    ActionButton(title: "Restore recovery point", systemImage: "arrow.counterclockwise", isBusy: isRestoring) {
                        showConfirm = true
                    }
                }
            }
            .padding(Theme.pagePadding)
            .background(Theme.page)
            .navigationTitle("Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .confirmationDialog("Restore recovery point", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Restore", role: .destructive, action: runRestore)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces the current MobileGestalt cache with your pristine backup. Keep the device powered until it finishes.")
        }
    }

    private func runRestore() {
        errorMessage = nil
        isRestoring = true
        Task {
            do {
                _ = try await store.restore()
                isRestoring = false
                done = true
            } catch {
                isRestoring = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

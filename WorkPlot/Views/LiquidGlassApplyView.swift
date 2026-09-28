import SwiftUI

/// Dedicated Disable-Liquid-Glass apply flow with the version-appropriate
/// backup story:
///
/// - iOS 27: full backup → modify → full restore (GoldenNugget-style).
///   Backup (blue) snapshots the target preference files first; Apply
///   (blue) stays disabled until that snapshot exists.
/// - iOS 26: partial-restore (bookrestore-style). The Backup button is
///   grayed off — only Apply is active — and the flow captures pre-images
///   automatically so the last apply can be undone.
///
/// Reached from the Tweaks tab's Liquid Glass category.
struct LiquidGlassApplyView: View {
    @EnvironmentObject private var store: GestaltStore
    @StateObject private var model = LiquidGlassApplyModel()

    private var lgTweaks: [Tweak] {
        store.tweaks.filter { $0.category == .liquidGlass }
    }

    private var isIOS27Flow: Bool { model.flow == .fullBackup }
    private var backupMissing: Bool { isIOS27Flow && model.backupInfo == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                introCard
                tweaksCard
                flowCard
            }
            .padding(Theme.pagePadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.page)
        .navigationTitle("Disable Liquid Glass")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.refresh() }
        .overlay {
            if model.isBusy {
                ProgressOverlay(message: isIOS27Flow ? "Working…" : "Applying…")
            }
        }
    }

    // MARK: - Intro

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("What this does")
            Text("Writes the liquid-glass disable keys into .GlobalPreferences.plist and the SpringBoard preferences. A respring is required afterwards. Toggling a tweak off removes its key again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .wsCard(cornerRadius: 18)
    }

    // MARK: - Tweaks

    private var tweaksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Liquid Glass tweaks", detail: "\(lgTweaks.count) available")
            if lgTweaks.isEmpty {
                Text("No Liquid Glass tweaks are offered on this iOS version.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(lgTweaks.indices, id: \.self) { index in
                        let tweak = lgTweaks[index]
                        HStack(spacing: 12) {
                            Image(systemName: tweak.symbol)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Theme.wsBlue.opacity(0.55),
                                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tweak.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(tweak.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Toggle("", isOn: store.binding(for: tweak.id))
                                .labelsHidden()
                                .tint(Theme.wsBlue)
                        }
                        .padding(.vertical, 9)
                        if index < lgTweaks.count - 1 {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
        .wsCard(cornerRadius: 18)
    }

    // MARK: - Apply flow

    private var flowCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Apply flow")
            statusRow
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    backupButton
                    applyButton
                }
                // The note sits directly under Apply.
                Text(model.flow.applyNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            restoreButton
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
            respringRow
        }
        .padding(16)
        .wsCard(cornerRadius: 18)
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: model.flow == .fullBackup ? "externaldrive.fill" : "arrow.triangle.2.circlepath")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(model.flow == .fullBackup ? "Full backup flow (iOS 27)"
                     : model.flow == .partialRestore ? "Partial-restore flow (iOS 26)"
                     : "Unsupported iOS version")
                    .font(.subheadline.weight(.semibold))
                Text(backupStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var backupStatusText: String {
        switch model.flow {
        case .fullBackup:
            if let info = model.backupInfo {
                let size = ByteCountFormatter.string(fromByteCount: Int64(info.totalBytes), countStyle: .file)
                return "Backup from \(info.createdAt.formatted(date: .abbreviated, time: .shortened)) • \(size)"
            }
            return "No backup yet — press Backup first."
        case .partialRestore:
            return "Pre-apply snapshots are captured automatically."
        case .unsupported:
            return "Needs iOS 26 or 27."
        }
    }

    // MARK: Buttons

    /// Blue on iOS 27; grayed off (disabled) on iOS 26, where the
    /// partial-restore flow applies without a backup step.
    private var backupButton: some View {
        ActionButton(title: "Backup",
                     systemImage: "externaldrive.fill",
                     isBusy: model.busyTask == .backingUp,
                     disabled: model.flow != .fullBackup) {
            model.createBackup()
        }
        .opacity(model.flow == .fullBackup ? 1 : 0.45)
    }

    /// Blue on both flows. On iOS 27 it stays disabled until the full
    /// backup exists.
    private var applyButton: some View {
        ActionButton(title: "Apply",
                     systemImage: "bolt.fill",
                     isBusy: model.busyTask == .applying,
                     disabled: backupMissing || model.flow == .unsupported) {
            model.apply(tweaks: store.tweaks)
        }
    }

    private var restoreButton: some View {
        secondaryButton(
            title: model.flow == .partialRestore ? "Undo last apply" : "Restore full backup",
            systemImage: "arrow.uturn.backward",
            tint: Theme.destructive,
            disabled: restoreDisabled,
            action: { model.restore() }
        )
        .accessibilityHint(model.flow == .partialRestore
                           ? "Revert the last partial-restore apply"
                           : "Restore the pristine liquid-glass backup")
    }

    private var restoreDisabled: Bool {
        switch model.flow {
        case .fullBackup: return model.backupInfo == nil
        case .partialRestore: return !model.canUndoPartial
        case .unsupported: return true
        }
    }

    private var respringRow: some View {
        secondaryButton(
            title: "Respring",
            systemImage: "arrow.clockwise",
            tint: Theme.wsBlue,
            disabled: false,
            action: { RespringHelper.shared.trigger() }
        )
        .accessibilityHint("Restart SpringBoard so the changes take effect")
    }

    /// Full-width tinted outline button used for the secondary actions.
    private func secondaryButton(title: String,
                                 systemImage: String,
                                 tint: Color,
                                 disabled: Bool,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

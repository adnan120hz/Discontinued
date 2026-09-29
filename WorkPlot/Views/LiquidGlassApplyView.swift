import SwiftUI

/// Liquid Glass tweaks menu: the full GoldenNugget-mobile liquid-glass
/// tweak set (toggles writing into .GlobalPreferences.plist and the
/// SpringBoard preferences) with the version-appropriate backup story:
///
/// - iOS 27: full backup → modify → full restore (GoldenNugget-style).
///   Backup (blue) snapshots the target preference files first; Apply
///   (blue) stays disabled until that snapshot exists.
/// - iOS 26: partial-restore (bookrestore-style). The Backup button is
///   grayed off — only Apply is active — and the flow captures pre-images
///   automatically so the last apply can be undone.
///
/// The Backup button here is its own backup task — a "Liquid Glass Backup"
/// of the liquid-glass preference files only. It is NOT the MobileGestalt
/// stock snapshot; that is a separate backup mode in the Backup feature.
///
/// Every tweak in this menu needs a FULL REBOOT to take effect — a
/// respring is not enough. Only PosterBoard tweaks apply with just a
/// respring.
struct LiquidGlassApplyView: View {
    @EnvironmentObject private var store: GestaltStore
    @StateObject private var model = LiquidGlassApplyModel()

    private var lgTweaks: [Tweak] {
        store.tweaks.filter { $0.category == .liquidGlass }
    }

    private var isIOS27Flow: Bool { model.flow == .fullBackup }
    private var backupMissing: Bool {
        isIOS27Flow && model.backupInfo == nil && model.backupMode != .fullDevice
    }

    // MARK: - Full backup (iOS 27, GoldenNugget-style)

    /// Prerequisites + backup-mode status for the full-device backup path.
    /// Honest copy: when the on-device AirLift channel is not ready, the UI
    /// says Backup will take a preference snapshot instead — never a full
    /// device backup it cannot do. Nothing here claims an automatic
    /// restore-on-reboot: the restore is the step that applies the tweaks,
    /// and the reboot afterwards is manual.
    private var fullBackupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Full Backup")
            switch model.backupMode {
            case .fullDevice:
                modeStatusRow(icon: "externaldrive.fill",
                              title: "Full device backup",
                              detail: "Pulled from the device over the AirLift channel, " +
                                      "GoldenNugget-style. The working backup is temporary — " +
                                      "it is wiped when the next backup runs, so restore " +
                                      "before backing up again.")
            case .preferenceSnapshot:
                modeStatusRow(icon: "doc.fill",
                              title: "Preference snapshot — not a full device backup",
                              detail: "Covers the liquid-glass preference files only. " +
                                      "The full-device path needs the on-device AirLift " +
                                      "channel, which is not ready yet.")
            case nil:
                prerequisitesList
            }
        }
        .padding(16)
        .wsCard(cornerRadius: 18)
    }

    private var prerequisitesList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Before you press Backup, make sure:")
                .font(.subheadline.weight(.semibold))
            prerequisiteRow(icon: "wifi",
                            text: "The device is on Wi-Fi.",
                            live: nil)
            prerequisiteRow(icon: "cable.connector",
                            text: "The loopback tunnel / VPN app is running.",
                            live: model.tunnelUp)
            prerequisiteRow(icon: "link",
                            text: "AirLift is paired (see the AirLift tab).",
                            live: model.airliftPaired)
            prerequisiteRow(icon: "eye.slash",
                            text: "Find My is turned off.",
                            live: nil)
            prerequisiteRow(icon: "book.closed",
                            text: "Apple Books is installed (where applicable).",
                            live: nil)
            if !model.channelReady {
                Text("The on-device AirLift channel is not ready yet" +
                     (model.channelNote.map { " (\($0))" } ?? "") +
                     " — Backup will take a preference snapshot instead: " +
                     "the liquid-glass preference files only, not a full device backup.")
                    .font(.footnote)
                    .foregroundStyle(Theme.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Backup captures the current state — press it before applying tweaks.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func prerequisiteRow(icon: String, text: String, live: Bool?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: prerequisiteIcon(live))
                .font(.body.weight(.semibold))
                .foregroundStyle(prerequisiteColor(live))
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func prerequisiteIcon(_ live: Bool?) -> String {
        switch live {
        case .some(true): return "checkmark.circle.fill"
        case .some(false): return "xmark.circle.fill"
        case nil: return "circle"
        }
    }

    private func prerequisiteColor(_ live: Bool?) -> Color {
        switch live {
        case .some(true): return Theme.affirmative
        case .some(false): return Theme.destructive
        case nil: return .secondary
        }
    }

    private func modeStatusRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Media safety copy

    /// AFC photo/video safety copy (iOS 27 full-backup flow). Pure copy —
    /// the device originals are never deleted by this backup.
    private var mediaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Photo & video safety copy")
            Text("Copies DCIM and PhotoStreamsData over AFC into this app's storage. " +
                 "Each file is verified before anything is removed — and this backup " +
                 "never removes the device originals.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.wsBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Media store")
                        .font(.subheadline.weight(.semibold))
                    Text(model.mediaInfo?.summary ?? "No media stored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if model.mediaBusy, let progress = model.taskProgress {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(progress)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 12) {
                ActionButton(title: "Pull media",
                             systemImage: "arrow.down.to.line",
                             isBusy: model.mediaBusy,
                             disabled: !model.channelReady) {
                    model.pullMedia()
                }
                ActionButton(title: "Push back",
                             systemImage: "arrow.up.to.line",
                             isBusy: false,
                             disabled: model.mediaInfo == nil || model.mediaBusy || !model.channelReady) {
                    model.pushMediaBack()
                }
            }
            .opacity(model.channelReady ? 1 : 0.45)
            secondaryButton(title: "Empty store",
                            systemImage: "trash",
                            tint: Theme.destructive,
                            disabled: model.mediaInfo == nil || model.mediaBusy,
                            action: { model.emptyMediaStore() })
            if !model.channelReady {
                Text("Media actions need the device channel — pair AirLift and bring the tunnel up first.")
                    .font(.footnote)
                    .foregroundStyle(Theme.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .wsCard(cornerRadius: 18)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                disclaimerCard
                introCard
                tweaksCard
                if isIOS27Flow {
                    fullBackupCard
                }
                flowCard
                if isIOS27Flow {
                    mediaCard
                }
            }
            .padding(Theme.pagePadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.page)
        .navigationTitle("Liquid Glass Tweaks iOS 26.2+")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.refresh() }
        .overlay {
            if model.isBusy {
                ProgressOverlay(message: model.taskProgress ?? (isIOS27Flow ? "Working…" : "Applying…"))
            }
        }
    }

    // MARK: - Disclaimer

    /// Prominent experimental-feature disclaimer. English, as spec'd.
    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.destructive)
            VStack(alignment: .leading, spacing: 6) {
                Text("Experimental — use at your own risk")
                    .font(.headline)
                Text("Liquid Glass tweaks are experimental. They were made as optimal and safe as possible, but errors can still happen — any damage or data loss that results is entirely your own responsibility. Back up your data before applying anything here.\n\nWant iOS 18 UI style? Use the Disable Liquid Glass tweak in Other Exploit (DarkSword) — only for iOS 26.0.1/26.1.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.destructive.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    // MARK: - Intro

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("What this does")
            Text("Writes the liquid-glass tweak keys into .GlobalPreferences.plist and the SpringBoard preferences. A full reboot is required afterwards — a respring is not enough. Toggling a tweak off removes its key again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .wsCard(cornerRadius: 18)
    }

    // MARK: - Tweaks

    private var tweaksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Liquid Glass tweaks iOS 26.2+ (NO iOS 18 UI)", detail: "\(lgTweaks.count) available")
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
            SectionHeader("Liquid Glass Backup & Apply")
            Text("This Backup snapshots the liquid-glass preference files only. It is a separate backup task — not the MobileGestalt stock snapshot.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            statusRow
            if model.isBusy, let progress = model.taskProgress {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(progress)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
            rebootRow
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
            if model.backupMode == .fullDevice {
                return "Full device backup ready — Apply will inject and restore."
            }
            if model.backupMode == .preferenceSnapshot {
                return "Preference snapshot ready — not a full device backup."
            }
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
            title: restoreTitle,
            systemImage: "arrow.uturn.backward",
            tint: Theme.destructive,
            disabled: restoreDisabled,
            action: { model.restore() }
        )
        .accessibilityHint(restoreHint)
    }

    private var restoreTitle: String {
        switch model.flow {
        case .fullBackup:
            return model.backupMode == .fullDevice ? "Restore pristine files" : "Restore full backup"
        case .partialRestore:
            return "Undo last apply"
        case .unsupported:
            return "Restore"
        }
    }

    private var restoreHint: String {
        switch model.flow {
        case .fullBackup:
            return model.backupMode == .fullDevice
                ? "Restore the pristine liquid-glass files stashed at backup time"
                : "Restore the pristine liquid-glass backup"
        case .partialRestore:
            return "Revert the last partial-restore apply"
        case .unsupported:
            return "Restore"
        }
    }

    private var restoreDisabled: Bool {
        switch model.flow {
        case .fullBackup:
            return model.backupInfo == nil && model.backupMode != .fullDevice
        case .partialRestore: return !model.canUndoPartial
        case .unsupported: return true
        }
    }

    /// Liquid Glass tweaks need a FULL REBOOT to take effect — a respring
    /// is not enough. (Only PosterBoard tweaks apply with just a respring.)
    /// This app cannot reboot the device for you: power it off and back on
    /// (or force-restart it) after applying.
    private var rebootRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "power")
                .font(.title3)
                .foregroundStyle(Theme.wsBlue)
                .frame(width: 40, height: 40)
                .background(Theme.wsBlue.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Full reboot required")
                    .font(.subheadline.weight(.semibold))
                Text("These changes only take effect after a full device reboot. A respring is not enough.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
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

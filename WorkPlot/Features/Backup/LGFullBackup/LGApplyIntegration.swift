import Foundation

// MARK: - Full-backup engine integration

/// `LiquidGlassApplyModel` wiring for the GoldenNugget-style full-backup
/// path (`LGBackupEngine`) and the AFC media store (`LGMediaStore`).
///
/// Kept in an extension so `LiquidGlassBackupFlow.swift` stays the home of
/// the fallback (preference-snapshot / partial-restore) logic.
///
/// Honest-copy rules enforced here, not just in the view:
/// - `backupMode` is the single source of truth for what Backup produced.
/// - The full-device apply/restore never claim a reboot happens for the
///   user — every success message says to reboot manually.
/// - Media pull never deletes device originals from the UI path.
extension LiquidGlassApplyModel {

    /// Refresh device-channel readiness for the prerequisites UI.
    func refreshChannel() {
        let engine = LGBackupEngine.shared
        channelReady = engine.isChannelReady
        channelNote = engine.channelReadinessNote
        airliftPaired = AirLiftManager.shared.isPaired
        tunnelUp = VPNCheck.isVPNActive()
        if mediaInfo == nil {
            mediaInfo = LGMediaStore.info()
        }
    }

    // MARK: - Full-device apply / restore

    /// Apply through the full-device path: compile → inject → restore via
    /// the channel. The restore applies the tweaks; it does not reboot —
    /// the success message says to reboot manually.
    func applyViaFullDevice(tweaks: [Tweak]) {
        begin(.applying)
        taskProgress = "Starting apply…"
        Task {
            defer {
                taskProgress = nil
                end()
            }
            do {
                let count = try await LGBackupEngine.shared.applyFullDevice(tweaks: tweaks) { message in
                    taskProgress = message
                }
                lastChangedFiles = count
                warnings = []
                if count == 0 {
                    statusMessage = "Nothing changed."
                } else {
                    statusMessage = "Restore complete — \(count) file(s) applied. " +
                        "Reboot your device manually for the changes to take effect."
                }
            } catch {
                statusMessage = nil
                warnings = [error.localizedDescription]
            }
        }
    }

    /// Restore the pristine liquid-glass files stashed at backup time.
    /// Only meaningful in full-device mode; the working backup is transient
    /// (wiped at the next Backup run), so this must run before backing up
    /// again.
    func restoreFullDevice() {
        begin(.restoring)
        taskProgress = "Starting restore…"
        Task {
            defer {
                taskProgress = nil
                end()
            }
            do {
                try await LGBackupEngine.shared.restoreFullDevice { message in
                    taskProgress = message
                }
                warnings = []
                statusMessage = "Pristine files restored. " +
                    "Reboot your device manually for the changes to take effect."
            } catch {
                statusMessage = nil
                warnings = [error.localizedDescription]
            }
        }
    }

    // MARK: - Media store

    /// Pull DCIM / PhotoStreamsData over AFC into the app's media store.
    /// Pure safety copy: device originals are never deleted by this action.
    func pullMedia() {
        guard !mediaBusy else { return }
        mediaBusy = true
        taskProgress = "Starting media pull…"
        Task {
            defer {
                taskProgress = nil
                mediaBusy = false
                refreshChannel()
            }
            do {
                let manifest = try await LGBackupEngine.shared.pullMedia { message in
                    taskProgress = message
                }
                mediaInfo = LGMediaStore.info()
                warnings = []
                statusMessage = "Media pull complete: \(manifest.entries.count) file(s) stored and verified."
            } catch {
                statusMessage = nil
                warnings = [error.localizedDescription]
            }
        }
    }

    /// Push the media store's contents back onto the device.
    func pushMediaBack() {
        guard !mediaBusy else { return }
        mediaBusy = true
        taskProgress = "Starting push-back…"
        Task {
            defer {
                taskProgress = nil
                mediaBusy = false
                refreshChannel()
            }
            do {
                try await LGBackupEngine.shared.pushMediaBack { message in
                    taskProgress = message
                }
                warnings = []
                statusMessage = "Push-back finished. Check the log lines above for any skipped files."
            } catch {
                statusMessage = nil
                warnings = [error.localizedDescription]
            }
        }
    }

    /// Empty the media store. Only offered once the user has pushed the
    /// files back — the store may be the only copy.
    func emptyMediaStore() {
        do {
            try LGBackupEngine.shared.emptyMediaStore()
            mediaInfo = nil
            warnings = []
            statusMessage = "Media store emptied."
        } catch {
            warnings = [error.localizedDescription]
        }
    }
}

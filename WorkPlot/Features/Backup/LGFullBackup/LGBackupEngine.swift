import Foundation

// MARK: - Backup mode

/// Which backup actually ran. The fallback label is spec'd UI copy and is
/// shown verbatim: "preference snapshot — not a full device backup".
enum LGBackupMode {
    /// A real device backup was pulled over the AirLift device channel.
    case fullDevice
    /// No usable channel: the existing plist-snapshot flow ran instead.
    case preferenceSnapshot
}

/// The outcome of one `LGBackupEngine.runBackup()`.
struct LGBackupResult {
    let mode: LGBackupMode
    let createdAt: Date
    /// Human-readable detail line for the UI.
    let detail: String
}

// MARK: - Engine errors

enum LGBackupError: LocalizedError {
    /// Apply was pressed without a backup (the UI gates on this too).
    case backupRequired
    case nothingToApply

    var errorDescription: String? {
        switch self {
        case .backupRequired:
            return "For iOS 27 you must press Backup first."
        case .nothingToApply:
            return "There are no Liquid Glass tweaks to apply on this iOS version."
        }
    }
}

// MARK: - Orchestrator

/// Orchestrates the Liquid Glass full-backup path, adapted from the DESIGN of
/// GoldenNugget-mobile's apply pipeline (`GoldenNuggetEngine.applyTweaks`) —
/// no source code was copied; this is an original implementation of that
/// design:
///
///   1. `runBackup()` — wipe the transient working directory (the working
///      backup is transient: wiped at the start of every run), then pull a
///      real device backup over the AirLift device channel and prune its
///      manifest to the disk state. When no usable channel exists, fall back
///      to the existing preference-snapshot flow (`LiquidGlassBackupStore`)
///      and say so — the UI labels the fallback honestly.
///   2. Media moves separately over AFC (`LGMediaStore`), with
///      verify-before-delete, exactly like the reference design.
///   3. `applyFullDevice()` — compile the enabled tweaks to whole-file
///      plists BEFORE the device is touched (an impossible selection costs
///      nothing), inject them into the working backup AFTER the prune, then
///      restore. The restore is the step that applies the tweaks.
///
/// There is NO automatic restore at device boot anywhere here, and the
/// restore does NOT reboot the device — the user reboots manually. UI copy
/// must never claim otherwise.
///
/// All progress handlers are called on the main actor.
@MainActor
final class LGBackupEngine {
    static let shared = LGBackupEngine()
    private init() {}

    /// Genuine mobilebackup2 channel — the real GoldenNugget-mobile method.
    /// NOT AirLift, NOT a plist snapshot.
    var channel: LGDeviceChannel = MobileBackup2Channel.shared

    var isChannelReady: Bool { channel.isReady }
    var channelReadinessNote: String? { channel.readinessNote }

    // MARK: - Backup

    /// Run one backup. Full-device when the channel is usable; otherwise the
    /// honest preference-snapshot fallback. The working directory is wiped
    /// first either way — the working backup never carries over between runs.
    func runBackup(onProgress: @escaping (String) -> Void) async throws -> LGBackupResult {
        try LGManifestStore.resetWorkingDirectory()
        onProgress("Preparing backup workspace…")

        if channel.isReady {
            do {
                return try await runFullDeviceBackup(onProgress: onProgress)
            } catch let error as LGChannelError {
                // The channel looked ready but its device I/O is not there
                // yet — fall back honestly instead of failing the run.
                onProgress("Full-device backup unavailable (\(error.localizedDescription))")
            }
        } else if let note = channel.readinessNote {
            onProgress("Device channel not ready (\(note))")
        }

        onProgress("Taking a preference snapshot instead…")
        let info = try LiquidGlassBackupStore.createFullBackup()
        return LGBackupResult(
            mode: .preferenceSnapshot,
            createdAt: info.createdAt,
            detail: "preference snapshot — not a full device backup")
    }

    /// The real GoldenNugget-style path: pull → prune. Requires the genuine
    /// on-device AirLift channel (`r5/airlift-real`); throws
    /// `backendUnavailable` until it lands.
    private func runFullDeviceBackup(onProgress: @escaping (String) -> Void) async throws -> LGBackupResult {
        let udid = LGManifestStore.deviceIdentifier
        let deviceDir = try LGManifestStore.deviceWorkingDirectory(udid: udid)

        onProgress("Pulling device backup…")
        try await channel.pullBackup(into: deviceDir, udid: udid) { percent in
            let clamped = max(0, min(100, percent))
            onProgress(String(format: "Pulling device backup… %.0f%%", clamped))
        }
        try LGManifestStore.notePullCompleted(udid: udid)

        // Stash the pristine liquid-glass targets now — the restore half of
        // this flow needs the pre-tweak bytes, and the working backup is
        // transient (wiped at the next Backup run).
        try stashPristineLG()

        let dropped = try LGManifestStore.pruneToDiskState(deviceDir: deviceDir)
        onProgress("Backup pulled — pruned \(dropped) stale row(s).")

        return LGBackupResult(mode: .fullDevice, createdAt: Date(),
                              detail: "full device backup (GoldenNugget-style)")
    }

    // MARK: - Apply (full-device path)

    /// Compile → inject → restore. Gated on a completed full-device backup;
    /// the UI disables Apply until `runBackup()` reports `.fullDevice`.
    ///
    /// - Returns: the number of plist payloads injected.
    /// - Note: the restore applies the tweaks but does NOT reboot the
    ///   device. The caller must tell the user to reboot manually.
    func applyFullDevice(tweaks: [Tweak],
                         onProgress: @escaping (String) -> Void) async throws -> Int {
        // 1. Compile the selection to plists before the device is touched.
        onProgress("Compiling liquid-glass tweaks…")
        let payloads = try Self.compileLGTweakPayloads(tweaks: tweaks)
        guard !payloads.isEmpty else { throw LGBackupError.nothingToApply }

        // 2. The working backup must exist — Backup ran first.
        let deviceDir = try LGManifestStore.deviceWorkingDirectory()
        guard LGManifestStore.readWorkingManifest().pulledAt != nil else {
            throw LGBackupError.backupRequired
        }

        // 3. Prune, then inject. Injection rides AFTER the prune: no tweak
        //    row is in the keep-set, so a row written before the prune would
        //    be deleted on the way past.
        onProgress("Preparing backup…")
        try LGManifestStore.pruneToDiskState(deviceDir: deviceDir)
        try LGManifestStore.injectLGTweaks(into: deviceDir, payloads: payloads)
        onProgress("Injected \(payloads.count) tweak file(s).")

        // 4. Restore — this is the step that applies the tweaks.
        onProgress("Restoring…")
        try await channel.restore(deviceDir: deviceDir,
                                  sourceIdentifier: LGManifestStore.deviceIdentifier) { percent in
            let clamped = max(0, min(100, percent))
            onProgress(String(format: "Restoring… %.0f%%", clamped))
        }
        return payloads.count
    }

    // MARK: - Media

    /// Pull DCIM/PhotoStreamsData over AFC into the app's media store.
    /// Requires the channel; the UI gates on `isChannelReady`.
    func pullMedia(deletingOriginals: Bool = false,
                   onProgress: @escaping (String) -> Void) async throws -> LGMediaStore.Manifest {
        try requireChannel()
        return try await LGMediaStore.pull(channel: channel,
                                           deletingOriginals: deletingOriginals,
                                           onProgress: onProgress)
    }

    /// Push the media store's contents back onto the device.
    func pushMediaBack(onProgress: @escaping (String) -> Void) async throws {
        try requireChannel()
        try await LGMediaStore.pushBack(channel: channel, onProgress: onProgress)
    }

    func emptyMediaStore() throws {
        try LGMediaStore.emptyStore()
    }

    private func requireChannel() throws {
        guard channel.isReady else {
            throw LGChannelError.backendUnavailable(
                channel.readinessNote ?? "The device channel is not ready.")
        }
    }

    // MARK: - Pristine stash (full-device restore)

    /// One stashed pristine file's index record.
    private struct PristineEntry: Codable {
        let domain: String
        let relativePath: String
        let fileName: String
    }

    private var pristineDir: URL {
        LGManifestStore.workingRoot.appendingPathComponent("PristineLG", isDirectory: true)
    }

    private var pristineIndexURL: URL {
        pristineDir.appendingPathComponent("pristine.json")
    }

    /// Stash pristine byte copies of the liquid-glass target files at backup
    /// time, so the full-device path can genuinely restore the pre-tweak
    /// state later. Lives in the transient working dir — wiped at the start
    /// of the next Backup run, exactly like the rest of the working backup.
    private func stashPristineLG() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: pristineDir, withIntermediateDirectories: true)
        var index: [PristineEntry] = []
        for target in LGManifestStore.liquidGlassTargets {
            guard let domain = Self.plistDomain(for: target) else { continue }
            var bytes: Data?
            for path in GestaltStore.preferencePlistPaths(for: domain) {
                if let data = fm.contents(atPath: path) { bytes = data; break }
            }
            guard let data = bytes else { continue }
            let fileName = LGManifestStore.fileID(domain: target.domain,
                                                  relativePath: target.relativePath) + ".plist"
            try data.write(to: pristineDir.appendingPathComponent(fileName), options: .atomic)
            index.append(PristineEntry(domain: target.domain,
                                       relativePath: target.relativePath,
                                       fileName: fileName))
        }
        let encoded = try JSONEncoder().encode(index)
        try encoded.write(to: pristineIndexURL, options: .atomic)
    }

    private func readPristineLGPayloads() throws -> [String: Data] {
        guard let indexData = try? Data(contentsOf: pristineIndexURL),
              let index = try? JSONDecoder().decode([PristineEntry].self, from: indexData)
        else { return [:] }
        var out: [String: Data] = [:]
        for entry in index {
            let url = pristineDir.appendingPathComponent(entry.fileName)
            guard let data = try? Data(contentsOf: url) else { continue }
            out["\(entry.domain)/\(entry.relativePath)"] = data
        }
        return out
    }

    /// Restore the pristine liquid-glass files stashed at backup time: inject
    /// them into the working backup (over the tweaked rows) and restore the
    /// whole backup through the channel. The device comes back to its
    /// at-backup state with pristine liquid-glass files.
    ///
    /// Like every other restore here, this does NOT reboot the device — the
    /// user reboots manually.
    func restoreFullDevice(onProgress: @escaping (String) -> Void) async throws {
        let deviceDir = try LGManifestStore.deviceWorkingDirectory()
        guard LGManifestStore.readWorkingManifest().pulledAt != nil else {
            throw LGBackupError.backupRequired
        }
        let pristine = try readPristineLGPayloads()
        guard !pristine.isEmpty else {
            throw LGChannelError.transferFailed(
                "No pristine liquid-glass copies were stashed at backup time — nothing to restore.")
        }
        onProgress("Preparing pristine files…")
        try LGManifestStore.pruneToDiskState(deviceDir: deviceDir)
        try LGManifestStore.injectLGTweaks(into: deviceDir, payloads: pristine)
        onProgress("Restoring…")
        try await channel.restore(deviceDir: deviceDir,
                                  sourceIdentifier: LGManifestStore.deviceIdentifier) { percent in
            let clamped = max(0, min(100, percent))
            onProgress(String(format: "Restoring… %.0f%%", clamped))
        }
    }

    /// Backup-domain coordinates → the tweak plist domain used to probe the
    /// live file. Narrowed to the liquid-glass injection targets.
    private static func plistDomain(for coords: (domain: String, relativePath: String)) -> PlistDomain? {
        guard coords.domain == "HomeDomain" else { return nil }
        switch coords.relativePath {
        case "Library/Preferences/.GlobalPreferences.plist":
            return .globalPreferences
        case "Library/Preferences/com.apple.springboard.plist":
            return .springBoard
        default:
            return nil
        }
    }

    // MARK: - Tweak compilation

    /// Compile the current Liquid Glass toggle selection into whole-file
    /// plist payloads, keyed `"domain/relativePath"` in backup coordinates.
    ///
    /// Merge semantics mirror `GestaltStore.applyPlistModifications`: enabled
    /// writes the value (`.remove` / `.keepCurrent` untouched), disabled
    /// removes the key. Unrelated keys are preserved; the file is serialized
    /// in its original plist format.
    static func compileLGTweakPayloads(tweaks: [Tweak]) throws -> [String: Data] {
        let inScope = tweaks.filter { $0.category == .liquidGlass && !$0.plistModifications.isEmpty }
        guard !inScope.isEmpty else { throw LGBackupError.nothingToApply }

        var payloads: [String: Data] = [:]
        var warnings: [String] = []
        let pairs = inScope.flatMap { tweak in tweak.plistModifications.map { (tweak, $0) } }
        for (domain, entries) in Dictionary(grouping: pairs, by: { $0.1.domain }) {
            guard let coords = backupCoordinates(for: domain) else { continue }
            var format = PropertyListSerialization.PropertyListFormat.binary
            var merged: [String: Any]?
            for path in GestaltStore.preferencePlistPaths(for: domain) {
                guard let data = FileManager.default.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(
                        from: data, options: [], format: &format) as? [String: Any]
                else { continue }
                merged = plist
                break
            }
            guard var plist = merged else {
                warnings.append("\(domainLabel(domain)): preference file not reachable — skipped.")
                continue
            }
            for (tweak, mod) in entries {
                if tweak.isEnabled {
                    switch mod.value {
                    case .remove, .keepCurrent:
                        break
                    default:
                        plist[mod.key] = mod.value.plistObject
                    }
                } else {
                    plist.removeValue(forKey: mod.key)
                }
            }
            let out = try PropertyListSerialization.data(fromPropertyList: plist,
                                                         format: format, options: 0)
            payloads["\(coords.domain)/\(coords.relativePath)"] = out
        }
        for warning in warnings {
            // Compile warnings go to the session log, not the throw path: a
            // partially compilable selection still applies what it can.
            SessionLogger.shared.log(warning)
        }
        return payloads
    }

    /// Backup-domain coordinates for a tweak plist domain, narrowed to the
    /// liquid-glass injection targets in `LGManifestStore`.
    private static func backupCoordinates(for domain: PlistDomain) -> (domain: String, relativePath: String)? {
        switch domain {
        case .globalPreferences:
            return ("HomeDomain", "Library/Preferences/.GlobalPreferences.plist")
        case .springBoard:
            return ("HomeDomain", "Library/Preferences/com.apple.springboard.plist")
        }
    }

    private static func domainLabel(_ domain: PlistDomain) -> String {
        switch domain {
        case .globalPreferences: return "GlobalPreferences"
        case .springBoard: return "SpringBoard"
        }
    }
}

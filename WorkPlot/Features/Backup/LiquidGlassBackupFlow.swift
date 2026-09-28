import Foundation
import SwiftUI

// MARK: - Flow selection

/// Which Disable-Liquid-Glass apply route WorkSlop uses, picked from the
/// running iOS version via `WorkSlopSupport.isIOS27()` / `isIOS26()`.
enum LiquidGlassFlow {
    /// iOS 27: full backup → modify → full restore (GoldenNugget-style).
    case fullBackup
    /// iOS 26: partial-restore (bookrestore-style) — no Backup step.
    case partialRestore
    case unsupported

    static var current: LiquidGlassFlow {
        if WorkSlopSupport.isIOS27() { return .fullBackup }
        if WorkSlopSupport.isIOS26() { return .partialRestore }
        return .unsupported
    }

    /// The note shown directly under the Apply button. The iOS 27 string
    /// is spec'd verbatim — do not reword it.
    var applyNote: String {
        switch self {
        case .fullBackup:
            return "For iOS 27 you must press Backup first"
        case .partialRestore:
            return "On iOS 26 the partial-restore flow applies directly — no backup step needed."
        case .unsupported:
            return "The backup-safe liquid-glass flow needs iOS 26 or 27."
        }
    }
}

// MARK: - Full backup (iOS 27)

/// One full liquid-glass backup snapshot: pristine byte-for-byte copies of
/// every reachable target preference file.
struct LiquidGlassBackupInfo {
    let createdAt: Date
    /// (display name, byte count) per snapshotted file.
    let files: [(name: String, byteCount: Int)]

    var totalBytes: Int { files.reduce(0) { $0 + $1.byteCount } }
}

/// Pristine snapshots of the liquid-glass target preference files
/// (`.GlobalPreferences.plist` and the SpringBoard preferences).
///
/// iOS 27 path of the disable-liquid-glass flow, GoldenNugget-style:
/// `createFullBackup()` snapshots the live files BEFORE anything is
/// modified; `restoreFullBackup()` writes those pristine copies back over
/// the live files (the "full restore" half of backup → modify → restore).
///
/// Create-once semantics, like `BackupManager.ensureBackup`: the snapshot
/// is taken from the untouched files and is never overwritten, so Restore
/// always returns the device to its pre-tweak state.
enum LiquidGlassBackupStore {

    enum BackupError: LocalizedError {
        case noReachableFiles
        case readFailed

        var errorDescription: String? {
            switch self {
            case .noReachableFiles:
                return "None of the liquid-glass preference files are reachable on this device."
            case .readFailed:
                return "Could not read the liquid-glass backup snapshot."
            }
        }
    }

    private struct Manifest: Codable {
        struct Entry: Codable {
            let fileName: String
            let originalPath: String
            let byteCount: Int
        }
        let createdAt: Date
        let entries: [Entry]
    }

    /// The liquid-glass target domains, in probe order.
    private static var domains: [PlistDomain] { [.globalPreferences, .springBoard] }

    private static func domainLabel(_ domain: PlistDomain) -> String {
        switch domain {
        case .globalPreferences: return "GlobalPreferences"
        case .springBoard: return "SpringBoard"
        }
    }

    private static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkSlop/LiquidGlassBackup", isDirectory: true)
    }

    private static var manifestURL: URL {
        root.appendingPathComponent("manifest.json")
    }

    /// Every reachable on-device target file, as (domain, path), in probe
    /// order. Uses the same path list `GestaltStore` writes through.
    static func reachableTargets() -> [(domain: PlistDomain, path: String)] {
        domains.flatMap { domain in
            GestaltStore.preferencePlistPaths(for: domain)
                .filter { FileManager.default.fileExists(atPath: $0) }
                .map { (domain, $0) }
        }
    }

    static var hasBackup: Bool {
        FileManager.default.fileExists(atPath: manifestURL.path)
    }

    static func info() -> LiquidGlassBackupInfo? {
        guard let manifest = readManifest() else { return nil }
        return LiquidGlassBackupInfo(
            createdAt: manifest.createdAt,
            files: manifest.entries.map { ($0.fileName, $0.byteCount) }
        )
    }

    /// Snapshots every reachable target file. Create-once: when a snapshot
    /// already exists it is returned untouched — the pristine recovery
    /// point is never overwritten by a post-tweak state.
    @discardableResult
    static func createFullBackup() throws -> LiquidGlassBackupInfo {
        if let existing = info() { return existing }
        let targets = reachableTargets()
        guard !targets.isEmpty else { throw BackupError.noReachableFiles }
        try FileManager.default.createDirectory(at: root,
                                                withIntermediateDirectories: true)
        var entries: [Manifest.Entry] = []
        for (index, target) in targets.enumerated() {
            let fileName = "\(domainLabel(target.domain))-\(index).plist"
            let data = try Data(contentsOf: URL(fileURLWithPath: target.path))
            try data.write(to: root.appendingPathComponent(fileName),
                           options: .atomic)
            entries.append(Manifest.Entry(fileName: fileName,
                                          originalPath: target.path,
                                          byteCount: data.count))
        }
        let manifest = Manifest(createdAt: Date(), entries: entries)
        let encoded = try JSONEncoder().encode(manifest)
        try encoded.write(to: manifestURL, options: .atomic)
        return LiquidGlassBackupInfo(
            createdAt: manifest.createdAt,
            files: entries.map { ($0.fileName, $0.byteCount) }
        )
    }

    /// Full restore: writes every pristine snapshot copy back over its live
    /// file through the bad_query lease + verified in-place write — the
    /// same primitive the modify step uses.
    static func restoreFullBackup() throws {
        guard let manifest = readManifest() else { throw BackupError.readFailed }
        for entry in manifest.entries {
            let data = try Data(contentsOf: root.appendingPathComponent(entry.fileName))
            try BadQueryLeaseScope.withLease(forPath: entry.originalPath) {
                try InodeWriter.writeVerifiedInPlace(data, to: entry.originalPath)
            }
        }
    }

    static func deleteBackup() throws {
        try FileManager.default.removeItem(at: root)
    }

    private static func readManifest() -> Manifest? {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return nil }
        // The snapshot files must still be there; otherwise the manifest
        // is stale.
        let allPresent = manifest.entries.allSatisfy {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0.fileName).path)
        }
        return allPresent ? manifest : nil
    }
}

// MARK: - Partial restore (iOS 26, bookrestore-style)

/// A bookrestore-style partial-restore session for the iOS 26
/// disable-liquid-glass flow.
///
/// Instead of demanding a full backup up front, the session captures
/// *pre-images* — the current bytes of every target file the flow is about
/// to touch — then applies the staged changes through the same probe +
/// lease + verified in-place write the full flow uses. `revert()` writes
/// the pre-images back, so the last apply can always be undone. Only the
/// files the flow actually touches are recorded: a minimal restore set,
/// not a full backup.
struct BookRestoreSession {
    struct PreImage {
        let path: String
        /// `nil` when the file did not exist before the apply.
        let data: Data?
    }

    private let preImages: [PreImage]

    /// Captures pre-images of every reachable liquid-glass target file.
    static func capture() -> BookRestoreSession {
        let preImages = LiquidGlassBackupStore.reachableTargets().map { target in
            PreImage(path: target.path,
                     data: FileManager.default.contents(atPath: target.path))
        }
        return BookRestoreSession(preImages: preImages)
    }

    /// Writes every pre-image back over its live file (the partial
    /// "restore" half). Files that did not exist before the apply are left
    /// alone — their liquid-glass keys were only ever removed-or-absent,
    /// so there is nothing to restore.
    func revert() throws {
        for preImage in preImages {
            guard let original = preImage.data else { continue }
            try BadQueryLeaseScope.withLease(forPath: preImage.path) {
                try InodeWriter.writeVerifiedInPlace(original, to: preImage.path)
            }
        }
    }
}

// MARK: - Orchestrator

/// Errors for the Disable-Liquid-Glass apply flow.
enum LiquidGlassFlowError: LocalizedError {
    /// iOS 27: Apply was pressed before Backup.
    case backupRequired
    case nothingToApply
    case nothingToUndo
    case unsupportedFlow
    /// A key did not read back as expected after writing.
    case verifyFailed(String)

    var errorDescription: String? {
        switch self {
        case .backupRequired:
            return "For iOS 27 you must press Backup first."
        case .nothingToApply:
            return "There are no Liquid Glass tweaks to apply on this iOS version."
        case .nothingToUndo:
            return "There is no partial-restore apply to undo yet."
        case .unsupportedFlow:
            return "The backup-safe liquid-glass flow needs iOS 26 or 27."
        case .verifyFailed(let message):
            return message
        }
    }
}

/// Orchestrates the Disable-Liquid-Glass apply flow for the UI:
/// full backup → modify → full restore on iOS 27, partial-restore
/// (bookrestore-style) on iOS 26. Any write or verification failure
/// triggers the restore half of the flow, so the device is never left
/// half-modified.
@MainActor
final class LiquidGlassApplyModel: ObservableObject {
    /// Which step is currently running, for per-button spinners.
    enum BusyTask { case backingUp, applying, restoring }

    @Published private(set) var isBusy = false
    @Published private(set) var busyTask: BusyTask?
    @Published private(set) var statusMessage: String?
    @Published private(set) var warnings: [String] = []
    @Published private(set) var lastChangedFiles = 0
    @Published private(set) var backupInfo: LiquidGlassBackupInfo?
    @Published private(set) var canUndoPartial = false

    private var lastSession: BookRestoreSession?

    var flow: LiquidGlassFlow { LiquidGlassFlow.current }

    func refresh() {
        backupInfo = LiquidGlassBackupStore.info()
    }

    private func begin(_ task: BusyTask) {
        isBusy = true
        busyTask = task
    }

    private func end() {
        isBusy = false
        busyTask = nil
        refresh()
    }

    // MARK: Backup (iOS 27)

    /// Snapshots the pristine target files. Create-once — an existing
    /// snapshot is never overwritten.
    func createBackup() {
        guard !isBusy else { return }
        begin(.backingUp)
        defer { end() }
        do {
            backupInfo = try LiquidGlassBackupStore.createFullBackup()
            warnings = []
            statusMessage = "Backup created — you can now press Apply."
        } catch {
            statusMessage = nil
            warnings = [error.localizedDescription]
        }
    }

    // MARK: Apply

    /// Applies the staged liquid-glass tweaks through the
    /// version-appropriate flow, then verifies every touched key.
    func apply(tweaks: [Tweak]) {
        guard !isBusy else { return }
        begin(.applying)
        defer { end() }
        do {
            let changed = try runApply(tweaks: tweaks)
            lastChangedFiles = changed
            statusMessage = changed == 0
                ? "Nothing changed — the keys already match the staged tweaks."
                : "Applied to \(changed) file\(changed == 1 ? "" : "s"). Respring to take effect."
        } catch {
            statusMessage = nil
            // `runApply` already surfaced write warnings before throwing.
            if warnings.isEmpty { warnings = [error.localizedDescription] }
        }
    }

    private func runApply(tweaks: [Tweak]) throws -> Int {
        let inScope = tweaks.filter {
            $0.category == .liquidGlass && !$0.plistModifications.isEmpty
        }
        guard !inScope.isEmpty else { throw LiquidGlassFlowError.nothingToApply }
        let enabled = inScope.filter(\.isEnabled)
        let disabled = inScope.filter { !$0.isEnabled }

        switch flow {
        case .fullBackup:
            guard LiquidGlassBackupStore.hasBackup else {
                throw LiquidGlassFlowError.backupRequired
            }
            var stepWarnings: [String] = []
            do {
                let changed = Self.write(enabled: enabled,
                                         disabled: disabled,
                                         warnings: &stepWarnings)
                stepWarnings += Self.verify(enabled: enabled, disabled: disabled)
                warnings = stepWarnings
                return changed
            } catch {
                // Full restore: pristine snapshot back over the live files.
                try? LiquidGlassBackupStore.restoreFullBackup()
                warnings = stepWarnings + [error.localizedDescription,
                                           "The pristine backup was restored."]
                throw error
            }
        case .partialRestore:
            let session = BookRestoreSession.capture()
            var stepWarnings: [String] = []
            do {
                let changed = Self.write(enabled: enabled,
                                         disabled: disabled,
                                         warnings: &stepWarnings)
                stepWarnings += Self.verify(enabled: enabled, disabled: disabled)
                lastSession = session
                canUndoPartial = true
                warnings = stepWarnings
                return changed
            } catch {
                try? session.revert()
                warnings = stepWarnings + [error.localizedDescription,
                                           "The pre-apply state was restored."]
                throw error
            }
        case .unsupported:
            throw LiquidGlassFlowError.unsupportedFlow
        }
    }

    /// Writes the staged tweaks through `GestaltStore`'s shared
    /// probe + lease + verified in-place write path: enabled tweaks write
    /// their values, disabled tweaks have their keys removed. Returns the
    /// number of files actually changed.
    private static func write(enabled: [Tweak],
                              disabled: [Tweak],
                              warnings: inout [String]) -> Int {
        var changed = 0
        for tweak in enabled {
            changed += GestaltStore.applyPlistModifications(tweak.plistModifications,
                                                            enabled: true,
                                                            warnings: &warnings)
        }
        for tweak in disabled {
            changed += GestaltStore.applyPlistModifications(tweak.plistModifications,
                                                            enabled: false,
                                                            warnings: &warnings)
        }
        return changed
    }

    /// Re-reads every staged key from every reachable copy and confirms the
    /// expected presence/value. Returns non-fatal warnings (e.g. a domain
    /// with no reachable file); throws on the first real mismatch.
    private static func verify(enabled: [Tweak], disabled: [Tweak]) throws -> [String] {
        var verifyWarnings: [String] = []
        for tweak in enabled {
            for mod in tweak.plistModifications {
                switch Self.check(mod, enabled: true) {
                case .ok: break
                case .unreachable:
                    verifyWarnings.append("\(tweak.title): \(mod.key) — target file not reachable, skipped.")
                case .mismatch:
                    throw LiquidGlassFlowError.verifyFailed("\(tweak.title): \(mod.key) did not verify after writing.")
                }
            }
        }
        for tweak in disabled {
            for mod in tweak.plistModifications {
                switch Self.check(mod, enabled: false) {
                case .ok: break
                case .unreachable:
                    verifyWarnings.append("\(tweak.title): \(mod.key) — target file not reachable, skipped.")
                case .mismatch:
                    throw LiquidGlassFlowError.verifyFailed("\(tweak.title): \(mod.key) did not verify after writing.")
                }
            }
        }
        return verifyWarnings
    }

    private enum CheckResult { case ok, unreachable, mismatch }

    private static func check(_ mod: PlistModification, enabled: Bool) -> CheckResult {
        let paths = GestaltStore.preferencePlistPaths(for: mod.domain)
        var checked = 0
        for path in paths {
            guard let data = FileManager.default.contents(atPath: path) else { continue }
            var format = PropertyListSerialization.PropertyListFormat.binary
            guard let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: &format) as? [String: Any]
            else { continue }
            checked += 1
            if enabled {
                switch mod.value {
                case .remove, .keepCurrent:
                    break
                default:
                    guard plistScalarsEqual(plist[mod.key], mod.value.plistObject) else {
                        return .mismatch
                    }
                }
            } else if plist[mod.key] != nil {
                return .mismatch
            }
        }
        return checked > 0 ? .ok : .unreachable
    }

    /// True when two plist scalars are equal (bridged through NSObject).
    /// Mirrors `GestaltStore`'s private helper, which this file can't see.
    private static func plistScalarsEqual(_ current: Any?, _ new: Any) -> Bool {
        guard let current, let newObject = new as? NSObject else { return false }
        return (current as? NSObject)?.isEqual(newObject) ?? false
    }

    // MARK: Restore / undo

    /// iOS 27: full restore of the pristine snapshot.
    /// iOS 26: revert the last partial-restore apply via its pre-images.
    func restore() {
        guard !isBusy else { return }
        begin(.restoring)
        defer { end() }
        do {
            switch flow {
            case .fullBackup:
                try LiquidGlassBackupStore.restoreFullBackup()
                statusMessage = "Full backup restored. Respring to take effect."
            case .partialRestore:
                guard let session = lastSession else {
                    throw LiquidGlassFlowError.nothingToUndo
                }
                try session.revert()
                lastSession = nil
                canUndoPartial = false
                statusMessage = "Last apply reverted. Respring to take effect."
            case .unsupported:
                throw LiquidGlassFlowError.unsupportedFlow
            }
            warnings = []
        } catch {
            statusMessage = nil
            warnings = [error.localizedDescription]
        }
    }
}

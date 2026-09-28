import CryptoKit
import Foundation
import UIKit

// MARK: - Working-backup manifest store

/// Bookkeeping for the Liquid Glass full-backup's transient working backup.
///
/// Adapted from the DESIGN of GoldenNugget-mobile's manifest handling
/// (`Nugget/Core/ManifestStore.swift` + `BackupInjector.swift`) — no source
/// code was copied; this is an original implementation of that design:
///
/// - The working backup is TRANSIENT: it is wiped at the start of every run
///   (`resetWorkingDirectory()`), exactly like the reference design.
/// - A file's identity is the iOS backup fileID scheme: the SHA-1 hex of
///   `"domain-relativePath"`, stored in the two-character shard layout
///   `<shard>/<fileID>` the restore agent expects.
/// - `pruneToDiskState()` drops rows whose payload is not on disk — a
///   restore would fail on a row it cannot serve.
/// - `injectLGTweakPlist(...)` writes the tweak payload + its rows (domain
///   root, parent directories, then the file), narrowed to the liquid-glass
///   plist targets. Injection rides AFTER the prune: no tweak row is in the
///   keep-set, so a row written before the prune would be deleted on the
///   way past.
///
/// The row SHAPE for a real `Manifest.db` (owner, protection class, blob) is
/// recorded here as data, but synthesizing binary `MBFile` blobs for a real
/// pulled `Manifest.db` is part of the pending real-channel work
/// (`r5/airlift-real`) — this store never fabricates a database the device
/// did not produce. What it does maintain, honestly, is the JSON working
/// manifest: pull record, prune record, and injected rows.
@MainActor
enum LGManifestStore {

    // MARK: - Injected row

    /// One injected tweak row, as recorded in the working manifest.
    /// `flags`: 1 = file, 2 = directory (the backup manifest convention).
    struct InjectedRow: Codable {
        var fileID: String
        var domain: String
        var relativePath: String
        var flags: Int
        var size: Int64
        var mode: Int
        var userID: Int
        var groupID: Int
        var protectionClass: Int
        var injectedAt: Date
    }

    /// The liquid-glass tweak injection targets, narrowed to the plist files
    /// the Liquid Glass tweak set actually writes.
    ///
    /// - `.GlobalPreferences.plist` → HomeDomain, the liquid-glass keys.
    /// - `com.apple.springboard.plist` → HomeDomain, SpringBoard prefs.
    /// Plus the domain-root rows, which the restore agent needs so it does
    /// not skip the whole domain.
    static let liquidGlassTargets: [(domain: String, relativePath: String)] = [
        ("HomeDomain", "Library/Preferences/.GlobalPreferences.plist"),
        ("HomeDomain", "Library/Preferences/com.apple.springboard.plist"),
    ]

    /// iOS backup fileID: SHA-1 hex of "domain-relativePath". This is the
    /// device's own naming scheme for backup payloads (functional design,
    /// reimplemented here).
    static func fileID(domain: String, relativePath: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data("\(domain)-\(relativePath)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Working directory lifecycle

    /// `<Documents>/WorkSlop/LGWorking/` — the transient working root.
    static var workingRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkSlop/LGWorking", isDirectory: true)
    }

    /// Stable local identifier used in place of the device UDID until the
    /// real channel reports one. Documented, not faked: the working backup
    /// is per-device, and this is the best stable ID available on-device.
    static var deviceIdentifier: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "device"
    }

    /// `<working>/<udid>/` — the per-device working backup directory.
    static func deviceWorkingDirectory(udid: String = deviceIdentifier) throws -> URL {
        let dir = workingRoot.appendingPathComponent(udid, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var workingManifestURL: URL {
        workingRoot.appendingPathComponent("lg-working.json")
    }

    /// Wipe the transient working backup. Called at the START of every run —
    /// a run never builds on a previous run's working backup, exactly like
    /// the reference design.
    static func resetWorkingDirectory() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: workingRoot.path) {
            try fm.removeItem(at: workingRoot)
        }
        try fm.createDirectory(at: workingRoot, withIntermediateDirectories: true)
        try writeWorkingManifest(WorkingManifest())
    }

    // MARK: - Working manifest

    struct WorkingManifest: Codable {
        var version: Int = 1
        var udid: String = ""
        var pulledAt: Date?
        var prunedAt: Date?
        var injectedRows: [InjectedRow] = []
    }

    static func readWorkingManifest() -> WorkingManifest {
        guard let data = try? Data(contentsOf: workingManifestURL),
              let manifest = try? JSONDecoder().decode(WorkingManifest.self, from: data)
        else { return WorkingManifest() }
        return manifest
    }

    private static func writeWorkingManifest(_ manifest: WorkingManifest) throws {
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: workingManifestURL, options: .atomic)
    }

    /// Record that a backup pull completed into `deviceDir`.
    static func notePullCompleted(udid: String) throws {
        var manifest = readWorkingManifest()
        manifest.udid = udid
        manifest.pulledAt = Date()
        try writeWorkingManifest(manifest)
    }

    // MARK: - Prune

    /// Prune the working manifest to the disk state: drop injected-row
    /// records whose payload file is absent. A restore would fail on a row
    /// it cannot serve, so a missing payload is a dropped row — never a
    /// silent gap.
    ///
    /// Rows are also dropped when their target is not one of the
    /// liquid-glass injection targets: this store only ever injects LG
    /// tweaks, so anything else in the working manifest is stale from an
    /// older run shape.
    @discardableResult
    static func pruneToDiskState(deviceDir: URL) throws -> Int {
        var manifest = readWorkingManifest()
        let fm = FileManager.default
        let targets = Set(liquidGlassTargets.map { "\($0.domain)/\($0.relativePath)" })
        var kept: [InjectedRow] = []
        var dropped = 0
        for row in manifest.injectedRows {
            let key = "\(row.domain)/\(row.relativePath)"
            // Directory scaffolding rows (flags == 2) carry no payload.
            let payloadExists = row.flags == 2 ||
                fm.fileExists(atPath: payloadURL(forFileID: row.fileID, in: deviceDir).path)
            if payloadExists && (targets.contains(key) || row.flags == 2) {
                kept.append(row)
            } else {
                dropped += 1
            }
        }
        manifest.injectedRows = kept
        manifest.prunedAt = Date()
        try writeWorkingManifest(manifest)
        return dropped
    }

    // MARK: - Inject

    /// Payload location for a fileID: the `<shard>/<fileID>` layout the
    /// restore agent joins against.
    static func payloadURL(forFileID fileID: String, in deviceDir: URL) -> URL {
        deviceDir
            .appendingPathComponent(String(fileID.prefix(2)), isDirectory: true)
            .appendingPathComponent(fileID)
    }

    /// Inject one liquid-glass tweak plist into the working backup: payload
    /// at its fileID shard, plus rows for the domain root, each parent
    /// directory, and the file itself (dirs first, so a key collision with
    /// the file row is impossible).
    ///
    /// Row shape mirrors what the device records for a system-container
    /// plist: `nobody` (-2) owner, protection class 4 on files, 0 on the
    /// domain root — the same shape the reference design measured off a
    /// real device row rather than inventing.
    static func injectLGTweakPlist(into deviceDir: URL,
                                   domain: String,
                                   relativePath: String,
                                   contents: Data) throws {
        let fm = FileManager.default
        var manifest = readWorkingManifest()

        // 1. Payload where the fileID says it lives.
        let fileID = fileID(domain: domain, relativePath: relativePath)
        let payload = payloadURL(forFileID: fileID, in: deviceDir)
        try fm.createDirectory(at: payload.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try contents.write(to: payload, options: .atomic)

        // 2. Rows: domain root, one per parent component, then the file.
        var rows: [(path: String, flags: Int)] = [("", 2)]
        var accumulated = ""
        for component in relativePath.split(separator: "/").dropLast() {
            accumulated = accumulated.isEmpty ? String(component) : "\(accumulated)/\(component)"
            rows.append((accumulated, 2))
        }
        rows.append((relativePath, 1))

        let now = Date()
        let systemOwner = -2 // Darwin's `nobody`, per the device's own rows.
        for row in rows {
            let isFile = row.flags == 1
            let isRoot = row.path.isEmpty
            let rowID = fileID(domain: domain, relativePath: row.path)
            // Replace any older row for the same fileID: re-running an apply
            // must not leave two rows for one file.
            manifest.injectedRows.removeAll { $0.fileID == rowID }
            manifest.injectedRows.append(InjectedRow(
                fileID: rowID,
                domain: domain,
                relativePath: row.path,
                flags: row.flags,
                size: isFile ? Int64(contents.count) : 0,
                mode: isFile ? 0o100644 : 0o40755,
                // The domain root row is the single exception: the device
                // records 0/0 at protection class 0 there.
                userID: isRoot ? 0 : systemOwner,
                groupID: isRoot ? 0 : systemOwner,
                protectionClass: isRoot ? 0 : 4,
                injectedAt: now))
        }
        try writeWorkingManifest(manifest)
    }

    /// Inject every liquid-glass tweak plist for this run. `payloads` maps
    /// `"domain/relativePath"` → whole-file plist bytes.
    static func injectLGTweaks(into deviceDir: URL, payloads: [String: Data]) throws {
        for (key, contents) in payloads {
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            try injectLGTweakPlist(into: deviceDir, domain: parts[0],
                                   relativePath: parts[1], contents: contents)
        }
    }
}

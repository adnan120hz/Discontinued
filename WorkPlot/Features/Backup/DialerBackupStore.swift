import Foundation
import CryptoKit

// MARK: - DialerBackupStore
//
// 3105-style journaled per-file snapshots for the dialer theme destination
// (`/var/mobile/Library/Caches/TelephonyUI-10`).
//
// Before a theme ZIP is extracted, every existing file that the theme would
// overwrite is copied into `Documents/WorkSlop/DialerBackup/<timestamp>/`
// alongside a `manifest.json` describing each entry:
//   - originalPath: absolute device path the file came from
//   - fileName: leaf name inside the snapshot directory
//   - byteCount, sha256
//   - existedBefore: false for files the theme ADDS (restore deletes them)
//
// Create-once semantics: the pristine snapshot is never overwritten — a
// second Apply reuses the first snapshot. Restore writes snapshots back via
// the bad_query geod lease and deletes theme-added files.

struct DialerBackupManifestEntry: Codable {
    let originalPath: String
    let fileName: String
    let byteCount: Int
    let sha256: String
    let existedBefore: Bool
}

struct DialerBackupManifest: Codable {
    let createdAt: Date
    let destinationRoot: String
    let entries: [DialerBackupManifestEntry]
}

enum DialerBackupError: LocalizedError {
    case noSnapshot
    case manifestCorrupt
    case snapshotFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSnapshot:
            return "No dialer backup snapshot exists yet. Apply a theme first."
        case .manifestCorrupt:
            return "The dialer backup manifest is corrupt."
        case .snapshotFailed(let detail):
            return "Dialer snapshot failed: \(detail)"
        }
    }
}

enum DialerBackupStore {

    static let destinationRoot = "/var/mobile/Library/Caches/TelephonyUI-10"

    // MARK: Paths

    private static func backupsRoot() throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        let root = docs.appendingPathComponent("WorkSlop/DialerBackup", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// The pristine snapshot directory, or nil when none exists.
    static func existingSnapshotURL() -> URL? {
        guard let root = try? backupsRoot(),
              let children = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]) else { return nil }
        return children
            .filter { $0.hasDirectoryPath }
            .sorted {
                let d0 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let d1 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return d0 < d1
            }
            .first
    }

    static var hasSnapshot: Bool { existingSnapshotURL() != nil }

    static func snapshotDate() -> Date? {
        guard let url = existingSnapshotURL() else { return nil }
        return (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? nil
    }

    // MARK: Snapshot

    /// Snapshots every existing file under the destination paths the theme
    /// is about to write. `relativePaths` are the theme's destination-
    /// relative paths (after top-level folder stripping). Create-once: if a
    /// snapshot already exists it is reused and nothing is re-copied.
    /// - Returns: true when a NEW snapshot was created, false when an
    ///   existing pristine snapshot was reused.
    @discardableResult
    static func snapshotBeforeApply(relativePaths: [String]) throws -> Bool {
        if existingSnapshotURL() != nil { return false }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dir = try backupsRoot()
            .appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var entries: [DialerBackupManifestEntry] = []
        do {
            try BadQueryLeaseScope.withLibraryCachesLease {
                let fm = FileManager.default
                for rel in relativePaths {
                    let abs = (destinationRoot as NSString).appendingPathComponent(rel)
                    let leaf = (rel as NSString).lastPathComponent
                    guard !leaf.isEmpty else { continue }
                    if fm.fileExists(atPath: abs) {
                        let data = try Data(contentsOf: URL(fileURLWithPath: abs))
                        let snapName = "orig_\(entries.count)_\(leaf)"
                        try data.write(to: dir.appendingPathComponent(snapName), options: .atomic)
                        entries.append(DialerBackupManifestEntry(
                            originalPath: abs,
                            fileName: snapName,
                            byteCount: data.count,
                            sha256: sha256(data),
                            existedBefore: true))
                    } else {
                        entries.append(DialerBackupManifestEntry(
                            originalPath: abs,
                            fileName: "",
                            byteCount: 0,
                            sha256: "",
                            existedBefore: false))
                    }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw DialerBackupError.snapshotFailed(error.localizedDescription)
        }

        let manifest = DialerBackupManifest(createdAt: Date(),
                                            destinationRoot: destinationRoot,
                                            entries: entries)
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)
        return true
    }

    // MARK: Restore

    /// Restores the pristine snapshot: writes backed-up bytes back via the
    /// geod lease and deletes files the theme added. The snapshot is kept
    /// (create-once) so restore can run again after a later Apply.
    static func restore() throws -> (restored: Int, deleted: Int) {
        guard let dir = existingSnapshotURL() else { throw DialerBackupError.noSnapshot }
        let manifestURL = dir.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(DialerBackupManifest.self,
                                                       from: manifestData) else {
            throw DialerBackupError.manifestCorrupt
        }

        var restored = 0
        var deleted = 0
        try BadQueryLeaseScope.withLibraryCachesLease {
            let fm = FileManager.default
            for entry in manifest.entries {
                if entry.existedBefore {
                    let snapURL = dir.appendingPathComponent(entry.fileName)
                    let data = try Data(contentsOf: snapURL)
                    // Integrity check against the manifest before writing back.
                    guard sha256(data) == entry.sha256 else { continue }
                    try data.write(to: URL(fileURLWithPath: entry.originalPath), options: .atomic)
                    restored += 1
                } else {
                    if fm.fileExists(atPath: entry.originalPath) {
                        try fm.removeItem(atPath: entry.originalPath)
                        deleted += 1
                    }
                }
            }
        }
        return (restored, deleted)
    }

    // MARK: Helpers

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

// MARK: - User Data Backup (Task D)

/// "User Data Backup" — a DISTINCT backup task in the Backup feature.
///
/// On iOS 27 this snapshots reachable USER DATA — photos/videos and
/// settings — into the app's own container, with a manifest describing
/// every file. It is a separate backup mode from:
///   - the MobileGestalt stock snapshot (the pristine MobileGestalt plist,
///     kept by `BackupManager` / `GestaltBackupStore`), and
///   - the Liquid Glass Backup (the liquid-glass preference files only,
///     kept by `LiquidGlassBackupStore` for the Liquid Glass menu).
///
/// Honest scope: it can only snapshot files the bad_query sandbox escape
/// can actually reach on-device. Photos/videos come from the DCIM camera
/// roll; settings come from the mobile preferences directory. The snapshot
/// is size-capped (see `Limits`); anything beyond the cap is recorded in
/// the manifest as skipped — never silently dropped.
@MainActor
enum UserDataBackupStore {

    // MARK: Types

    /// One user-data backup snapshot.
    struct UserDataBackupInfo {
        let createdAt: Date
        let fileCount: Int
        let totalBytes: Int64
        /// Files seen but left out because of the size caps.
        let skippedCount: Int
        let skippedBytes: Int64
    }

    enum TaskError: LocalizedError {
        case unsupportedIOS
        case noReachableData
        case readFailed
        case restoreFailed
        case nothingToRestore

        var errorDescription: String? {
            switch self {
            case .unsupportedIOS:
                return "The User Data Backup needs iOS 27."
            case .noReachableData:
                return "No photos, videos, or settings files are reachable on this device."
            case .readFailed:
                return "Could not read the user-data backup snapshot."
            case .restoreFailed:
                return "Could not restore any files from the user-data backup."
            case .nothingToRestore:
                return "There is no user-data backup to restore yet."
            }
        }
    }

    /// Snapshot caps. Copying an unbounded camera roll could fill the app
    /// container, so the snapshot takes the newest files first up to these
    /// limits and records the rest as skipped.
    private enum Limits {
        static let maxMediaFiles = 300
        static let maxMediaBytes: Int64 = 1_500_000_000 // 1.5 GB
        static let maxSingleFileBytes: Int64 = 300_000_000 // 300 MB
        static let maxSettingsFiles = 500
        static let maxSettingsBytes: Int64 = 50_000_000 // 50 MB
    }

    private struct Manifest: Codable {
        struct Entry: Codable {
            let fileName: String // relative path under the snapshot dir
            let originalPath: String
            let byteCount: Int64
            let kind: String // "media" or "settings"
        }
        let createdAt: Date
        let entries: [Entry]
        let skippedCount: Int
        let skippedBytes: Int64
    }

    // MARK: Paths

    private static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkSlop/UserDataBackup", isDirectory: true)
    }

    private static var manifestURL: URL {
        root.appendingPathComponent("manifest.json")
    }

    private static var mediaRoots: [String] {
        ["/var/mobile/Media/DCIM", "/private/var/mobile/Media/DCIM"]
    }

    private static var settingsRoots: [String] {
        ["/var/mobile/Library/Preferences", "/private/var/mobile/Library/Preferences"]
    }

    private static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "dng", "raw", "rw2",
        "mov", "mp4", "m4v", "3gp",
    ]

    // MARK: Discovery

    private struct Candidate {
        let path: String
        let byteCount: Int64
        let modified: Date
        let kind: String
    }

    /// Newest-first media candidates from the first reachable DCIM root.
    private static func mediaCandidates() -> [Candidate] {
        guard let dcim = mediaRoots.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let enumerator = FileManager.default.enumerator(atPath: dcim) else { return [] }
        var out: [Candidate] = []
        for case let relative as String in enumerator {
            let ext = (relative as NSString).pathExtension.lowercased()
            guard mediaExtensions.contains(ext) else { continue }
            let full = (dcim as NSString).appendingPathComponent(relative)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: full),
                  let size = attrs[.size] as? NSNumber else { continue }
            let modified = (attrs[.modificationDate] as? Date) ?? .distantPast
            out.append(Candidate(path: full, byteCount: size.int64Value,
                                 modified: modified, kind: "media"))
        }
        return out.sorted { $0.modified > $1.modified }
    }

    /// Top-level settings plists from the first reachable Preferences root.
    private static func settingsCandidates() -> [Candidate] {
        guard let prefs = settingsRoots.first(where: { FileManager.default.fileExists(atPath: $0) }),
              let names = try? FileManager.default.contentsOfDirectory(atPath: prefs) else { return [] }
        var out: [Candidate] = []
        for name in names where name.hasSuffix(".plist") {
            let full = (prefs as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir),
                  !isDir.boolValue,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: full),
                  let size = attrs[.size] as? NSNumber else { continue }
            let modified = (attrs[.modificationDate] as? Date) ?? .distantPast
            out.append(Candidate(path: full, byteCount: size.int64Value,
                                 modified: modified, kind: "settings"))
        }
        return out.sorted { $0.modified > $1.modified }
    }

    // MARK: Public API

    static var hasBackup: Bool {
        FileManager.default.fileExists(atPath: manifestURL.path)
    }

    static func info() -> UserDataBackupInfo? {
        guard let manifest = readManifest() else { return nil }
        return UserDataBackupInfo(
            createdAt: manifest.createdAt,
            fileCount: manifest.entries.count,
            totalBytes: manifest.entries.reduce(0) { $0 + $1.byteCount },
            skippedCount: manifest.skippedCount,
            skippedBytes: manifest.skippedBytes
        )
    }

    /// Snapshots reachable user data (photos/videos + settings), newest
    /// first, within the caps. Create-once like the other backup tasks:
    /// an existing snapshot is returned untouched so Restore always goes
    /// back to the pre-tweak state.
    @discardableResult
    static func create() throws -> UserDataBackupInfo {
        guard WorkSlopSupport.isIOS27() else { throw TaskError.unsupportedIOS }
        if let existing = info() { return existing }

        var entries: [Manifest.Entry] = []
        var skippedCount = 0
        var skippedBytes: Int64 = 0

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Media: newest first, capped.
        var mediaBytes: Int64 = 0
        var mediaFiles = 0
        for candidate in mediaCandidates() {
            let overSingle = candidate.byteCount > Limits.maxSingleFileBytes
            let overCount = mediaFiles >= Limits.maxMediaFiles
            let overTotal = mediaBytes + candidate.byteCount > Limits.maxMediaBytes
            guard !overSingle, !overCount, !overTotal else {
                skippedCount += 1
                skippedBytes += candidate.byteCount
                continue
            }
            let relative = "media/\(mediaFiles)-\(URL(fileURLWithPath: candidate.path).lastPathComponent)"
            try copySnapshot(candidate.path, toRelative: relative)
            entries.append(Manifest.Entry(fileName: relative, originalPath: candidate.path,
                                          byteCount: candidate.byteCount, kind: "media"))
            mediaBytes += candidate.byteCount
            mediaFiles += 1
        }

        // Settings: top-level plists, capped.
        var settingsBytes: Int64 = 0
        var settingsFiles = 0
        for candidate in settingsCandidates() {
            let overCount = settingsFiles >= Limits.maxSettingsFiles
            let overTotal = settingsBytes + candidate.byteCount > Limits.maxSettingsBytes
            guard !overCount, !overTotal else {
                skippedCount += 1
                skippedBytes += candidate.byteCount
                continue
            }
            let relative = "settings/\(URL(fileURLWithPath: candidate.path).lastPathComponent)"
            try copySnapshot(candidate.path, toRelative: relative)
            entries.append(Manifest.Entry(fileName: relative, originalPath: candidate.path,
                                          byteCount: candidate.byteCount, kind: "settings"))
            settingsBytes += candidate.byteCount
            settingsFiles += 1
        }

        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: root)
            throw TaskError.noReachableData
        }

        let manifest = Manifest(createdAt: Date(), entries: entries,
                                skippedCount: skippedCount, skippedBytes: skippedBytes)
        let encoded = try JSONEncoder().encode(manifest)
        try encoded.write(to: manifestURL, options: .atomic)

        return UserDataBackupInfo(
            createdAt: manifest.createdAt,
            fileCount: entries.count,
            totalBytes: entries.reduce(0) { $0 + $1.byteCount },
            skippedCount: skippedCount,
            skippedBytes: skippedBytes
        )
    }

    /// Restores every snapshotted file over its original path through the
    /// bad_query lease + verified in-place write — the same primitive the
    /// other backup tasks use. Returns the number of files restored; throws
    /// when nothing could be restored.
    @discardableResult
    static func restore() throws -> Int {
        guard let manifest = readManifest() else { throw TaskError.nothingToRestore }
        var restored = 0
        var errors: [String] = []
        for entry in manifest.entries {
            do {
                let data = try Data(contentsOf: root.appendingPathComponent(entry.fileName))
                try BadQueryLeaseScope.withLease(forPath: entry.originalPath) {
                    try InodeWriter.writeVerifiedInPlace(data, to: entry.originalPath)
                }
                restored += 1
            } catch {
                errors.append("\(entry.originalPath): \(error.localizedDescription)")
            }
        }
        guard restored > 0 else {
            throw TaskError.restoreFailed
        }
        if !errors.isEmpty {
            // Partial success is still reported; the caller surfaces this.
            print("[UserDataBackup] \(errors.count) files failed to restore:\n" + errors.joined(separator: "\n"))
        }
        return restored
    }

    static func delete() throws {
        try FileManager.default.removeItem(at: root)
    }

    // MARK: Private

    private static func copySnapshot(_ sourcePath: String, toRelative relative: String) throws {
        let dest = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // FileManager copies in chunks — no need to buffer a whole
        // photo/video in memory here.
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(atPath: sourcePath, toPath: dest.path)
    }

    private static func readManifest() -> Manifest? {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return nil }
        let allPresent = manifest.entries.allSatisfy {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0.fileName).path)
        }
        return allPresent ? manifest : nil
    }
}

// MARK: - View model

/// Drives the User Data Backup UI.
@MainActor
final class UserDataBackupModel: ObservableObject {
    enum BusyTask { case backingUp, restoring }

    @Published private(set) var isBusy = false
    @Published private(set) var busyTask: BusyTask?
    @Published private(set) var statusMessage: String?
    @Published private(set) var warnings: [String] = []
    @Published private(set) var backupInfo: UserDataBackupStore.UserDataBackupInfo?

    var isIOS27: Bool { WorkSlopSupport.isIOS27() }

    func refresh() {
        backupInfo = UserDataBackupStore.info()
    }

    func createBackup() {
        guard !isBusy else { return }
        isBusy = true
        busyTask = .backingUp
        defer {
            isBusy = false
            busyTask = nil
            refresh()
        }
        do {
            let info = try UserDataBackupStore.create()
            backupInfo = info
            warnings = []
            var message = "User Data Backup created: \(info.fileCount) files."
            if info.skippedCount > 0 {
                message += " \(info.skippedCount) files skipped (size caps)."
            }
            statusMessage = message
        } catch {
            statusMessage = nil
            warnings = [error.localizedDescription]
        }
    }

    func restoreBackup() {
        guard !isBusy else { return }
        isBusy = true
        busyTask = .restoring
        defer {
            isBusy = false
            busyTask = nil
            refresh()
        }
        do {
            let restored = try UserDataBackupStore.restore()
            warnings = []
            statusMessage = "Restored \(restored) files. Reboot to take effect."
        } catch {
            statusMessage = nil
            warnings = [error.localizedDescription]
        }
    }

    func deleteBackup() {
        guard !isBusy else { return }
        do {
            try UserDataBackupStore.delete()
            backupInfo = nil
            warnings = []
            statusMessage = "User Data Backup deleted."
        } catch {
            warnings = [error.localizedDescription]
        }
    }
}

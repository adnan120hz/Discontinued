import Foundation

// MARK: - AFC media store

/// AFC-backed photo/video safety store for the Liquid Glass full-backup flow.
///
/// Adapted from the DESIGN of GoldenNugget-mobile's AFC media backup
/// (`Nugget/Core/AfcMediaBackup.swift`) — no source code was copied; this is
/// an original implementation of that design:
///
/// - Pull the bulk media trees (`DCIM`, `PhotoStreamsData`) over AFC into
///   the app container, streamed in chunks so a large video never has to
///   exist in memory.
/// - Write to a `.partial` sidecar first; a cancelled or failed transfer
///   must never leave a short file a later run would treat as complete.
/// - Verify each file's size against what the device reported BEFORE any
///   delete. A file whose copy does not match keeps its original, always.
/// - Keep a JSON manifest per file (source path, stored name, size,
///   verified flag). The device-original deletion is tracked per file —
///   it is the only irreversible half of the operation.
/// - Manual push-back and empty-store actions; the store is the app's own
///   directory, never the backup's `MediaDomain` rows (a manifest prune
///   would drop those).
///
/// Storage: `Documents/WorkSlop/LGMedia/<tree>/…` + `lg-media.json`.
/// Photo metadata (`PhotoData`) is deliberately NOT pulled — it is not
/// listable over the media AFC service and is not bulk media.
@MainActor
enum LGMediaStore {

    /// The bulk media trees. Narrow on purpose: only actual photo/video
    /// files move.
    static let trees = ["DCIM", "PhotoStreamsData"]

    /// 4 MB stream chunks: trades memory against syscall count, not against
    /// a per-file connection.
    private static let chunkSize = 4 << 20

    /// Largest single file the push-back will write over AFC in one call.
    /// A file that does not fit is reported and skipped rather than risking
    /// a memory kill mid-restore; the local copy is left untouched.
    private static let inlineWriteLimit: Int64 = 64 << 20

    // MARK: - Manifest

    /// One stored file's record.
    struct Entry: Codable {
        /// Device-side absolute path, e.g. "/DCIM/100APPLE/IMG_0001.JPG".
        var source: String
        /// Path inside the store, e.g. "DCIM/100APPLE/IMG_0001.JPG".
        var storedAs: String
        var size: Int64
        /// True only after the pulled copy verified against the device size.
        var verified: Bool
        /// True only when the device original was removed after verification.
        var deviceOriginalRemoved: Bool
    }

    struct Manifest: Codable {
        var version: Int = 1
        var entries: [Entry] = []
    }

    /// Store summary for the UI.
    struct StoreInfo {
        let fileCount: Int
        let totalBytes: Int64
        let allVerified: Bool

        var summary: String {
            let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            let verified = allVerified ? "all verified" : "unverified files present"
            return "\(fileCount) files • \(size) • \(verified)"
        }
    }

    // MARK: - Paths

    private static var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkSlop/LGMedia", isDirectory: true)
    }

    private static var manifestURL: URL {
        root.appendingPathComponent("lg-media.json")
    }

    // MARK: - State

    static var hasStore: Bool {
        FileManager.default.fileExists(atPath: manifestURL.path)
    }

    static func info() -> StoreInfo? {
        guard let manifest = readManifest(), !manifest.entries.isEmpty else { return nil }
        return StoreInfo(
            fileCount: manifest.entries.count,
            totalBytes: manifest.entries.reduce(0) { $0 + $1.size },
            allVerified: manifest.entries.allSatisfy { $0.verified })
    }

    // MARK: - Pull

    /// Pull every media file into the store, then — only if
    /// `deletingOriginals` is set — remove each one from the device AFTER its
    /// size has been verified against what the device reported for that path.
    ///
    /// Ordering is the whole point: write, close, verify, and only then
    /// delete. Pull failures are fatal — once originals are deleted this
    /// store is the only copy, so a silently skipped file is data loss.
    ///
    /// NOTE: the UI calls this with `deletingOriginals: false` (pure safety
    /// copy). Deleting device originals is implemented and verified-first,
    /// but is intentionally not exposed in the UI until the full restore
    /// path is device-tested — removing the only other copy of someone's
    /// photos without a proven push-back would be reckless.
    static func pull(channel: LGDeviceChannel,
                     deletingOriginals: Bool,
                     onProgress: @escaping (String) -> Void) async throws -> Manifest {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        // Survey first: the confirmation-worthy numbers without transferring.
        // A tree that cannot be listed is skipped with a note — silently
        // dropping it would hide missing photos; failing the whole pull
        // over one absent tree would be worse.
        var files: [(path: String, size: Int64)] = []
        var total: Int64 = 0
        var skippedSymlinks = 0
        for tree in trees {
            let listed: [LGAfcEntry]
            do {
                listed = try await walk(channel: channel, path: "/" + tree)
            } catch {
                onProgress("Media: /\(tree) is not listable — skipped")
                continue
            }
            for entry in listed {
                if entry.linkTarget != nil { skippedSymlinks += 1; continue }
                files.append((entry.path, entry.size))
                total += entry.size
            }
        }
        guard !files.isEmpty else {
            throw LGChannelError.transferFailed(
                "Media pull: no files found under \(trees.joined(separator: ", ")). " +
                "Nothing was stored.")
        }
        onProgress("Media: \(files.count) files, " +
                   ByteCountFormatter.string(fromByteCount: total, countStyle: .file))

        var manifest = Manifest()
        var done: Int64 = 0

        for file in files {
            let relative = String(file.path.dropFirst()) // drop the leading "/"
            let destination = root.appendingPathComponent(relative)
            try fm.createDirectory(at: destination.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)

            let partial = destination.appendingPathExtension("partial")
            try? fm.removeItem(at: partial)
            fm.createFile(atPath: partial.path, contents: nil)
            let handle = try FileHandle(forWritingTo: partial)

            var written: Int64 = 0
            do {
                try await channel.afcStreamFile(path: file.path, chunkSize: chunkSize) { chunk in
                    try handle.write(contentsOf: chunk)
                    written += Int64(chunk.count)
                }
                try handle.close()
            } catch {
                try? handle.close()
                try? fm.removeItem(at: partial)
                throw LGChannelError.transferFailed(
                    "Media pull: \(file.path) failed after \(written) bytes — no original was removed.")
            }

            // Verify before the irreversible half. The device's own reported
            // size is the reference; our written byte count is a cross-check.
            let copied = (try? fm.attributesOfItem(atPath: partial.path)[.size] as? NSNumber)??
                .int64Value ?? -1
            guard copied == file.size, written == file.size else {
                try? fm.removeItem(at: partial)
                throw LGChannelError.transferFailed(
                    "Media pull: \(file.path) size mismatch — device reports \(file.size), " +
                    "wrote \(copied) / \(written). Original kept.")
            }

            try? fm.removeItem(at: destination)
            try fm.moveItem(at: partial, to: destination)

            var removed = false
            if deletingOriginals {
                do {
                    try await channel.afcDelete(path: file.path)
                    removed = true
                } catch {
                    // The copy is already verified, so a failed delete is the
                    // lesser problem — reported, not fatal.
                    onProgress("Media: could not remove \(file.path) — the verified copy is intact")
                }
            }

            manifest.entries.append(Entry(source: file.path, storedAs: relative,
                                          size: file.size, verified: true,
                                          deviceOriginalRemoved: removed))
            done += file.size
            onProgress("Media: \(relative) — " +
                       ByteCountFormatter.string(fromByteCount: done, countStyle: .file) + " total")
        }

        if skippedSymlinks > 0 {
            onProgress("Media: skipped \(skippedSymlinks) symlink(s)")
        }
        try writeManifest(manifest)
        return manifest
    }

    // MARK: - Push back

    /// Put everything back onto the device, verifying each write by the size
    /// the device reports afterwards. Local copies are kept — `emptyStore()`
    /// removes them once the user confirms the device side is intact.
    static func pushBack(channel: LGDeviceChannel,
                         onProgress: @escaping (String) -> Void) async throws {
        let manifest = try readManifest() ?? Manifest()
        guard !manifest.entries.isEmpty else {
            throw LGChannelError.transferFailed("The media store is empty — nothing to push back.")
        }
        let fm = FileManager.default
        var restored = 0
        var skipped = 0

        for entry in manifest.entries {
            let local = root.appendingPathComponent(entry.storedAs)
            guard fm.fileExists(atPath: local.path) else {
                onProgress("Push: missing \(entry.storedAs) — skipped")
                skipped += 1
                continue
            }
            let size = (try? fm.attributesOfItem(atPath: local.path)[.size] as? NSNumber)??
                .int64Value ?? 0
            guard size == entry.size else {
                onProgress("Push: \(entry.storedAs) changed on disk since pull — skipped")
                skipped += 1
                continue
            }
            guard size <= inlineWriteLimit else {
                onProgress("Push: \(entry.storedAs) is too large to write over AFC " +
                           "(\(size) bytes) — skipped, local copy kept")
                skipped += 1
                continue
            }

            // Every ancestor must exist before the leaf: one make-directory
            // call for "/DCIM/100APPLE" fails when "/DCIM" is absent.
            for directory in ancestors(of: entry.source) {
                try? await channel.afcMakeDirectory(path: directory)
            }

            let data = try Data(contentsOf: local)
            try await channel.afcWriteFile(path: entry.source, data: data)

            let written = (try? await channel.afcFileSize(entry.source)) ?? -1
            guard written == size else {
                onProgress("Push: \(entry.source) size mismatch — device reports \(written), " +
                           "expected \(size)")
                skipped += 1
                continue
            }
            restored += 1
            onProgress("Push: \(entry.source)")
        }
        onProgress("Push: \(restored) restored, \(skipped) skipped")
    }

    /// Empty the store. Only call this once the originals are back and
    /// verified on the device — the store may be the only copy.
    static func emptyStore() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: root.path) {
            try fm.removeItem(at: root)
        }
    }

    // MARK: - Internals

    /// Depth-first listing via the channel, symlinks reported (not followed).
    /// A directory that cannot be listed throws: silently skipping it would
    /// drop photos without a trace.
    private static func walk(channel: LGDeviceChannel, path: String) async throws -> [LGAfcEntry] {
        var out: [LGAfcEntry] = []
        for entry in try await channel.afcListDirectory(path) {
            if entry.isDirectory {
                out += try await walk(channel: channel, path: entry.path)
            } else {
                out.append(entry)
            }
        }
        return out
    }

    /// "/DCIM/100APPLE/IMG_0001.JPG" → ["/DCIM", "/DCIM/100APPLE"],
    /// outermost first — the order AFC needs them created in.
    private static func ancestors(of path: String) -> [String] {
        var parts = path.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return [] }
        parts.removeLast()
        var prefix = ""
        var out: [String] = []
        for part in parts {
            prefix += "/" + part
            out.append(prefix)
        }
        return out
    }

    private static func writeManifest(_ manifest: Manifest) throws {
        let data = try JSONEncoder().encode(manifest)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: manifestURL, options: .atomic)
    }

    private static func readManifest() -> Manifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }
}

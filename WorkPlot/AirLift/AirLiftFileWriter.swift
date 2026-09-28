import Foundation
import AirliftFFI

// MARK: - Errors

enum AirLiftWriteError: LocalizedError {
    /// No pairing file exists (pair first in AirLift Pairing), or pairing
    /// was revoked.
    case notPaired(String)
    /// The on-device AirLift exploit reported a failure. The message comes
    /// straight from the Rust core — surfaced as-is, never masked.
    case exploitFailed(String)
    /// The iOS 26.x bad_query fallback failed.
    case writeFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notPaired(let detail):
            "AirLift is not paired: \(detail)"
        case .exploitFailed(let detail):
            "AirLift write failed: \(detail)"
        case .writeFailed(let path, let underlying):
            "Failed to write \(path): \(underlying.localizedDescription)"
        }
    }
}

// MARK: - AirLiftFileWriter

/// File-write backend for the AirLift theme flows (dialer / passcode /
/// wallet).
///
/// ## iOS 27+ — genuine on-device AirLift
/// `writeFiles(_:toDirectory:)` stages the files in a temp dir and calls
/// `al_exploit_write_dir` from the bundled Rust core (ported from
/// AirCard-iOS, Mak5er, MIT — see `RustCore/`). The phone
/// talks to ITSELF over a loopback tunnel (LocalDevVPN → `10.7.0.1`,
/// `127.0.0.1` fallback): StreamingZip symlink → stage via
/// `streaming_zip_conduit` → forged `Books/Sync/Books.plist` via AFC → the
/// AirTraffic Books-sync path traversal (0xjohnnydev/airlift) → the payload
/// lands outside the Media scope at the requested absolute path. There is no
/// Mac involved anywhere in this path.
///
/// Prerequisites (surfaced honestly in the UI, not hidden):
/// - the phone is paired with itself (AirLift Pairing → RPPairing host, PIN
///   confirmed in Settings → Privacy & Security → Developer Mode);
/// - the official Apple Books app is installed and opened at least once
///   (the exploit forges its sync manifest);
/// - a loopback VPN app (e.g. LocalDevVPN) is active so the tunnel IPs are
///   reachable.
///
/// This is NOT device-verified by us — the IPA is unsigned and CI-built.
/// Failures from the exploit are surfaced verbatim to the caller.
///
/// ## iOS 26.x — bad_query fallback (NOT AirLift)
/// The AirLift exploit does not work on iOS 26.x. There, writes go through
/// the existing on-device bad_query sandbox escape (`BadQueryLeaseScope` +
/// `FileManager`) — the same primitive the rest of WorkSlop uses. UI copy
/// must NEVER call this path "AirLift".
///
/// MobileGestalt tweaks always stay on bad_query regardless of iOS version:
/// the airlift PoC does not work on the MobileGestalt plist.
///
/// ## Threading
/// `al_exploit_write_dir` BLOCKS until the sync completes. Call off the main
/// thread (all current call sites already dispatch to a background queue).
enum AirLiftFileWriter {

    // MARK: Public API

    /// Writes raw data to an absolute path outside the app sandbox.
    /// Single-file convenience on top of `writeFiles(_:toDirectory:)`.
    /// - Throws: `AirLiftWriteError` on failure.
    static func writeFile(data: Data, to path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        let leaf = (path as NSString).lastPathComponent
        try writeFiles([(name: leaf, data: data)], toDirectory: dir)
    }

    /// Serializes a dictionary as an XML plist and writes it to `path`.
    /// - Throws: `AirLiftWriteError` on failure.
    static func writePlist(_ plist: [String: Any], to path: String) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try writeFile(data: data, to: path)
    }

    // MARK: iOS 27+ — genuine on-device AirLift

    /// Writes a batch of files into `dir` in a SINGLE AirLift sync session.
    /// Batching matters: each session opens a tunnel, forges the Books sync
    /// manifest, runs the ATC sync, and tears down. One session per
    /// destination directory, not one per file.
    ///
    /// `name` must be a leaf filename (no "/") — `al_exploit_write_dir`
    /// only reads the top level of the staged dir (dotfiles are skipped).
    /// Group entries by parent directory and call once per group to
    /// preserve a zip's folder structure.
    /// - Throws: `AirLiftWriteError` on failure.
    static func writeFiles(_ files: [(name: String, data: Data)],
                           toDirectory dir: String) throws {
        guard !files.isEmpty else { return }
        // Prefer the genuine AirLift pairing exploit whenever a pairing file
        // exists (per AirCard-iOS, TelephonyUI-10 writes go through the
        // pairing exploit, not bad_query). Fall back to bad_query only when
        // not paired.
        let pairingPath = AirLiftManager.pairingFilePath()
        if FileManager.default.fileExists(atPath: pairingPath) {
            try writeFilesViaAirLift(files, toDirectory: dir)
        } else if WorkSlopSupport.isIOS27() {
            try writeFilesViaAirLift(files, toDirectory: dir)
        } else {
            for file in files {
                let leaf = (file.name as NSString).lastPathComponent
                try writeViaBadQuery(data: file.data,
                                     to: (dir as NSString).appendingPathComponent(leaf))
            }
        }
    }

    private static func writeFilesViaAirLift(_ files: [(name: String, data: Data)],
                                             toDirectory dir: String) throws {
        let pairingPath = AirLiftManager.pairingFilePath()
        guard FileManager.default.fileExists(atPath: pairingPath) else {
            throw AirLiftWriteError.notPaired(
                "no pairing file at \(pairingPath). " +
                "Pair this iPhone with itself in AirLift Pairing first."
            )
        }
        for file in files {
            let leaf = (file.name as NSString).lastPathComponent
            guard !leaf.isEmpty, leaf != "/" else {
                throw AirLiftWriteError.exploitFailed(
                    "refusing to write directory path \(file.name)")
            }
        }

        // Stage flat: al_exploit_write_dir reads the top level of this dir.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("workslop-airlift-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging,
                                                    withIntermediateDirectories: true)
            for file in files {
                let leaf = (file.name as NSString).lastPathComponent
                try file.data.write(to: staging.appendingPathComponent(leaf),
                                    options: .atomic)
            }
        } catch {
            throw AirLiftWriteError.writeFailed(path: dir, underlying: error)
        }
        defer { try? FileManager.default.removeItem(at: staging) }

        // Blocks — caller must be off the main thread.
        var outError: UnsafeMutablePointer<CChar>?
        let rc = pairingPath.withCString { pairC in
            staging.path.withCString { srcC in
                dir.withCString { dstC in
                    al_exploit_write_dir(pairC, srcC, dstC, nil, nil, &outError)
                }
            }
        }
        if rc != 0 {
            let detail: String
            if let errPtr = outError {
                detail = String(cString: errPtr)
                al_string_free(errPtr)
            } else {
                detail = "unknown error (rc=\(rc))"
            }
            throw AirLiftWriteError.exploitFailed(detail)
        }
    }

    // MARK: iOS 26.x fallback — bad_query (NOT AirLift)

    /// Writes via a short-lived bad_query sandbox extension for the parent
    /// directory, then a plain `FileManager` write. Same primitive the
    /// Gestalt flows use; only the destination paths differ.
    ///
    /// This is the iOS 26.x path only. It is NOT the AirLift exploit and
    /// must never be presented as such.
    private static func writeViaBadQuery(data: Data, to path: String) throws {
        let parent = (path as NSString).deletingLastPathComponent
        do {
            try BadQueryLeaseScope.withLease(forPath: parent) {
                let fm = FileManager.default
                try fm.createDirectory(atPath: parent,
                                       withIntermediateDirectories: true)
                let url = URL(fileURLWithPath: path)
                try data.write(to: url, options: .atomic)
            }
        } catch {
            throw AirLiftWriteError.writeFailed(path: path, underlying: error)
        }
    }
}

import Foundation
import AirliftFFI

// MARK: - Errors

enum AirLiftWriteError: LocalizedError {
    /// No pairing file exists (pair first in AirLift Pairing), or pairing
    /// was revoked.
    case notPaired(String)
    /// The on-device AirLift exploit reported a failure. The message comes
    /// straight from the Rust core — surfaced as-is, never masked. Stage
    /// tags ([tcp-connect], [pair-verify], [atc-sync], [stage], [afc],
    /// [tunnel], [format]) say exactly which stage died.
    case exploitFailed(String)
    /// AirLift is not supported on this iOS version at all.
    case notSupported(String)
    /// Local staging of the files failed before the exploit ran.
    case stagingFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notPaired(let detail):
            "AirLift is not paired: \(detail)"
        case .exploitFailed(let detail):
            "AirLift write failed: \(detail)"
        case .notSupported(let detail):
            "AirLift is not supported on this iOS version: \(detail)"
        case .stagingFailed(let path, let underlying):
            "Failed to stage files for \(path): \(underlying.localizedDescription)"
        }
    }
}

// MARK: - AirLiftFileWriter

/// File-write backend for the AirLift theme flows (passcode / wallet —
/// and the iOS 27 dialer theme).
///
/// ## iOS 26.x and 27.x — genuine on-device AirLift (explicit attempt)
/// `writeFiles(_:toDirectory:)` stages the files in a temp dir and calls
/// `al_exploit_write_dir` from the bundled Rust core (ported from
/// AirCard-iOS, Mak5er, MIT — see `RustCore/`). The phone
/// talks to ITSELF over a loopback tunnel (`127.0.0.1:49152` first, then
/// the loopback-VPN subnet): StreamingZip symlink → stage via
/// `streaming_zip_conduit` → forged `Books/Sync/Books.plist` via AFC → the
/// AirTraffic Books-sync path traversal (0xjohnnydev/airlift) → the payload
/// lands outside the Media scope at the requested absolute path. There is no
/// Mac involved anywhere in this path.
///
/// There is deliberately NO bad_query fallback in this writer: passcode and
/// wallet themes attempt AirLift on iOS 26 and 27 alike, and a failure is
/// surfaced honestly (with its pipeline stage) instead of silently
/// downgrading to another primitive.
///
/// Prerequisites (surfaced honestly in the UI, not hidden):
/// - the phone is paired (AirLift Pairing → RPPairing host on iOS 27, or a
///   pairing file imported on iOS 26);
/// - the official Apple Books app is installed and opened at least once
///   (the exploit forges its sync manifest);
/// - the tunnel targets are reachable — the exploit tries `127.0.0.1:49152`
///   first and warns when no `utun` interface is up, but continues anyway.
///
/// This is NOT device-verified by us — the IPA is unsigned and CI-built.
/// Failures from the exploit are surfaced verbatim to the caller, tagged
/// with the stage that failed ([tcp-connect] / [pair-verify] / [atc-sync] /
/// [stage] / [afc] / [tunnel] / [format]).
///
/// MobileGestalt tweaks always stay on bad_query regardless of iOS version:
/// the airlift PoC does not work on the MobileGestalt plist.
///
/// ## Threading
/// `al_exploit_write_dir` BLOCKS until the sync completes (up to ~120s per
/// tunnel attempt). Call off the main thread (all current call sites
/// already dispatch to a background queue) and pass a `progress` closure —
/// it is invoked on the main thread as the Rust core logs stage markers.
enum AirLiftFileWriter {

    /// Progress updates from the exploit run: human-readable stage text and
    /// a 0…1 fraction. Invoked on the main thread.
    typealias ProgressHandler = (_ stage: String, _ fraction: Double) -> Void

    // MARK: Public API

    /// Writes raw data to an absolute path outside the app sandbox.
    /// Single-file convenience on top of `writeFiles(_:toDirectory:)`.
    /// - Throws: `AirLiftWriteError` on failure.
    static func writeFile(data: Data, to path: String,
                          progress: ProgressHandler? = nil) throws {
        let dir = (path as NSString).deletingLastPathComponent
        let leaf = (path as NSString).lastPathComponent
        try writeFiles([(name: leaf, data: data)], toDirectory: dir,
                       progress: progress)
    }

    /// Serializes a dictionary as an XML plist and writes it to `path`.
    /// - Throws: `AirLiftWriteError` on failure.
    static func writePlist(_ plist: [String: Any], to path: String,
                           progress: ProgressHandler? = nil) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try writeFile(data: data, to: path, progress: progress)
    }

    // MARK: Genuine on-device AirLift (iOS 26.x and 27.x)

    /// Writes a batch of files into `dir` in a SINGLE AirLift sync session.
    /// Batching matters: each session opens a tunnel, forges the Books sync
    /// manifest, runs the ATC sync, and tears down. One session per
    /// destination directory, not one per file.
    ///
    /// `name` must be a leaf filename (no "/") — `al_exploit_write_dir`
    /// only reads the top level of the staged dir (dotfiles are skipped).
    /// Group entries by parent directory and call once per group to
    /// preserve a zip's folder structure.
    ///
    /// On iOS 26 AND 27 this attempts the AirLift exploit — there is no
    /// silent bad_query fallback. On any other iOS version it throws
    /// `AirLiftWriteError.notSupported` without touching the network.
    /// - Throws: `AirLiftWriteError` on failure.
    static func writeFiles(_ files: [(name: String, data: Data)],
                           toDirectory dir: String,
                           progress: ProgressHandler? = nil) throws {
        guard !files.isEmpty else { return }
        let v = WorkSlopSupport.currentVersion
        guard v.majorVersion == 26 || v.majorVersion == 27 else {
            throw AirLiftWriteError.notSupported(
                "AirLift writes need iOS 26.x or 27.x; this device is \(WorkSlopSupport.deviceLabel()).")
        }
        try writeFilesViaAirLift(files, toDirectory: dir, progress: progress)
    }

    private static func writeFilesViaAirLift(_ files: [(name: String, data: Data)],
                                             toDirectory dir: String,
                                             progress: ProgressHandler?) throws {
        let pairingPath = AirLiftManager.pairingFilePath()
        guard FileManager.default.fileExists(atPath: pairingPath) else {
            throw AirLiftWriteError.notPaired(
                "no pairing file at \(pairingPath). " +
                "Pair in AirLift Pairing first (Developer Mode on iOS 27, pairing-file import on iOS 26)."
            )
        }
        // Honest warning, not a blocker: the exploit tries 127.0.0.1:49152
        // first, then the loopback-VPN subnet. A missing utun interface
        // only makes the later targets unreachable.
        if !VPNCheck.isVPNActive() {
            progress?("No local dev VPN detected — trying 127.0.0.1:49152 directly…", 0.05)
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
            throw AirLiftWriteError.stagingFailed(path: dir, underlying: error)
        }
        defer { try? FileManager.default.removeItem(at: staging) }

        // Wire the Rust log stream to progress: each stage marker maps to a
        // fraction so the UI shows where the (blocking, up-to-120s) run is.
        let reporter = AirLiftProgressReporter(progress: progress)
        progress?("Staging files…", 0.1)

        // Blocks — caller must be off the main thread.
        var outError: UnsafeMutablePointer<CChar>?
        let rc = pairingPath.withCString { pairC in
            staging.path.withCString { srcC in
                dir.withCString { dstC in
                    withExtendedLifetime(reporter) {
                        al_exploit_write_dir(pairC, srcC, dstC,
                                             airLiftLogCallback,
                                             Unmanaged.passUnretained(reporter).toOpaque(),
                                             &outError)
                    }
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
        progress?("Done", 1.0)
    }
}

/// Forwards the Rust core's log lines to a Swift progress handler, mapping
/// known stage markers to (text, fraction). The callback fires on the
/// exploit's background thread; the handler is always invoked on main.
private final class AirLiftProgressReporter {
    private let progress: AirLiftFileWriter.ProgressHandler?
    init(progress: AirLiftFileWriter.ProgressHandler?) { self.progress = progress }

    func handle(line: String) {
        let entry: (String, Double)?
        if line.contains("trying RSD tunnel") || line.contains("connecting to lockdownd") {
            entry = ("Connecting to device tunnel…", 0.2)
        } else if line.contains("tunnel connected successfully") || line.contains("connected to lockdownd") {
            entry = ("Tunnel established", 0.35)
        } else if line.contains("opening AFC") {
            entry = ("Opening device storage…", 0.45)
        } else if line.contains("stage objects verified") || line.contains("staged Books.plist") {
            entry = ("Files staged on device", 0.6)
        } else if line.contains("starting com.apple.atc") {
            entry = ("Starting sync…", 0.7)
        } else if line.contains("SyncAllowed observed") {
            entry = ("Syncing…", 0.85)
        } else if line.contains("pairing format:") {
            entry = ("Pairing format detected", 0.15)
        } else {
            entry = nil
        }
        guard let (text, fraction) = entry, let progress else { return }
        DispatchQueue.main.async { progress(text, fraction) }
    }
}

private let airLiftLogCallback: ALLogCallback = { ctx, msg in
    guard let ctx = ctx, let msg = msg else { return }
    let reporter = Unmanaged<AirLiftProgressReporter>.fromOpaque(ctx).takeUnretainedValue()
    reporter.handle(line: String(cString: msg))
}

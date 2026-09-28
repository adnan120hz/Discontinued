import Foundation

// MARK: - Channel errors

/// Errors surfaced by the device-host channel layer.
enum LGChannelError: LocalizedError {
    /// The genuine on-device AirLift channel is not ready yet. This is the
    /// honest gate: `LGBackupEngine` falls back to the preference-snapshot
    /// flow instead of pretending a full backup happened.
    case backendUnavailable(String)
    /// Pairing is required before any device I/O.
    case pairingRequired
    /// A transfer failed part-way.
    case transferFailed(String)

    var errorDescription: String? {
        switch self {
        case .backendUnavailable(let detail):
            return detail
        case .pairingRequired:
            return "AirLift is not paired. Pair this device first (AirLift tab), then try again."
        case .transferFailed(let detail):
            return detail
        }
    }
}

// MARK: - AFC entry

/// One entry in an AFC directory listing.
///
/// `path` is the device-side absolute path, e.g. "/DCIM/100APPLE/IMG_0001.JPG".
struct LGAfcEntry {
    let path: String
    let size: Int64
    let isDirectory: Bool
    /// Non-nil for symlinks. Symlinks are never followed — following one
    /// could escape the media tree and duplicate content.
    let linkTarget: String?
    let modified: Date?
}

// MARK: - Channel protocol

/// Abstracts the host-to-device channel the Liquid Glass full-backup path
/// needs: pairing state, loopback-tunnel status, AFC file access, and the
/// mobilebackup2 pull/restore pair.
///
/// Why a protocol: the genuine on-device AirLift channel — pairing file in
/// Documents + loopback tunnel to the device's own services (the design the
/// parallel `r5/airlift-real` work is implementing, AirCard-iOS-style) — is
/// not in this tree yet. The engine codes against this abstraction and treats
/// `isReady == false` as an honest "not yet": it uses the preference-snapshot
/// fallback instead of faking a full backup.
///
/// All members are main-actor isolated: the concrete implementation reads
/// `AirLiftManager` (itself `@MainActor`) for pairing state.
@MainActor
protocol LGDeviceChannel: AnyObject {
    /// True when the loopback tunnel is up and the device is paired.
    var isReady: Bool { get }
    /// Plain-English reason `isReady` is false. Nil when ready.
    var readinessNote: String? { get }
    /// The pairing file this channel authenticates with, when one exists.
    var pairingFileURL: URL? { get }

    /// Pull a real mobilebackup2 backup of the device into `deviceDir`
    /// (`<working>/<udid>/`).
    func pullBackup(into deviceDir: URL, udid: String,
                    onProgress: @escaping (Double) -> Void) async throws
    /// Restore the prepared backup at `deviceDir` back onto the device.
    /// The restore does NOT reboot the device; the user reboots manually.
    func restore(deviceDir: URL, sourceIdentifier: String,
                 onProgress: @escaping (Double) -> Void) async throws

    // MARK: - AFC (media tree)

    func afcListDirectory(_ path: String) async throws -> [LGAfcEntry]
    func afcStreamFile(path: String, chunkSize: Int,
                       chunkHandler: @escaping (Data) throws -> Void) async throws
    func afcFileSize(_ path: String) async throws -> Int64
    func afcMakeDirectory(_ path: String) async throws
    func afcWriteFile(path: String, data: Data) async throws
    func afcDelete(path: String) async throws
}

// MARK: - AirLift-backed channel

/// The WorkSlop AirLift-backed device channel.
///
/// What is real today: readiness is genuinely checkable — AirLift pairing
/// state from `AirLiftManager` plus loopback-tunnel presence via `VPNCheck`
/// (the `utun` interface gate the passcode-theme and wallet flows already
/// use). The pairing file lives in Documents (`Documents/AirLiftPairing/`),
/// which is where the on-device AirLift channel authenticates from.
///
/// What is honestly gated: the device I/O half (mobilebackup2 pull/restore
/// and AFC) delegates to the genuine on-device AirLift layer, which is being
/// built on the parallel `r5/airlift-real` branch. Until that lands, every
/// I/O method throws `backendUnavailable` with a plain-English reason. That
/// throw is load-bearing — `LGBackupEngine` catches it and runs the honest
/// preference-snapshot fallback instead.
@MainActor
final class AirLiftDeviceChannel: LGDeviceChannel {
    static let shared = AirLiftDeviceChannel()
    private init() {}

    var isReady: Bool {
        AirLiftManager.shared.isPaired && VPNCheck.isVPNActive()
    }

    var readinessNote: String? {
        if !AirLiftManager.shared.isPaired {
            return "AirLift is not paired yet."
        }
        if !VPNCheck.isVPNActive() {
            return "The loopback tunnel is not up (no utun interface detected)."
        }
        return nil
    }

    var pairingFileURL: URL? {
        // Pairing-file-in-Documents: the imported pairing file is copied into
        // Documents/AirLiftPairing/ at import time, so the security-scoped
        // source URL is never needed again. This is the file the on-device
        // AirLift channel authenticates with.
        guard let file = AirLiftManager.shared.importedFile else { return nil }
        return URL(fileURLWithPath: file.storedPath)
    }

    // MARK: - Device I/O (gated on the real AirLift layer)

    /// INTEGRATION POINT (`r5/airlift-real`): pull a real mobilebackup2
    /// backup from the device itself — this app acting as host to its own
    /// device over the loopback tunnel + pairing file. Throws until the
    /// on-device AirLift layer lands; never fakes a backup.
    func pullBackup(into deviceDir: URL, udid: String,
                    onProgress: @escaping (Double) -> Void) async throws {
        throw LGChannelError.backendUnavailable(
            "The on-device AirLift backup channel is not ready yet " +
            "(in progress on the parallel airlift work). No device backup " +
            "was pulled — use the preference-snapshot fallback instead.")
    }

    /// INTEGRATION POINT (`r5/airlift-real`): hand the prepared backup back
    /// to the device via mobilebackup2. Throws until the on-device AirLift
    /// layer lands; never reports a fake restore.
    func restore(deviceDir: URL, sourceIdentifier: String,
                 onProgress: @escaping (Double) -> Void) async throws {
        throw LGChannelError.backendUnavailable(
            "The on-device AirLift restore channel is not ready yet " +
            "(in progress on the parallel airlift work). Nothing was " +
            "restored — the preference-snapshot flow restores in place instead.")
    }

    /// INTEGRATION POINT (`r5/airlift-real`): AFC directory listing over the
    /// device's media service.
    func afcListDirectory(_ path: String) async throws -> [LGAfcEntry] {
        throw LGChannelError.backendUnavailable(
            "AFC is not reachable yet — the on-device AirLift channel is still " +
            "being built (parallel airlift work).")
    }

    /// INTEGRATION POINT (`r5/airlift-real`): streamed AFC file read.
    func afcStreamFile(path: String, chunkSize: Int,
                       chunkHandler: @escaping (Data) throws -> Void) async throws {
        throw LGChannelError.backendUnavailable(
            "AFC is not reachable yet — the on-device AirLift channel is still " +
            "being built (parallel airlift work).")
    }

    func afcFileSize(_ path: String) async throws -> Int64 {
        throw LGChannelError.backendUnavailable(
            "AFC is not reachable yet — the on-device AirLift channel is still " +
            "being built (parallel airlift work).")
    }

    func afcMakeDirectory(_ path: String) async throws {
        throw LGChannelError.backendUnavailable(
            "AFC is not reachable yet — the on-device AirLift channel is still " +
            "being built (parallel airlift work).")
    }

    func afcWriteFile(path: String, data: Data) async throws {
        throw LGChannelError.backendUnavailable(
            "AFC is not reachable yet — the on-device AirLift channel is still " +
            "being built (parallel airlift work).")
    }

    func afcDelete(path: String) async throws {
        throw LGChannelError.backendUnavailable(
            "AFC is not reachable yet — the on-device AirLift channel is still " +
            "being built (parallel airlift work).")
    }
}

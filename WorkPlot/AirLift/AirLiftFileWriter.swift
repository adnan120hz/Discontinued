import Foundation

// MARK: - Write Backend

/// The backing route used by `AirLiftFileWriter`.
///
/// HONESTY NOTE — read before changing this:
/// The real airlift exploit (0xjohnnydev/airlift) is **Mac-hosted**: it runs
/// on a *paired Mac* over Wi-Fi/USB using MobileDevice.framework +
/// AirTrafficHost.framework, abusing Books sync (ATLegacyAssetLink /
/// ATAirlock) to write files outside the sync scope (verified in
/// /var/mobile/... paths). It runs with **no iOS app required** and
/// **cannot run inside this iOS process**.
///
/// What runs TODAY (`.onDeviceBadQuery`) is this app's existing on-device
/// primitive: a bad_query sandbox extension (`BadQueryLeaseScope`) +
/// `FileManager`. Every AirLift theme view routes through that until the
/// host-side integration is built and device-tested.
///
/// `.airTrafficHost` is the INTEGRATION POINT for that future work: the
/// host-side Mac tool plus a transport (e.g. local HTTP/USB mux) that this
/// iOS app can send write requests to. It is deliberately unimplemented —
/// throwing instead of pretending to work.
enum AirLiftWriteBackend {
    /// On-device writes via the bad_query sandbox escape. Active today.
    case onDeviceBadQuery
    /// Mac-hosted AirTraffic writes. Integration point — NOT implemented.
    case airTrafficHost
}

// MARK: - Errors

enum AirLiftWriteError: LocalizedError {
    /// The requested backend is not implemented on this build.
    case backendUnavailable(String)
    case writeFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .backendUnavailable(let detail):
            "AirLift write backend unavailable: \(detail)"
        case .writeFailed(let path, let underlying):
            "Failed to write \(path): \(underlying.localizedDescription)"
        }
    }
}

// MARK: - AirLiftFileWriter

/// File-write backend for the AirLift theme flows (dialer / passcode /
/// wallet).
///
/// ## Current behavior
/// `writeFile(data:to:)` / `writePlist(_:to:)` route through the on-device
/// bad_query primitive (`BadQueryLeaseScope` + `FileManager`), the same
/// sandbox escape the rest of WorkSlop uses. This is real, working code on
/// builds where bad_query is available — it is NOT the Mac-hosted AirTraffic
/// exploit, and the UI copy must not claim otherwise.
///
/// ## Future work (not device-verified)
/// To use the genuine airlift path:
/// 1. Build the Mac-side host tool from the airlift reference
///    (`~/workspace/workslop-refs/airlift`), device-test it against a paired
///    iPhone on iOS 26.6–27.x.
/// 2. Add a transport here (local socket / USB mux) that forwards
///    `writeFile` requests to that host tool.
/// 3. Implement `case .airTrafficHost` below and flip `backend`.
/// Until then, `.airTrafficHost` throws `backendUnavailable` on purpose.
enum AirLiftFileWriter {

    /// Active backend. Flip to `.airTrafficHost` only after the Mac-side
    /// integration is implemented and device-tested (see above).
    static var backend: AirLiftWriteBackend = .onDeviceBadQuery

    // MARK: Public API

    /// Writes raw data to an absolute path outside the app sandbox.
    /// - Throws: `AirLiftWriteError` on failure.
    static func writeFile(data: Data, to path: String) throws {
        switch backend {
        case .onDeviceBadQuery:
            try writeViaBadQuery(data: data, to: path)
        case .airTrafficHost:
            // INTEGRATION POINT: forward this write to the paired Mac's
            // AirTraffic host tool. Unimplemented by design — see the enum
            // docs above. Do not stub this out with a fake success.
            throw AirLiftWriteError.backendUnavailable(
                "The Mac-hosted AirTraffic integration is not implemented yet. " +
                "Writes currently go through the on-device bad_query primitive."
            )
        }
    }

    /// Serializes a dictionary as an XML plist and writes it to `path`.
    /// - Throws: `AirLiftWriteError` on failure.
    static func writePlist(_ plist: [String: Any], to path: String) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try writeFile(data: data, to: path)
    }

    // MARK: On-device primitive (active today)

    /// Writes via a short-lived bad_query sandbox extension for the parent
    /// directory, then a plain `FileManager` write. Same primitive the
    /// Gestalt flows use; only the destination paths differ.
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

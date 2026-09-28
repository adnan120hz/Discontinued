import Foundation

// MARK: - Exploit Path

/// The file-write route WorkSlop will use on the current device.
///
/// Picked by ``WorkSlopSupport/bestPath()`` from the running iOS version.
enum WorkSlopExploitPath {
    /// MobileGestalt cache writes via the bad_query sandbox escape (iOS 27).
    case badQuery
    /// Pairing-based file writes through AirLift (iOS 26.6 – 27.x).
    case airLift
    /// PosterBoard + dialer theming via bad_query (iOS 26.6 – 26.7).
    case legacyPosterBoard
    case unsupported
}

// MARK: - Version Support

/// Central version gating for WorkSlop's exploit paths.
///
/// Pragmatic rules, based on the *marketing* version
/// (`ProcessInfo.processInfo.operatingSystemVersion`):
///
/// | iOS range      | MobileGestalt (bad_query) | AirLift (pairing) | PosterBoard + dialer |
/// |---------------|---------------------------|-------------------|----------------------|
/// | < 26.6        | no                        | no                | no                   |
/// | 26.6 – 26.7.x | no                        | yes               | yes                  |
/// | 27.x          | yes                       | yes               | no                   |
/// | > 27          | no                        | no                | no                   |
enum WorkSlopSupport {

    // MARK: Current version

    /// The running OS version (marketing version, e.g. 27.0).
    static var currentVersion: OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }

    /// True when (major, minor, patch) >= the given triple.
    private static func isAtLeast(_ v: OperatingSystemVersion,
                                 major: Int, minor: Int, patch: Int = 0) -> Bool {
        (v.majorVersion, v.minorVersion, v.patchVersion) >= (major, minor, patch)
    }

    // MARK: Path availability

    /// iOS 27.0+ (dev beta 1–5, public beta 1–3, RC, stable) via bad_query.
    ///
    /// Build-string refinement is best-effort only: `DeviceCompatibility.Build`
    /// parsing is consulted for context (see ``betaOrSeedBuild()``), but an
    /// unknown or unparseable 27.0 build is treated as SUPPORTED (fail-open),
    /// because no patched build inside the 27.0 family has been confirmed.
    static func mobileGestaltAvailable() -> Bool {
        currentVersion.majorVersion == 27
    }

    /// iOS 26.6 through 26.7.x: PosterBoard + dialer theming via bad_query.
    static func legacyPosterBoardAvailable() -> Bool {
        let v = currentVersion
        return isAtLeast(v, major: 26, minor: 6) && v.majorVersion < 27
    }

    /// iOS 26.6 through 27.x: pairing-based file writes.
    ///
    /// The pairing handshake is version-tolerant across the whole bad_query
    /// range; the actual write primitive is chosen by `AirLiftFileWriter`.
    static func airLiftAvailable() -> Bool {
        let v = currentVersion
        return isAtLeast(v, major: 26, minor: 6) && v.majorVersion <= 27
    }

    // MARK: Best path

    /// The most capable available path, most-capable first.
    static func bestPath() -> WorkSlopExploitPath {
        if mobileGestaltAvailable() { return .badQuery }
        if airLiftAvailable() { return .airLift }
        if legacyPosterBoardAvailable() { return .legacyPosterBoard }
        return .unsupported
    }

    // MARK: Labels

    /// e.g. "iOS 27.0 • bad_query (MobileGestalt)".
    static func deviceLabel() -> String {
        let v = currentVersion
        let versionString: String = v.patchVersion > 0
            ? "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            : "iOS \(v.majorVersion).\(v.minorVersion)"
        switch bestPath() {
        case .badQuery:
            return "\(versionString) • bad_query (MobileGestalt)"
        case .airLift:
            return "\(versionString) • AirLift (pairing)"
        case .legacyPosterBoard:
            return "\(versionString) • bad_query (PosterBoard + dialer)"
        case .unsupported:
            return "\(versionString) • unsupported"
        }
    }

    // MARK: Build nuance (best-effort)

    /// Best-effort read of the 27.0 build flavor (dev beta / public beta /
    /// RC / stable) from the build string, e.g. "24A5390f".
    ///
    /// Returns `nil` when the build string is missing or unparseable — callers
    /// must treat that as *supported* (fail-open). A trailing letter seed
    /// (e.g. the "f" in 24A5390f) marks a seeded/beta build; RC and stable
    /// builds such as 24A435 / 24A437 carry no trailing letter.
    static func betaOrSeedBuild() -> Bool? {
        guard let raw = DeviceCompatibility.currentOS().build,
              let build = DeviceCompatibility.Build.parse(raw)
        else { return nil }
        return !build.seed.isEmpty
    }
}

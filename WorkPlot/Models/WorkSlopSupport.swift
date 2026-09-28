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
/// Rules are based on the *marketing* version
/// (`ProcessInfo.processInfo.operatingSystemVersion`), refined where needed
/// by the build-code database (`WorkSlopBuilds`, keyed off
/// `DeviceCompatibility.currentOS().build`).
///
/// | iOS range                       | MobileGestalt (bad_query) | AirLift (pairing) | PosterBoard + dialer |
/// |---------------------------------|---------------------------|-------------------|----------------------|
/// | < 26.6                          | no                        | no                | no                   |
/// | 26.6 – 26.7.x                   | no                        | yes               | yes                  |
/// | 27.x db 1–4 / pb 1–2            | yes                       | yes               | no                   |
/// | 27.x db 5+ / pb 3+ / RC / stable| no                        | yes (incl. dialer)| no                   |
/// | > 27                            | no                        | no                | no                   |
///
/// Unknown or unparseable 27.x builds are treated as SUPPORTED (fail-open):
/// no patched build inside the 27.x family has been confirmed.
enum WorkSlopSupport {

    // MARK: Current version

    /// The running OS version (marketing version, e.g. 27.0).
    static var currentVersion: OperatingSystemVersion {
        ProcessInfo.processInfo.operatingSystemVersion
    }

    /// True when running iOS 27.x. The backup-flow UI uses the full
    /// backup/restore path here.
    static func isIOS27() -> Bool {
        currentVersion.majorVersion == 27
    }

    /// True when running iOS 26.x. The backup-flow UI uses the partial
    /// (bookrestore) path here.
    static func isIOS26() -> Bool {
        currentVersion.majorVersion == 26
    }

    /// True when (major, minor, patch) >= the given triple.
    private static func isAtLeast(_ v: OperatingSystemVersion,
                                 major: Int, minor: Int, patch: Int = 0) -> Bool {
        (v.majorVersion, v.minorVersion, v.patchVersion) >= (major, minor, patch)
    }

    // MARK: Build channel

    /// Channels the running build is known under. Developer-beta and
    /// public-beta builds sometimes share a build string (e.g. 24A5390f is
    /// both dev beta 4 and public beta 2), so this returns all known channels.
    ///
    /// Returns `nil` when the build string is missing or unparseable, and an
    /// empty array when the build is well-formed but not listed in
    /// ``WorkSlopBuilds``. Both cases are fail-open in the predicates below.
    private static func buildChannels() -> [WorkSlopBuildChannel]? {
        guard let raw = DeviceCompatibility.currentOS().build,
              DeviceCompatibility.Build.parse(raw) != nil
        else { return nil }
        return WorkSlopBuilds.channels(forBuild: raw)
    }

    /// The primary build channel of the running system.
    ///
    /// Returns `.unknown` when the build string is well-formed but not listed
    /// in the database, and `nil` when the build string is missing or
    /// unparseable. (Do not edit: owned by the version-gating worker.)
    static func currentBuildChannel() -> WorkSlopBuildChannel? {
        guard let channels = buildChannels() else { return nil }
        return channels.first ?? .unknown
    }

    // MARK: Path availability

    /// iOS 27.x dev beta 1–4 and public beta 1–2 via bad_query.
    ///
    /// Resolved through the build-code database
    /// (`DeviceCompatibility.currentOS().build`). Unknown or unparseable
    /// 27.x builds are treated as SUPPORTED (fail-open), because no patched
    /// build inside the 27.x family has been confirmed.
    static func mobileGestaltAvailable() -> Bool {
        guard isIOS27() else { return false }
        guard let channels = buildChannels() else { return true }
        if channels.isEmpty { return true }
        return channels.contains { channel in
            switch channel {
            case .devBeta(let n): return (1...4).contains(n)
            case .publicBeta(let n): return (1...2).contains(n)
            case .rc, .stable, .unknown: return false
            }
        }
    }

    /// iOS 27.x RC, dev beta 5+, public beta 2+, or official stable: dialer
    /// theming is available through the AirLift pairing path.
    ///
    /// Earlier 27.x builds (dev beta 1–4, public beta 1) route dialer theming
    /// through bad_query instead (see ``mobileGestaltAvailable()``).
    /// Unknown or unparseable 27.x builds are treated as SUPPORTED
    /// (fail-open). (Do not edit: owned by the version-gating worker.)
    static func airLiftDialerAvailable() -> Bool {
        guard isIOS27() else { return false }
        guard let channels = buildChannels() else { return true }
        if channels.isEmpty { return true }
        return channels.contains { channel in
            switch channel {
            case .devBeta(let n): return n >= 5
            case .publicBeta(let n): return n >= 2
            case .rc, .stable: return true
            case .unknown: return false
            }
        }
    }

    /// iOS 26.6 through 26.7.x: PosterBoard + dialer theming via bad_query.
    static func legacyPosterBoardAvailable() -> Bool {
        let v = currentVersion
        return isAtLeast(v, major: 26, minor: 6) && v.majorVersion < 27
    }

    /// App Data reader via bad_query.
    ///
    /// Supported on iOS 18.x (any build), iOS 26.0 and 26.6.1, and
    /// iOS 27.0 dev beta 1–4 / public beta 1–2 (the same build-channel
    /// window as ``mobileGestaltAvailable()``).
    ///
    /// iOS 26 is gated by marketing version; iOS 18 by major version;
    /// iOS 27 by build channel from the build-code database. Unknown or
    /// unparseable 27.x builds are treated as SUPPORTED (fail-open),
    /// matching the other predicates — no patched 27.x build inside this
    /// window has been confirmed. Everything else is unsupported.
    static func appDataAvailable() -> Bool {
        let v = currentVersion
        if v.majorVersion == 18 { return true }
        if v.majorVersion == 26 {
            return (v.minorVersion == 0 && v.patchVersion == 0)
                || (v.minorVersion == 6 && v.patchVersion == 1)
        }
        guard isIOS27() else { return false }
        guard let channels = buildChannels() else { return true }
        if channels.isEmpty { return true }
        return channels.contains { channel in
            switch channel {
            case .devBeta(let n): return (1...4).contains(n)
            case .publicBeta(let n): return (1...2).contains(n)
            case .rc, .stable, .unknown: return false
            }
        }
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

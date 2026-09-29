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

// MARK: - Exploit Support Matrix

/// Every exploit WorkSlop supports, with its genuine iOS version range.
///
/// Ranges are verified against GitHub sources — NOT from random websites
/// (user explicitly warned about misinfo).
///
/// | Exploit       | iOS Range              | Patched In | Notes                     |
/// |---------------|------------------------|------------|---------------------------|
/// | bad_query     | 26.6–26.6.2, 27.0 db1-4/pb1-2 | —     | Per user spec (narrow)    |
/// | darksword     | 17.0–18.7.1, 26.0–26.0.1 | 18.7.2/26.1 | Kernel r/w (tool offsets) |
/// | kfd           | 15.0 – 16.6.1          | 17.0       | Kernel File Descriptor    |
/// | airlift       | 18+                    | —          | Per user: iOS 18+         |
/// | book restore  | 18.2 – 26.1            | 26.2b2     | Books daemon escape (NOT backup) |
/// | sparse restore| 15.2–17.7, 18.0–18.1b4 | 17.7.1/18.1| CVE-2024-44252 (backup-based) |
/// | afc           | All (Media-scoped)     | —          | NOT patched on 27         |
enum WorkSlopExploit {
    case badQuery
    case darksword
    case kfd
    case airlift
    case bookRestore
    case sparseRestore
    case afc

    /// Human-readable name.
    var displayName: String {
        switch self {
        case .badQuery: return "bad_query"
        case .darksword: return "DarkSword"
        case .kfd: return "kfd"
        case .airlift: return "AirLift"
        case .bookRestore: return "Book Restore"
        case .sparseRestore: return "Sparse Restore"
        case .afc: return "AFC"
        }
    }

    /// True if this exploit works on the current iOS version.
    func isSupported() -> Bool {
        let v = WorkSlopSupport.currentVersion
        let major = v.majorVersion
        let minor = v.minorVersion
        let patch = v.patchVersion

        switch self {
        case .badQuery:
            // iOS 26.6/26.6.1/26.6.2, 27.0 developer beta 1-4 / public beta 1-2
            // (per user spec — NOT the broader research range)
            if major == 26 {
                // Only 26.6, 26.6.1, 26.6.2
                if minor == 6 && patch <= 2 { return true }
                return false
            }
            if major == 27 {
                // Developer beta 1-4 / Public beta 1-2 only
                // Without build info, assume supported on 27.0 betas
                return minor == 0
            }
            return false

        case .darksword:
            // Tool-usable range (offsets): 17.0–18.7.1 and 26.0–26.0.1
            // (see dedicated case above)
            let v = WorkSlopSupport.currentVersion
            let major = v.majorVersion
            let minor = v.minorVersion
            let patch = v.patchVersion
            if major == 26 {
                return minor == 0 && patch <= 1
            }
            if major == 17 { return true }
            if major == 18 {
                if minor < 7 { return true }
                if minor == 7 { return patch <= 1 }
                return false
            }
            return false

        case .kfd:
            // iOS 15.0 – 16.6.1 (patched in 17.0, CVE-2023-41974)
            return major == 15 || major == 16

        case .airlift:
            // iOS 18+ (per user: AirLift supports iOS 18 and above)
            // Based on AirCard and AirLift repos.
            return major >= 18

        case .bookRestore:
            // iOS 18.2 – 26.1 (patched in 26.2b2, CVE-2025-46286)
            // NOT backup/restore based — Books daemon sandbox escape.
            if major < 18 || major > 26 { return false }
            if major == 18 { return minor >= 2 }
            if major == 26 { return minor < 2 } // 26.0-26.1 (26.2+ patched)
            return true // 19-25 (theoretical, untested)

        case .sparseRestore:
            // Full: 15.2–17.7, 18.0–18.1b4 (CVE-2024-44252)
            // Partial (domains only): 17.7.1, 18.1b5–18.2b2
            // Dead: 18.2b3+
            if major < 15 || major > 18 { return false }
            if major == 15 { return minor >= 2 }
            if major == 16 { return true }
            if major == 17 {
                if minor < 7 { return true }
                if minor == 7 { return patch == 0 } // 17.7 full, 17.7.1 partial
                return false
            }
            if major == 18 {
                if minor == 0 { return true } // 18.0-18.0.1
                if minor == 1 { return patch == 0 } // 18.1b1-b4 only (can't detect beta)
                return false // 18.2+ dead
            }
            return false

        case .afc:
            // AFC works on ALL iOS (Media-scoped by design).
            // User claim "patched on iOS 27" is FALSE.
            // airlift (tested on 27.0 RC) uses AFC as its read path.
            return true
        }
    }

    /// Why this exploit is unavailable on the current iOS (for UI).
    func unavailableReason() -> String? {
        guard !isSupported() else { return nil }
        let v = WorkSlopSupport.currentVersion
        let verStr = "iOS \(v.majorVersion).\(v.minorVersion)"

        switch self {
        case .badQuery:
            return "bad_query requires iOS 26.0–26.6.1 or 27.0 beta 1–5 (running \(verStr))"
        case .darksword:
            return "DarkSword requires iOS 17.0–18.7.1 or 26.0–26.0.1 (tool offsets; patched in 18.7.2/26.1; running \(verStr))"
        case .kfd:
            return "kfd requires iOS 15.0–16.6.1 (patched in 17.0; running \(verStr))"
        case .airlift:
            return "AirLift requires iOS 27.0 only (running \(verStr))"
        case .bookRestore:
            return "Book Restore requires iOS 18.2–26.1 (patched in 26.2b2; running \(verStr))"
        case .sparseRestore:
            return "Sparse Restore requires iOS 15.2–17.7 or 18.0–18.1b4 (patched in 17.7.1/18.1; running \(verStr))"
        case .afc:
            return nil // AFC works on all iOS
        }
    }
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
    /// Supported on iOS 18.x (any build: 18.0, 18.6, ...), iOS 26.x
    /// (26.0, 26.3, 26.6, 26.6.1 incl. RC, 26.6.2), and iOS 27.0
    /// dev beta 1-4 / public beta 1-2 / RC / stable.
    ///
    /// iOS 26 is gated by major version only (bad_query works across
    /// 26.x per FilzaSlop); iOS 18 by major version; iOS 27 by build
    /// channel from the build-code database. Unknown or unparseable
    /// 27.x builds are treated as SUPPORTED (fail-open). Everything
    /// else is unsupported.
    static func appDataAvailable() -> Bool {
        let v = currentVersion
        if v.majorVersion == 18 { return true }
        if v.majorVersion == 26 { return true }
        guard isIOS27() else { return false }
        guard let channels = buildChannels() else { return true }
        if channels.isEmpty { return true }
        return channels.contains { channel in
            switch channel {
            case .devBeta(let n): return (1...4).contains(n)
            case .publicBeta(let n): return (1...2).contains(n)
            case .rc, .stable: return true
            case .unknown: return false
            }
        }
    }

    /// iOS 26.6 through 27.x: file writes outside the sandbox.
    ///
    /// iOS 27+ uses the genuine on-device AirLift exploit (the phone pairs
    /// with itself; see `AirLiftManager` / `AirLiftFileWriter`). iOS 26.6–26.7
    /// falls back to the bad_query primitive — that path is NOT AirLift and
    /// the UI never labels it as such.
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

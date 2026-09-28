import Foundation

// MARK: - Build Channel

/// Release channel of a specific Apple build.
enum WorkSlopBuildChannel: Equatable {
    case devBeta(Int)
    case publicBeta(Int)
    case rc
    case stable
    case unknown
}

// MARK: - Build Database

/// Lookup table mapping Apple build strings to their marketing version and
/// release channel. Backs the build-granular gating in `WorkSlopSupport`
/// (MobileGestalt availability, AirLift dialer theming).
///
/// Build numbers were researched from Apple press/dev-release coverage
/// (AppleInsider, iClarified, BetaProfiles, MacRumors forums, ipsw.dev).
/// Entries marked "best-effort" could not be fully verified; unknown builds
/// are fail-open in the predicates, so an imperfect table degrades to the
/// old version-only behavior rather than locking users out.
///
/// Some builds shipped on both channels (public betas mirror a developer
/// beta build); those list both channels, developer beta first, and
/// ``channel(forBuild:)`` returns the first one as primary.
enum WorkSlopBuilds {

    /// Lowercased build string → (marketing version, channels).
    static let database: [String: (version: String, channels: [WorkSlopBuildChannel])] = [
        // MARK: iOS 26.6 family
        // best-effort: RC build seen on ipsw.dev; public 26.6 build unverified
        // (point-release RCs are usually identical to the public build).
        "23g71": ("26.6", [.stable]),
        // user-confirmed.
        "23g82": ("26.6.1", [.stable]),
        // best-effort: one report (AppleInsider) claims the public 26.6.1
        // shipped as 23G83 rather than the 23G82 RC; kept so both resolve.
        "23g83": ("26.6.1", [.stable]),
        "23g90": ("26.6.2", [.stable]),

        // MARK: iOS 26.7 family
        // best-effort: RC build; public release assumed identical.
        "23h24": ("26.7", [.stable]),

        // MARK: iOS 27.0 developer betas
        "24a5355q": ("27.0", [.devBeta(1)]),
        "24a5370h": ("27.0", [.devBeta(2)]),
        // dev beta 3 and public beta 1 share this build.
        "24a5380h": ("27.0", [.devBeta(3), .publicBeta(1)]),
        // dev beta 4 and public beta 2 share this build.
        "24a5390f": ("27.0", [.devBeta(4), .publicBeta(2)]),
        // dev beta 5 and public beta 3 share this build.
        "24a5408d": ("27.0", [.devBeta(5), .publicBeta(3)]),
        "24a5418b": ("27.0", [.devBeta(6)]),
        "24a5424a": ("27.0", [.devBeta(7)]),
        "24a5430a": ("27.0", [.devBeta(8)]),

        // MARK: iOS 27.0 release candidates and stable
        "24a435": ("27.0", [.rc]),
        // Official public release, Sep 14 2026. Apple's feed briefly labeled
        // this build "iOS 27.0 RC" (Sep 11), so it may also have served as RC 2.
        "24a437": ("27.0", [.stable]),
    ]

    /// Normalizes a raw build string for lookup (trims, lowercases — some
    /// sources print the seed letter uppercase, e.g. "24A5380H").
    private static func key(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// (marketing version, channels) for a build string, or `nil` when the
    /// build is not listed.
    static func info(forBuild raw: String) -> (version: String, channels: [WorkSlopBuildChannel])? {
        database[key(raw)]
    }

    /// All known channels for a build string; empty when unlisted.
    static func channels(forBuild raw: String) -> [WorkSlopBuildChannel] {
        info(forBuild: raw)?.channels ?? []
    }

    /// Primary channel for a build string, or `.unknown` when unlisted.
    static func channel(forBuild raw: String) -> WorkSlopBuildChannel {
        channels(forBuild: raw).first ?? .unknown
    }
}

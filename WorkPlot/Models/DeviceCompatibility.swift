import Foundation

// MARK: - Compatibility

/// Supported OS range for WorkSlop:
///   iOS 26.6 – 26.7.x  → supported (limited: PosterBoard + dialer via
///                          bad_query, plus AirLift pairing file writes)
///   iOS 27.x           → supported (full: bad_query MobileGestalt writes,
///                          plus AirLift pairing file writes)
/// Anything below 26.6 or above 27.x is unsupported.
///
/// Version gating details live in `WorkSlopSupport`; this enum keeps the
/// user-facing status/messages.
enum DeviceCompatibility {

    /// Legacy reference build from the old class-13 matrix (27.0 beta 4).
    /// Kept for historical context; the current matrix (see `evaluate`)
    /// treats all 27.x builds as supported. `Build.parse` is still used by
    /// `WorkSlopSupport` for best-effort build-flavor detection.
    static let newestSupportedBuild = Build(alpha: "A", number: 5390, seed: "f")

    struct OSInfo {
        let version: OperatingSystemVersion
        let build: String?
    }

    enum Status {
        case supported
        case unsupported(reason: String)
    }

    struct Build: Comparable {
        let alpha: String
        let number: Int
        let seed: String

        static func < (lhs: Build, rhs: Build) -> Bool {
            if lhs.alpha != rhs.alpha { return lhs.alpha < rhs.alpha }
            if lhs.number != rhs.number { return lhs.number < rhs.number }
            return lhs.seed < rhs.seed
        }

        /// "24A5390f" -> (alpha: "A", number: 5390, seed: "f")
        static func parse(_ raw: String) -> Build? {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let letterStart = s.firstIndex(where: { $0.isLetter }) else { return nil }
            var letterEnd = letterStart
            while letterEnd < s.endIndex, s[letterEnd].isLetter {
                letterEnd = s.index(after: letterEnd)
            }
            let alpha = String(s[letterStart..<letterEnd]).uppercased()

            let numStart = letterEnd
            var numEnd = numStart
            while numEnd < s.endIndex, s[numEnd].isNumber {
                numEnd = s.index(after: numEnd)
            }
            guard numStart < numEnd, let number = Int(String(s[numStart..<numEnd])) else {
                return nil
            }
            let seed = String(s[numEnd...])
            return Build(alpha: alpha, number: number, seed: seed)
        }
    }

    /// Reads the marketing OS version and build string of the running system.
    static func currentOS() -> OSInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var build: String? = nil
        let paths = [
            "/System/Library/CoreServices/SystemVersion.plist",
            "/System/Library/CoreServices/.system_version.plist"
        ]
        for p in paths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: p)),
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let b = plist["ProductBuildVersion"] as? String {
                build = b
                break
            }
        }
        return OSInfo(version: version, build: build)
    }

    /// Evaluates support against the WorkSlop matrix:
    /// unsupported below iOS 26.6 or above iOS 27.x; 26.6–26.7.x is
    /// supported-but-limited; 27.x is fully supported.
    static func evaluate(version: OperatingSystemVersion,
                         build: String?) -> Status {
        let major = version.majorVersion
        let minor = version.minorVersion

        if major < 26 || (major == 26 && minor < 6) {
            return .unsupported(reason:
                "This app requires iOS 26.6 or newer. You are running iOS \(major).\(minor).")
        }

        if major > 27 {
            return .unsupported(reason:
                "iOS \(major) is not supported. WorkSlop is verified on iOS 26.6 – 26.7.x (PosterBoard + AirLift) and iOS 27.x (bad_query MobileGestalt).")
        }

        // iOS 26.6–26.7.x → supported (limited).
        // iOS 27.x        → supported (full bad_query MobileGestalt).
        // The `build` string is intentionally not used to reject 27.x builds:
        // see WorkSlopSupport.mobileGestaltAvailable() (fail-open on 27.0).
        return .supported
    }

    static var currentStatus: Status {
        let os = currentOS()
        return evaluate(version: os.version, build: os.build)
    }

    static var currentInfo: OSInfo { currentOS() }

    // MARK: - Feature gating

    /// Full MobileGestalt tweaks need iOS 27 (bad_query). iOS 26.6–26.7.x is
    /// limited to PosterBoard + dialer theming and AirLift pairing writes.
    static func fullFeatureStatus(feature: String) -> Status {
        guard WorkSlopSupport.mobileGestaltAvailable() else {
            let label = WorkSlopSupport.deviceLabel()
            return .unsupported(reason:
                "\(feature) requires iOS 27 with full MobileGestalt access (bad_query). \(label): only PosterBoard, dialer theming and AirLift pairing are available here.")
        }
        return .supported
    }

    static var supportsFullFeatureSet: Bool {
        if case .supported = fullFeatureStatus(feature: "This feature") { return true }
        return false
    }
}
